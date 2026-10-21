# Test harness

Policy: the `go-testing` rule. Day-to-day authoring: `testing-go-backends`.

## internal/platform/testdb

```go
// Package testdb gives integration tests a fresh migrated database with the real roles and a
// pool as the runtime role (RLS applies). APP_TEST_DATABASE_URL is a superuser DSN; -short skips,
// a full run without it fails, so integration tests never skip silently.
package testdb

type DB struct {
	App, System, Admin  *pgxpool.Pool // runtime role (RLS), system role (global jobs), superuser (setup, assertions)
	AppURL, MigratorURL string
}

var (
	rolesOnce sync.Once
	rolesErr  error // a failed role setup fails every later test with the same cause
)

func New(t testing.TB) *DB {
	t.Helper()
	if testing.Short() {
		t.Skip("integration test: needs Postgres")
	}
	admin := os.Getenv("APP_TEST_DATABASE_URL")
	if admin == "" {
		t.Fatal("APP_TEST_DATABASE_URL is not set (docker compose up -d postgres, or use -short)")
	}
	rolesOnce.Do(func() { rolesErr = ensureRoles(admin) })
	if rolesErr != nil {
		t.Fatalf("test roles: %v", rolesErr)
	}
	name := "app_test_" + strings.ReplaceAll(ids.New(), "-", "")[:20]
	exec(t, admin, fmt.Sprintf(`CREATE DATABASE %s OWNER app_migrator`, name))
	t.Cleanup(func() { exec(t, admin, fmt.Sprintf(`DROP DATABASE IF EXISTS %s WITH (FORCE)`, name)) })

	migratorURL := withUserAndDB(t, admin, "app_migrator", testPassword, name)
	appURL := withUserAndDB(t, admin, "app_runtime", testPassword, name)
	if err := migrate.Up(context.Background(), migratorURL); err != nil {
		t.Fatalf("migrate: %v", err)
	}
	return &DB{
		App:         pool(t, appURL),
		System:      pool(t, withUserAndDB(t, admin, "app_system", testPassword, name)),
		Admin:       pool(t, withUserAndDB(t, admin, "", "", name)),
		AppURL:      appURL,
		MigratorURL: migratorURL,
	}
}
```

`ensureRoles(admin) error` creates the bootstrap roles with test passwords if they are missing and returns any error instead of failing the first test only. `go test ./...` runs packages as parallel processes, so it holds a session-level advisory lock on one admin connection around the check-and-create (`SELECT pg_advisory_lock(hashtext('testdb.roles'))`, the `DO` blocks with `IF NOT EXISTS`, then `pg_advisory_unlock`); `sync.Once` only covers one process.

A database per test costs ~100–300 ms; for a large API suite, one database per package with tenants created per test is fine as long as tests share no tenant.

## TestMain (every package with integration or API tests)

```go
var personalData = regexp.MustCompile(`\+1555010\d{2}|\b` + devCode + `\b|eyJ[A-Za-z0-9_-]{10,}`) // test numbers, the dev code, JWTs

func TestMain(m *testing.M) {
	for _, v := range append([]string{"APP_LIVE"}, config.ProviderKeyNames()...) { // derived, never a copy
		if os.Getenv(v) != "" {
			fmt.Fprintf(os.Stderr, "%s is set: tests never call real providers\n", v)
			os.Exit(1)
		}
	}
	http.DefaultTransport = localOnly{next: http.DefaultTransport} // httpx.NewClient builds on it, so provider clients are covered
	logs := &lockedBuffer{}
	slog.SetDefault(slog.New(slog.NewJSONHandler(logs, &slog.HandlerOptions{Level: slog.LevelDebug})))
	code := m.Run()
	if hits := personalData.FindAllString(logs.String(), 5); len(hits) > 0 {
		fmt.Fprintf(os.Stderr, "personal data in logs: %q\n", hits)
		code = 1
	}
	os.Exit(code)
}

// localOnly fails every request to a host that is not loopback (outbound network blocked).
type localOnly struct{ next http.RoundTripper }

func (l localOnly) RoundTrip(r *http.Request) (*http.Response, error) {
	host := r.URL.Hostname()
	if ip := net.ParseIP(host); host != "localhost" && (ip == nil || !ip.IsLoopback()) {
		return nil, fmt.Errorf("test tried to reach %s: outbound network is blocked", host)
	}
	return l.next.RoundTrip(r)
}
```

The live smoke (`internal/smoke`, build tag `live`) has its own `TestMain` with the opposite guard: it refuses to run unless `APP_LIVE=1` and every key are set and the API base URL (`APP_SMOKE_BASE_URL`) is in the committed allowlist of non-production hosts (`internal/smoke/allowed_base_urls.txt`, changed only in a reviewed PR), whatever `APP_ENV` says, keeps a call budget, and is the only package that may reach the network. The other packages' guard stays as above.

## API test environment (internal/server/harness_test.go)

```go
var start = time.Date(2026, 1, 13, 7, 0, 0, 0, time.UTC) // fixed; tests step from here

type env struct {
	t   *testing.T
	h   http.Handler
	clk *clock.Stepping
	db  *testdb.DB
	sms *fakes.SMS
}

func newEnv(t *testing.T) *env {
	t.Helper()
	db := testdb.New(t)
	cfg := config.Config{Env: "test", JWTSecret: strings.Repeat("j", 32), AuthPepper: strings.Repeat("p", 32)}
	clk := clock.NewStepping(start)
	sms, err := fakes.NewSMS(cfg.Env) // fields are unexported: only the constructor builds a fake
	if err != nil {
		t.Fatal(err)
	}
	h, err := server.Wire(cfg, db.App, clk, server.Providers{SMS: sms})
	if err != nil {
		t.Fatal(err)
	}
	return &env{t: t, h: h, clk: clk, db: db, sms: sms}
}

type req struct {
	token, membership, idem string
	body                    any
}

type resp struct {
	status int
	header http.Header
	body   []byte
}

func (e *env) call(method, path string, r req) resp {
	e.t.Helper()
	hr := httptest.NewRequest(method, path, jsonBody(e.t, r.body))
	setHeaders(hr, r) // Content-Type, Authorization, membership header, Idempotency-Key
	w := httptest.NewRecorder()
	e.h.ServeHTTP(w, hr)
	out := resp{status: w.Code, header: w.Header(), body: w.Body.Bytes()}
	checkContract(e.t, hr, out)
	return out
}
```

## Contract validation of every response

```go
var (
	contractOnce   sync.Once
	contractRouter routers.Router
)

// checkContract fails the test when a response breaks the contract: an undocumented status, a
// missing required field, a wrong type or enum, or an extra field.
func checkContract(t *testing.T, r *http.Request, res resp) {
	t.Helper()
	contractOnce.Do(func() {
		spec, err := apigen.GetSpec()
		if err != nil {
			panic(err)
		}
		spec.Servers = nil
		closeResponseSchemas(spec) // additionalProperties: false on every response object schema
		if contractRouter, err = gorillamux.NewRouter(spec); err != nil {
			panic(err)
		}
	})
	route, params, err := contractRouter.FindRoute(r)
	if err != nil || res.status == http.StatusNotImplemented {
		return // refused before routing, or a draft operation
	}
	in := &openapi3filter.ResponseValidationInput{
		RequestValidationInput: &openapi3filter.RequestValidationInput{Request: r, PathParams: params, Route: route},
		Status:                 res.status,
		Header:                 res.header,
		Body:                   io.NopCloser(bytes.NewReader(res.body)),
		Options:                &openapi3filter.Options{IncludeResponseStatus: true},
	}
	if err := openapi3filter.ValidateResponse(context.Background(), in); err != nil {
		t.Errorf("%s %s → %d breaks the contract: %v", r.Method, r.URL.Path, res.status, err)
	}
}
```

`closeResponseSchemas` walks every response's JSON schema (following `$ref`, `items`, `properties`) and sets `AdditionalProperties` to false on object schemas that do not declare it, on this test copy only; the published contract stays open for additive changes. Composed schemas need care: each `allOf` member is validated on its own, so closing the members makes every field of the other members "extra". Flatten an `allOf` of objects into one schema (merge `properties` and `required`) before closing it, and leave `oneOf` / `anyOf` members and anything that cannot be flattened open.

## First tests

1. `TestDraftOperationAnswers501` — a draft operation returns `501 notImplemented` in the error shape.
2. `TestStableOperationsAreImplemented` — walks the spec; every operation with status `stable` does not return `501`.
3. `TestUnauthenticated` — a `bearerAuth` operation without a token returns `401` before module code.
4. `TestMigrationsApply` (`internal/platform/migrate`) — migrate an empty database, run maintenance, assert RLS is forced on every tenant table, the runtime role cannot `UPDATE` append-only tables, and the runtime pool can insert a River job (`client.InsertTx` with a no-op args kind) — the River grants work.
5. The first module's API test per operation and error code (`testing-go-backends`).
