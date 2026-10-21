---
name: testing-go-backends
description: Write, run, and debug tests in a Go backend — choose the owning suite, table-driven domain and use case tests, repository and RLS tests on a fresh Postgres, API tests through the server harness with contract validation, error-code, census, idempotency, and concurrency cases, job tests, rapid property tests, native fuzz tests, coverage with -coverpkg and the exclusion list, and debugging flaky or failing runs. Use when adding or changing tests, covering changed behavior, running the suites, chasing coverage gaps, or changing the test harness.
---

# Testing Go backends

Policy: the `backend-testing` and `go-testing` rules. Commands, the database variable, and the coverage gate: `CLAUDE.md` → Verification; read it first. Building the harness from nothing: `scaffolding-go-backend` → test-harness.md.

## Suites

| Suite | Where | Runs with |
| --- | --- | --- |
| Domain unit | `internal/<module>/domain/*_test.go` (package `domain_test`) | `go test -short` |
| Use case unit | `internal/<module>/app/*_test.go`, in-memory `Transactor` and fakes | `go test -short` |
| Integration (repositories, migrations, RLS, constraints) | `internal/<module>/infra/*_test.go`, `internal/platform/migrate` | `testdb`, full run |
| API | `internal/server/*_test.go` through `server.Wire`, fakes, stepping clock | `testdb`, full run |
| Jobs | `internal/<module>/jobs/*_test.go` with River's test helpers | `testdb`, full run |

- Black-box test packages by default. Harness details (`testdb`, `TestMain`, contract validation, Makefile targets): `scaffolding-go-backend` → test-harness.md and project-files.md.
- Providers: every port has a fake (module test helpers or `internal/platform/fakes`) that records calls and can be scripted to fail; fakes have unexported fields and a constructor, live in files tagged `//go:build !release`, and never reach the image; a real adapter's constructor refuses without its live flag and key, and its mapping is tested against `httptest.NewServer` stubs. The live smoke runs only through `make smoke-live` (`go test -tags live ./internal/smoke/...`) with a call budget.

## Authoring workflow (tests first)

1. Pick the owning suite (Suites below). Pure rule → domain; orchestration → use case with fakes; SQL, constraints, RLS → integration; transport, auth, error codes, tenancy → API.
2. Derive cases from the behavior's state machine and the edge-case checklist (`testing-backends` → Edge-case checklist): adversarial first (invalid, unknown, foreign, forbidden, concurrent, boundary times), happy path last. Name each test after the rule it protects (requirement id when there is one).
3. Run and see it fail for the right reason: `go test -short -run TestPublishFoo ./internal/foos/...` (unit) or `go test -count=1 -run TestUpdateFoo ./internal/server/` (needs the database variable).
4. Implement; rerun the narrow test; then `make test` once and `make cover` before the PR.

## Patterns

- **Table-driven** with `t.Run(tt.name, …)`, `errors.Is(err, tt.wantErr)`, `cmp.Diff(want, got)` for structs; `t.Parallel()` only when cases share no state.
- **Time**: `clock.NewStepping(start)`; `clk.Advance(d)` or `clk.Set(t)` to cross deadlines; DST cases built with `time.Date(…, loc)` for a named zone (fall back: the ambiguous hour means its first occurrence; spring forward: the gap moves forward). Never `time.Sleep`.
- **Builders**, not fixture files: `newFoo(t, func(f *domain.Foo){ f.Status = domain.FooDraft })` returns a valid entity with overrides; API helpers (`e.newTenant`, `a.createFoo`) create state through the API.
- **Test identifiers** from reserved ranges (`+1 555 0100`–`0199`, `example.com`); names with Cyrillic, diacritics (`ñ ø`), and emoji in at least one case per text field.
- **Concurrency**: start goroutines behind a `sync.WaitGroup` and a start barrier (`close(ready)`), each running a real request or transaction; collect results; assert one success and the typed conflict for the rest; run with `-race`.
- **Idempotency** (plus every case the project's idempotency ADR lists): same key twice → identical body; concurrently → one row, the loser replays or gets `409` with `Retry-After`; a failed call then a retry → runs once; a refused call then a retry → evaluated again; a replay after dismissal → refused; different body → `422`; after a simulated timeout (cancel the first call's context mid-flight) → the retry gets the stored result or completes once.
- **RLS**: as the runtime pool without scope → zero rows; with tenant A → no B rows; an insert referencing B → foreign key error; `UPDATE` on an append-only table → error.
- **Census**: the route census iterates `apigen.GetSpec()` paths and operations and fails when an operation has no entry in the RBAC table of the test; the cross-tenant census calls every read with B's ids as A.

## Property tests (rapid)

```go
func TestBalanceIsSumOfEntries(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		amounts := rapid.SliceOfN(rapid.Int64Range(-1_000_000, 1_000_000), 0, 200).Draw(t, "amounts")
		var l domain.Ledger
		for _, a := range amounts {
			l = l.Append(domain.Entry{AmountMinor: a})
		}
		var sum int64
		for _, a := range amounts {
			sum += a
		}
		if l.Balance() != sum {
			t.Fatalf("balance %d, sum %d", l.Balance(), sum)
		}
	})
}
```

Use them for invariants (ordering total and stable, every status reaches a terminal one, encode ∘ decode = identity), not for single examples.

## Fuzz tests

```go
func FuzzParseCursor(f *testing.F) {
	f.Add("")
	f.Add(validCursor)
	f.Fuzz(func(t *testing.T, s string) {
		c, err := domain.ParseCursor(s)
		if err != nil {
			return // refusing is fine; panicking is not
		}
		if again, err := domain.ParseCursor(c.String()); err != nil || again != c {
			t.Fatalf("round trip %q → %v, %v", s, again, err)
		}
	})
}
```

Run `go test -fuzz=FuzzParseCursor -fuzztime=60s ./internal/changelog/domain` when the decoder changes; commit any crasher it writes under `testdata/fuzz/`.

## Coverage

- `make cover` (or `go test -coverpkg=./... -coverprofile=cover.out ./...`); `go tool cover -func=cover.out | sort -k3 -n | head -40` lists the weakest functions; `go tool cover -html=cover.out` shows lines.
- An uncovered line is a missing test or dead code: add the case or delete the code. Never widen `coverage-exclusions.txt` without a reason in the PR.

## Debugging failing runs

- One failing test: `-run '^TestX$/^case$' -count=1 -v`; logs: set the project's test-log variable to mirror `slog` to stderr.
- Integration failure about permissions or empty results: the transaction lacks the tenant scope, or the test used the admin pool for something the runtime role must do.
- Flaky: rerun with `-count=20 -race`; look for shared state between parallel tests, wall-clock time, map iteration order, or a missing `t.Cleanup`. Fix within 2 working days or delete; never skip.
- Contract failure in `checkContract`: either the response or the contract is wrong; fix the one that disagrees with the design, never loosen the validator.
- `personal data in logs`: find the log call that prints the value and log the id instead.
