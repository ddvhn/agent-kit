---
description: Go backend architecture — one binary with subcommands, internal/<module>/{domain,app,infra,api,jobs} with a root package as the public interface, internal/platform plumbing, the composition root in internal/server/wire.go, use case structs with Run, the Transactor port, oapi-codegen strict server with a 501 fallback, typed errors mapped once, depguard, River
paths:
  - "**/*.go"
  - "go.mod"
  - ".golangci.yml"
  - "api/**"
---

# Go backend architecture

The Go realization of the backend rules. Names and neighbors: `CLAUDE.md`. Templates: `scaffolding-go-backend` (layout, platform, server, linters), `adding-go-modules`, `adding-go-endpoints`, `writing-go-use-cases`, `writing-go-jobs`.

## Layout

- One binary in `cmd/<app>` with subcommands (`api`, `migrate`, later `jobs`, `maintenance`); `main` only parses, loads config, wires, runs.
- `internal/<module>/` per bounded context: root package `<module>.go` (the only import other modules use), `domain`, `app`, `infra` (queries, sqlc output, repositories, adapters), and drivers `api` (HTTP) and `jobs` (workers).
- `internal/platform/` plumbing only (generated API, error type, actor, clock, config, db, ids, HTTP helpers, test database); `internal/server/` the composition root (`wire.go`), router, and API tests.
- `depguard` enforces it: another module's internals only from `internal/server`; `domain` imports no outer layer, module, `pgx`, `apigen`, or `net/http`; `app` no driver; `infra` no `app`, driver, or module. A new module adds its rules in the same PR.

## Use cases

- One file, one struct named verb-first, one method `Run(ctx, in) (out, error)` with its own input and output types; fields are the ports it needs; no module-wide `Service`.
- Transactions through a port: `domain.Transactor.InTenant(ctx, tenantID, func(ctx, tx domain.Tx) error)`; `tx` hands out repositories, change recorder, audit writer, and job enqueuer bound to that transaction.
- The acting identity is `authz.Actor` (platform plumbing); role meaning and policies live in each module's `domain`.

## HTTP

- `oapi-codegen` with `std-http-server`, `strict-server`, `models`, `embedded-spec`; handlers implement `StrictServerInterface`, return the typed response or `nil, err`.
- The server embeds every module's handler plus a generated fallback answering `501`; the module's method wins by embedding depth.
- Middleware: request id, recover, access log, authentication, then contract validation (a `bearerAuth` operation without a principal → `401`), rate limits, idempotency (designed per project in an ADR, `scaffolding-go-backend`). Server timeouts set; graceful shutdown.

## Errors

- `apperr.Error{Kind, Code, Message, Fields}`; modules declare errors in `domain/errors.go`; `httpx` maps kind → status in one `switch` and writes the contract's error shape; anything else is `500 internal`, logged with the request id.

## Jobs

- River in the same Postgres; enqueue with `InsertTx` through the transaction port; workers in `<module>/jobs` run one use case and re-check state; `api` only inserts.
