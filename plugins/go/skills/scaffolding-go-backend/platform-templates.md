# Platform and server templates

Plumbing only: no business type or rule goes into `internal/platform`. Third-party signatures (oapi-codegen runtime, nethttp-middleware, River) change between versions; check the installed version's godoc when a template does not compile.

## cmd/app/main.go

```go
// Command app is the backend binary: `app api` serves the REST API, `app migrate` applies
// migrations, `app jobs` runs workers, `app maintenance` runs housekeeping.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	_ "time/tzdata" // zones never depend on the host

	"example.com/app/internal/platform/config"
	"example.com/app/internal/platform/migrate"
	"example.com/app/internal/server"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: app api | migrate | jobs | maintenance")
		os.Exit(2)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := run(ctx, os.Args[1]); err != nil {
		slog.Error("exit", "command", os.Args[1], "err", err)
		os.Exit(1)
	}
}

func run(ctx context.Context, cmd string) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	switch cmd {
	case "migrate":
		return migrate.Up(ctx, cfg.MigratorDatabaseURL)
	case "api":
		return server.Serve(ctx, cfg) // opens the pool, Wire, http.Server with timeouts, graceful shutdown
	case "jobs":
		return server.RunJobs(ctx, cfg) // River client with workers, until ctx ends
	case "maintenance":
		return migrate.Maintain(ctx, cfg.MigratorDatabaseURL) // partitions, expired keys
	default:
		return fmt.Errorf("unknown command %q", cmd)
	}
}
```

## internal/platform/apperr

```go
// Package apperr is the one error type that crosses module boundaries: a kind, a stable code,
// and a developer message. httpx maps kinds to HTTP statuses in one place.
package apperr

type Kind int

const (
	Internal Kind = iota
	Invalid
	Unauthorized
	NotFound
	Conflict
	Unprocessable // well-formed but unusable, e.g. an idempotency key reused with another payload
	Gone
	RateLimited
	Unavailable
	NotImplemented
)

type FieldError struct{ Field, Code string }

type Error struct {
	Kind       Kind
	Code       string
	Message    string
	Fields     []FieldError
	RetryAfter time.Duration
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

// Is matches by code, so errors.Is works on copies made by WithRetryAfter.
func (e *Error) Is(target error) bool {
	t, ok := target.(*Error)
	return ok && t.Code == e.Code
}

func New(kind Kind, code, message string) *Error { return &Error{Kind: kind, Code: code, Message: message} }

func Invalidf(field, code string) *Error {
	return &Error{Kind: Invalid, Code: "validation.invalid", Message: field + ": " + code, Fields: []FieldError{{field, code}}}
}

var (
	ErrNotFound       = New(NotFound, "notFound", "not found")
	ErrUnauthorized   = New(Unauthorized, "auth.unauthorized", "missing or invalid access token")
	ErrNotImplemented = New(NotImplemented, "notImplemented", "in the contract, not built yet")
	ErrRateLimited    = New(RateLimited, "rateLimited", "too many requests")
)
```

## internal/platform/authz

```go
// Package authz carries the acting identity of a request. Which roles may do what is decided
// by each module's domain policies, never here.
package authz

type Actor struct {
	UserID       string
	MembershipID string
	TenantID     string
	Roles        []string
	Scopes       map[string]string // scope id (site, team) → role there
}

func (a Actor) Has(role string) bool { return slices.Contains(a.Roles, role) }
```

## internal/platform/clock

`type Clock interface{ Now() time.Time }`; `System` returns `time.Now().UTC()`; `Stepping` (mutex, `NewStepping(t)`, `Advance(d)`, `Set(t)`) for tests. The only `time.Now()` call in the codebase outside `main`.

## internal/platform/config

```go
type Config struct {
	Env                 string        `env:"APP_ENV,required"`
	HTTPAddr            string        `env:"APP_HTTP_ADDR" envDefault:":8080"`
	DatabaseURL         string        `env:"APP_DATABASE_URL,required"`
	MigratorDatabaseURL string        `env:"APP_MIGRATOR_DATABASE_URL"`
	SystemDatabaseURL   string        `env:"APP_SYSTEM_DATABASE_URL"` // global jobs only (BYPASSRLS)
	JWTSecret           string        `env:"APP_JWT_SECRET,required"`
	AuthPepper          string        `env:"APP_AUTH_PEPPER,required"`
	Live                bool          `env:"APP_LIVE"` // real adapters (sandbox credentials on staging); never in tests
	SMSAPIKey           string        `env:"APP_SMS_API_KEY"`
	SyncPollAfter       time.Duration `env:"APP_SYNC_POLL_AFTER" envDefault:"30s"`
}

func Load() (Config, error) {
	var c Config
	if err := env.Parse(&c); err != nil {
		return Config{}, fmt.Errorf("config: %w", err)
	}
	return c, c.Validate()
}

// Validate fails closed. Fakes (a fake code sender accepts a known code) exist only in non-release
// builds and run only in local and test; every other environment needs Live, and Live always needs
// every provider key. Errors are reported in a stable order.
func (c Config) Validate() error {
	var errs []error
	if len(c.JWTSecret) < 32 || len(c.AuthPepper) < 32 {
		errs = append(errs, errors.New("APP_JWT_SECRET and APP_AUTH_PEPPER need 32+ bytes"))
	}
	if c.Env != "local" && c.Env != "test" && !c.Live { // staging, production, and any typo
		errs = append(errs, fmt.Errorf("APP_ENV=%q needs APP_LIVE=1: fakes run only in local and test", c.Env))
	}
	if c.Live {
		keys := c.providerKeys()
		for _, name := range ProviderKeyNames() { // sorted
			if keys[name] == "" {
				errs = append(errs, fmt.Errorf("APP_LIVE=1 needs %s", name))
			}
		}
	}
	return errors.Join(errs...) // plus URL parsing of the database URLs
}

// providerKeys maps every key a real adapter needs to its value; a new provider adds its key here.
func (c Config) providerKeys() map[string]string {
	return map[string]string{"APP_SMS_API_KEY": c.SMSAPIKey}
}

// ProviderKeyNames is the sorted list of provider key variables; the test guard reads it too.
func ProviderKeyNames() []string {
	return slices.Sorted(maps.Keys(Config{}.providerKeys()))
}
```

Never log the config struct. Its table test (`config_test.go`) covers: `production` and `staging` without `APP_LIVE` → error; `APP_LIVE` with one key missing → an error naming it, in any env including local and test; an unknown env (`prod`, empty) → error; `local` and `test` without `APP_LIVE` and keys → ok; short secrets → error; two missing keys → the same message order every run.

**Fakes are not in release builds.** Every file of `internal/platform/fakes` starts with `//go:build !release`; their fields are unexported, so only the constructors (`fakes.NewSMS(env) (*SMS, error)`, refusing outside local and test) build them. `internal/server/providers_local.go` (`//go:build !release`) builds the fakes for `app api` in local; `providers_release.go` (`//go:build release`) defines the same function returning an error. `make build` and the Dockerfile use `-tags release`, and `make check-release` (part of `check`) fails when `go list -deps -tags release ./cmd/app` contains `internal/platform/fakes`. `.env.example` keeps `APP_ENV=local`; an image cannot run fakes whatever its env says.

## internal/platform/db

```go
// Scope is the context a transaction runs in; empty fields stay unset (fail closed).
type Scope struct{ TenantID, UserID string }

func InTx(ctx context.Context, pool *pgxpool.Pool, s Scope, fn func(pgx.Tx) error) error {
	return run(ctx, pool, pgx.TxOptions{IsoLevel: pgx.ReadCommitted}, s, fn)
}

func InSnapshotTx(ctx context.Context, pool *pgxpool.Pool, s Scope, fn func(pgx.Tx) error) error {
	return run(ctx, pool, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly}, s, fn)
}

func run(ctx context.Context, pool *pgxpool.Pool, opts pgx.TxOptions, s Scope, fn func(pgx.Tx) error) error {
	tx, err := pool.BeginTx(ctx, opts)
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if _, err := tx.Exec(ctx, `SELECT set_config('app.tenant_id', $1, true), set_config('app.user_id', $2, true)`,
		s.TenantID, s.UserID); err != nil {
		return fmt.Errorf("set scope: %w", err)
	}
	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

func IsNoRows(err error) bool { return errors.Is(err, pgx.ErrNoRows) }

func IsUniqueViolation(err error, constraint string) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505" && (constraint == "" || pgErr.ConstraintName == constraint)
}
```

## internal/platform/migrate

```go
// Up applies the goose migrations, then River's schema, then grants the runtime role River's
// tables: rivermigrate runs as the migrator, so the tables it creates belong to the migrator.
func Up(ctx context.Context, migratorURL string) error {
	pool, err := pgxpool.New(ctx, migratorURL)
	if err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer pool.Close()
	sqlDB := stdlib.OpenDBFromPool(pool)
	defer sqlDB.Close()
	p, err := goose.NewProvider(goose.DialectPostgres, sqlDB, migrations.FS)
	if err != nil {
		return fmt.Errorf("goose: %w", err)
	}
	if _, err := p.Up(ctx); err != nil {
		return fmt.Errorf("goose up: %w", err)
	}
	rm, err := rivermigrate.New(riverpgxv5.New(pool), nil)
	if err != nil {
		return fmt.Errorf("river: %w", err)
	}
	if _, err := rm.Migrate(ctx, rivermigrate.DirectionUp, nil); err != nil {
		return fmt.Errorf("river up: %w", err)
	}
	if _, err := pool.Exec(ctx, riverGrants); err != nil {
		return fmt.Errorf("river grants: %w", err)
	}
	return nil
}

// River's leader also reindexes its job indexes, which needs ownership: the runtime client sets
// `ReindexerIndexNames: []string{}` (an empty, non-nil list turns it off) and `app maintenance`,
// running as the migrator, does `REINDEX INDEX CONCURRENTLY` on River's indexes when needed.

// A global job that uses River runs as app_system, which needs the same grants: add it to the
// GRANT targets below (`TO app_runtime, app_system`) in the project that has one.

// riverGrants gives the runtime role River's tables and sequences except river_migration (and
// nothing else in public, such as goose_db_version). Functions keep the default EXECUTE for PUBLIC. Idempotent.
const riverGrants = `DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.oid::regclass AS rel, c.relkind FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relname LIKE 'river\_%' AND c.relname <> 'river_migration' AND c.relkind IN ('r', 'p', 'S') LOOP
    IF r.relkind = 'S' THEN
      EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO app_runtime', r.rel);
    ELSE
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE %s TO app_runtime', r.rel);
    END IF;
  END LOOP;
END $$`
```

`Maintain` opens the same pool and runs the maintenance statements (partitions ahead, expired idempotency keys).

## internal/platform/ids

`func New() string` returns `uuid.Must(uuid.NewV7()).String()`; `func Valid(s string) bool` parses. Typed ids live in each module's domain.

## internal/platform/httpx

```go
type errorBody struct {
	Error struct {
		Code      string              `json:"code"`
		Message   string              `json:"message"`
		RequestID string              `json:"requestId"`
		Fields    []apperr.FieldError `json:"fields,omitempty"`
	} `json:"error"`
}

// Error writes err in the contract's shape; the only kind → status mapping in the codebase.
func Error(w http.ResponseWriter, r *http.Request, err error) {
	var e *apperr.Error
	if !errors.As(err, &e) {
		slog.ErrorContext(r.Context(), "unexpected error", "err", err, "requestId", reqctx.RequestID(r.Context()))
		e = apperr.New(apperr.Internal, "internal", "internal error")
	}
	if e.RetryAfter > 0 {
		w.Header().Set("Retry-After", strconv.Itoa(int(math.Ceil(e.RetryAfter.Seconds()))))
	}
	var b errorBody
	b.Error.Code, b.Error.Message, b.Error.RequestID, b.Error.Fields = e.Code, e.Message, reqctx.RequestID(r.Context()), e.Fields
	JSON(w, status(e.Kind), b)
}

func status(k apperr.Kind) int {
	switch k {
	case apperr.Invalid:
		return http.StatusBadRequest
	case apperr.Unauthorized:
		return http.StatusUnauthorized
	case apperr.NotFound:
		return http.StatusNotFound
	case apperr.Conflict:
		return http.StatusConflict
	case apperr.Unprocessable:
		return http.StatusUnprocessableEntity
	case apperr.Gone:
		return http.StatusGone
	case apperr.RateLimited:
		return http.StatusTooManyRequests
	case apperr.Unavailable:
		return http.StatusServiceUnavailable
	case apperr.NotImplemented:
		return http.StatusNotImplemented
	default:
		return http.StatusInternalServerError
	}
}
```

Also here: `JSON(w, status, v)`, the request-id, recover, access-log (one line per request with operation, status, duration, ids), server-time, and authentication middleware (parses the bearer token, puts the principal in `reqctx`).

## Auth tokens (in the identity module's infra)

- Access tokens: `jwt.NewWithClaims(jwt.SigningMethodHS256, claims)` with a `kid` header; parse with `jwt.WithValidMethods([]string{"HS256"})`, `jwt.WithExpirationRequired()`, `jwt.WithIssuedAt()`, `jwt.WithLeeway(30*time.Second)`.
- Refresh tokens: 32 bytes from `crypto/rand`, base64url; only the SHA-256 is stored, the plaintext is returned once and never stored, logged, or replayed. Token rows have `family_id`, `parent_id`, `used_at`; a `refresh_families` row has `expires_at` (absolute lifetime, e.g. 30 days) and `revoked_at`.
- Rotation, in one transaction with `SELECT … FOR UPDATE` on the family row, then read the token's `used_at` (never before the lock, or two concurrent refreshes both issue a child): family revoked or expired → `401`; token already used → revoke the family and record a security event, return `nil` so the transaction commits, then answer `401` after the commit (returning the error inside `db.run` rolls the revocation back); otherwise mark the token used and issue a child pair. No grace window (`auditing-backend-security` lists what an ADR adding one must cover).
- Logout revokes the session's family; logout-all revokes every family of the user. Access tokens stay valid until their expiry (minutes); step-up and sensitive actions also check `refresh_families.revoked_at`.
- Token endpoints (sign-in, code exchange, refresh) are excluded from the idempotency replay store, because a stored response would hold plaintext tokens.
- Tests: reuse → family revoked and the latest child refused; concurrent double refresh → one wins, the other revokes the family; logout-all → every token refused; refresh after `expires_at` refused; the response never equal to an earlier one.
- One-time codes and identifiers stored as HMAC-SHA-256 with `cfg.AuthPepper`; compare with `hmac.Equal`.
- `http.Server` sets `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout`; `Shutdown` on `SIGTERM`.

## Idempotency

The scaffold creates only the `platform.idempotency_keys` table; the middleware and the store are designed in the project with the first retryable write and recorded in an ADR, because the details depend on its use cases. The design must answer, each with a test: the key is user + acting tenant (from the resolved actor, not the raw header) + operation id + key, and `body_hash` covers method, concrete path, and canonical body (another body → `422` with its own error code); a failed or cancelled call never leaves the key stuck (keep the key row in the same transaction as the write, or release it on failure and fence any takeover with a claim id); a committed result is never lost and never run twice; a concurrent duplicate gets a bounded wait, then `409` with `Retry-After` and its own error code, and a lock timeout set for the key never limits the use case's own locks; only successful results are replayed, as the use case's output and never HTTP types in `app`; the actor is resolved again before a replay, and the ADR states whether resource-level access is re-checked or a 24 h gap is accepted; outputs holding tokens, signed URLs, or one-time secrets are never stored (store ids and re-sign); a write whose only side effect is a provider call goes through an outbox job or the provider's own idempotency key; rows older than 24 h are deleted by `Maintain`; the ADR's migration adds the columns and grants its design needs (a claim id, `DELETE` for release, a stored status).

## internal/server/server.go

```go
// operations is the whole contract: module handlers at depth 1 win over the 501 fallback at
// depth 2; two modules implementing one operation fail to compile.
type operations struct {
	*foosHandler
	fallback
}

type (
	foosHandler = foosapi.Handler
	fallback    struct{ unimplemented }
)

var _ apigen.StrictServerInterface = operations{}

func New(d Deps) (http.Handler, error) {
	spec, err := apigen.GetSpec()
	if err != nil {
		return nil, fmt.Errorf("load contract: %w", err)
	}
	strict := apigen.NewStrictHandlerWithOptions(operations{foosHandler: d.Foos}, nil, apigen.StrictHTTPServerOptions{
		RequestErrorHandlerFunc:  func(w http.ResponseWriter, r *http.Request, err error) { httpx.Error(w, r, apperr.Invalidf("body", "invalid")) },
		ResponseErrorHandlerFunc: httpx.Error,
	})
	mux := http.NewServeMux()
	api := apigen.HandlerWithOptions(strict, apigen.StdHTTPServerOptions{BaseRouter: mux, ErrorHandlerFunc: paramError})
	// Order: request id → recover → access log → server time → auth (principal if a token is sent)
	// → contract validation (nethttp-middleware; bearerAuth operations without a principal → 401)
	// → rate limits → idempotency (see Idempotency above) → api.
	root := http.NewServeMux()
	root.HandleFunc("GET /healthz", healthz)
	root.HandleFunc("GET /readyz", readyz(d.Pool))
	root.Handle("/", chain(api, d, spec))
	return root, nil
}
```

## internal/server/wire.go

```go
// Wire builds every module and returns the API handler. Tests call it with a stepping clock
// and fakes for every provider.
func Wire(cfg config.Config, pool *pgxpool.Pool, clk clock.Clock, p Providers) (http.Handler, error) {
	aud := audit.New()
	rec := changelog.NewRecorder() // the client change log module (named to avoid the stdlib sync)
	tenantsMod := tenants.New(pool, clk, rec, aud)
	foosMod := foos.New(pool, clk, rec, aud)
	return New(Deps{Pool: pool, Clock: clk, Auth: tenantsMod.Authenticator(cfg.JWTSecret), Foos: foosMod.Handler})
}
```

`Providers` holds every external port (SMS, push, storage, models); tests pass fakes. `Serve` builds real adapters when `cfg.Live` is set (staging with sandbox or test credentials, production with real ones) and otherwise calls `localProviders`, which exists with fakes only in non-release builds; `Config.Validate` and the fake constructors refuse fakes outside local and test. Real adapters take their `*http.Client` from `internal/platform/httpx.NewClient` (timeouts, and the transport the test network block wraps), never `http.DefaultClient` or a client of their own.

## tools/genunimpl

A small Go program: parse `apigen.gen.go` with `go/parser`, find `StrictServerInterface`, and write `internal/server/unimplemented.gen.go` with `type unimplemented struct{}` and, for each method, `func (unimplemented) Op(context.Context, apigen.OpRequestObject) (apigen.OpResponseObject, error) { return nil, apperr.ErrNotImplemented }`, formatted with `go/format`, headed `// Code generated by tools/genunimpl. DO NOT EDIT.` Its own test checks the output compiles against a sample interface.
