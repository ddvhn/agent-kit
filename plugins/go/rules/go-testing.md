---
description: Go backend testing — table-driven tests, -short unit runs, a fresh migrated Postgres per test as the runtime role, API tests through the wired server validating every response, TestMain blocking network and scanning logs, rapid and native fuzzing, -race, -coverpkg coverage, make check
paths:
  - "**/*_test.go"
  - "Makefile"
---

# Go testing

How-to and templates: `testing-go-backends`; the harness: `scaffolding-go-backend`. Commands: `CLAUDE.md` → Verification.

- Domain and use case tests run with `go test -short` (no database; use cases with an in-memory `Transactor`); repository, migration, RLS, API, and job tests need the test database variable and fail, not skip, without it.
- Table-driven tests with `t.Run`, `errors.Is` for typed errors, `cmp.Diff` for structs; `-race` always in full runs.
- `testdb.New(t)` gives a fresh migrated database with pools as the runtime role and as admin; never SQLite or a mocked `pgx`.
- API tests build `server.Wire` with fakes and a stepping clock, create state through the API, and validate every response against the embedded spec (extra fields fail).
- Packages with integration or API tests have a `TestMain` that blocks outbound network, refuses live-provider variables, and scans the run's logs for personal data.
- `pgregory.net/rapid` for invariants; native fuzz tests for handwritten decoders.
- Coverage: `go test -coverpkg=./... -coverprofile`, filtered by `coverage-exclusions.txt`. Every PR states it ran `make check`; hooks are never skipped.
