---
name: scaffolding-go-backend
description: Create a Go backend from scratch the kit way, or bring an existing Go service onto the kit layout — go.mod, one binary with api / migrate / jobs / maintenance subcommands, the OpenAPI contract with oapi-codegen strict server and a 501 fallback, internal/platform plumbing (apperr, clock, config, db with tenant scope, ids, httpx), internal/server/wire.go, goose migrations with roles and RLS helpers, sqlc, depguard and golangci-lint, Makefile, compose, Dockerfile, the testdb and API test harness, git hooks, and what to record in CLAUDE.md. Use when starting a new Go backend, adding the first module or endpoint to an empty one, or unifying an existing Go backend's structure.
---

# Scaffolding a Go backend

The result follows the `backend-*` rules and the `go`, `go-architecture`, `go-data`, and `go-testing` rules. Templates use module path `example.com/app`, binary `app`, env prefix `APP_`, roles `app_migrator` / `app_runtime` / `app_system`, and the module `foos`; replace them with the real names once, everywhere.

Reference files in this folder:

- [project-files.md](project-files.md) — `go.mod` dependencies, `Makefile`, `.golangci.yml`, `sqlc.yaml`, `oapi-codegen.yaml`, `compose.yaml`, `Dockerfile`, bootstrap SQL, the first migration, `.env.example`, `.gitignore`, git hooks.
- [platform-templates.md](platform-templates.md) — `cmd/app/main.go`, `internal/platform` (apperr, authz, clock, config, db, ids, httpx), `internal/server` (server, wire, the 501 fallback generator).
- [test-harness.md](test-harness.md) — `testdb`, `TestMain` (network block, live-flag guard, log scan), the API test environment with contract validation, the first tests.

The first module's files: `adding-go-modules`. The first endpoint: `adding-go-endpoints`.

## Workflow

1. **Ask first** (expensive to change later): the module path and binary name; the Go version (the newest stable); the tenant model (shared database with RLS is the default, `isolating-tenants-in-postgres`); the identity model (passwordless codes, external identity, or both); the client repositories that will generate from the contract; the first modules and providers; the target ASVS level; environments and hosting (Postgres version, S3-compatible storage). Record the stack in an ADR (`recording-decisions`): language, HTTP, contract tooling, driver, queries, migrations, queue, config, logs, ids, tokens, tests, lint, CI.
2. **Existing service?** Inventory it against the layout (`go-architecture` rule → Layout) and the rules; list the differences and ask which to converge now. Converge per module, each step green; never a big-bang move.
3. Create the files from `project-files.md`, then `go mod tidy`.
4. Write the contract skeleton (`api/openapi.yaml`): `info`, `servers`, `bearerAuth`, shared components (`Error`, `Money`, `MembershipId`, `IdempotencyKey`, `Cursor`, `Limit`), and one operation (`getMe` or the first module's list) with milestone and `draft` (`designing-api-contracts`).
5. Write `internal/platform` and `internal/server` from `platform-templates.md`; `make generate`; `go build ./...`.
6. Write the harness from `test-harness.md` and one failing API test (the draft operation answers `501`; then the first real operation).
7. Bootstrap local Postgres (`docker compose up -d postgres`, the bootstrap SQL), `make migrate`, `make test` green.
8. Build the first module end to end (`adding-go-modules`): migration → queries → repository → use case → handler → `stable`.
9. `make check` green; `make hooks`.
10. Record the project in `CLAUDE.md` and `.claude/rules/` through the core skill `adopting-agent-kit` (What to record, below); write the README newcomer guide (prerequisites, local setup, commands, layout, generate, build).

## What to record in the repository

- `CLAUDE.md` → Project facts: stack summary and ADR link, module path, binary and subcommands, modules list, neighbors to copy (the first module and `internal/server/*_test.go`), review zones, environments. Verification: `make check-generated lint test cover`, `make test-unit`, the test database variable, the coverage gate. Project nuances and "ask first" items.
- `.claude/rules/`: the module list with their bounded contexts and the allowed module graph; role names and tenant settings; error code namespaces; the project's load profile and targets; markets for compliance.
- `.claude/settings.json`: enable `core`, `backend`, and `go`; allow `make`, `go test`, `go vet`, `go build`, `git diff/status/log/show`; deny reading `.env*`, deploy commands, and force-pushes.

## Pitfalls

- The runtime role must not own tables: run migrations as the migrator and connect the app as the runtime role, in tests too, or RLS silently passes.
- `set_config(…, true)` only inside a transaction; outside one it lasts the session and leaks across pooled connections.
- Generated code is committed; tool versions are pinned in the Makefile and run with the module's Go (`GOTOOLCHAIN=$(go env GOVERSION) go run tool@version`).
- Without the 501 fallback, the server does not compile until every operation exists; generate it from the strict interface.
- `time/tzdata` in `main`, or zone lookups fail in a distroless image.
