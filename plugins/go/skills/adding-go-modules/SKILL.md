---
name: adding-go-modules
description: Add a new module (bounded context) to a Go modular monolith — the internal/<module> folders and root package, domain types, errors and ports, the Transactor and repositories over sqlc, the schema migration with RLS, the sqlc.yaml entry, depguard rules, wiring in internal/server/wire.go, and the first tests. Use when a feature needs a new bounded context, when splitting a module, or when a module is missing layers. Adding an operation to an existing module: adding-go-endpoints; a use case: writing-go-use-cases.
---

# Adding a Go module

Policy: the `backend-architecture` rule → Modules; the `go-architecture` rule → Layout. Neighbor to copy: `CLAUDE.md` → Project facts. Name the module from the ubiquitous language (`foos`, plural, one word); a new term goes into the glossary first.

## Before code

1. Write down the bounded context in one paragraph: what it owns (tables, invariants), what it offers (use cases, events), which modules it calls (one way, from higher to lower) and which events it consumes. If it needs another module's data, that module must expose it through its root package; never its tables.
2. Check the module graph stays acyclic; name the new arrows in the PR.
3. Plan the slices: schema + repository, then one use case and operation at a time (`adding-go-endpoints`).

## Files

```
internal/foos/
  foos.go                     root package
  domain/foo.go               entity, value types, constructors that validate
  domain/policy.go            CanSeeFoo, CanEditFoo(actor, foo)
  domain/errors.go            var ErrFooNotFound = apperr.New(apperr.NotFound, "notFound", "not found") (the same text as `apperr.ErrNotFound`, so forbidden and missing look alike) and module codes
  domain/ports.go             FooRepository, Tx, Transactor
  domain/foo_test.go          table tests of constructors and policies
  app/create_foo.go           one use case (writing-go-use-cases)
  app/fakes_test.go           in-memory Transactor and repositories for use case tests
  infra/queries.sql           sqlc queries
  infra/db/                   generated
  infra/transactor.go         InTenant over db.InTx
  infra/foo_repository.go     FooRepository over db.Queries
  infra/foo_repository_test.go integration tests on testdb
  api/handlers.go             strict server methods for this module's operations
  api/mapping.go              domain ↔ apigen
migrations/000NN_foos.sql
```

## Root package

```go
// Package foos is the public interface of the foos module: <one-line bounded context>.
package foos

type Module struct {
	Handler *api.Handler
	// use cases other modules may call, exported one by one
	GetFoo *app.GetFoo
}

// New wires the module; rec and aud write change hints and audit rows in the same transaction.
func New(pool *pgxpool.Pool, clk clock.Clock, rec changelog.Recorder, aud audit.Writer) *Module {
	tx := infra.NewTransactor(pool, rec, aud)
	create := app.NewCreateFoo(tx, clk)
	get := app.NewGetFoo(tx)
	return &Module{Handler: api.NewHandler(create, get), GetFoo: get}
}
```

Other modules use only the root package: its exported use cases, its event types, its value types. Never `foos/domain`, `foos/app`, `foos/infra`, or `foos/api`.

## Domain ports

```go
type FooRepository interface {
	Get(ctx context.Context, id FooID) (Foo, error)   // ErrFooNotFound
	GetForUpdate(ctx context.Context, id FooID) (Foo, error)
	List(ctx context.Context, after *FooID, limit int) ([]Foo, error)
	Insert(ctx context.Context, f Foo) error
	Update(ctx context.Context, f Foo) error
}

type Tx interface {
	Foos() FooRepository
	Changes() ChangeRecorder // Record(ctx, topic, entityID, op)
	Audit() AuditWriter      // Write(ctx, action, entityID, before, after)
}

type Transactor interface {
	InTenant(ctx context.Context, tenantID string, fn func(ctx context.Context, tx Tx) error) error
}
```

`ChangeRecorder` and `AuditWriter` are small interfaces declared here; `wire.go` passes the implementations from the change-log and audit modules.

## Queries and mapping

- `infra/queries.sql` is read against `migrations/` and generated into `infra/db` (package `db`, `sql_package: pgx/v5`, `emit_pointers_for_null_types`, `emit_empty_slices`; shared overrides `uuid` → `string`, `timestamptz` → `time.Time`). Generated code is committed; `make check-generated` fails on drift.
- Query names `VerbNoun` (`GetFoo`, `ListFoosByTenant`, `UpdateFooStatus`); parameters by name (`sqlc.arg(after_id)`, `sqlc.narg(status)`); optional filters as `(sqlc.narg(status)::text IS NULL OR status = sqlc.narg(status))`.
- Every tenant query filters by `tenant_id` even under RLS; lists use keyset pagination (`WHERE id > sqlc.narg(after_id) ORDER BY id LIMIT sqlc.arg(row_limit)`, one extra row to know if there is a next page).
- `fooFromRow(db.FoosFoo) (domain.Foo, error)` maps rows; an unknown enum or invalid stored value is an error. `pgx.ErrNoRows` → the module's not-found error; `23505` / `23503` → typed conflicts by constraint name (`db.IsUniqueViolation`), never by message.
- Ids: UUID v7 from `ids.New()`, typed in the domain (`type FooID string`). Money: `int64` minor units plus unit; instants `time.Time` UTC; wall times plus a `*time.Location` loaded from the entity's zone.

## Migration

Copy the tenant table template from `isolating-tenants-in-postgres`: `CREATE SCHEMA foos` with `GRANT USAGE ON SCHEMA foos TO app_runtime`, `tenant_id`, `UNIQUE (tenant_id, id)`, composite foreign keys, `ENABLE` + `FORCE` RLS, grants for the runtime role, indexes led by `tenant_id`. How-to: `writing-go-migrations`.

## Wiring and tooling

1. `sqlc.yaml`: a new entry for the module (copy the anchor block); `make generate`.
2. `.golangci.yml`: add `foos-internals`, and the module's `app`, `infra`, `api`, `jobs`, and root package to the `domain-pure`, `app-layer`, and `infra-layer` deny lists.
3. `internal/server/wire.go`: build the module; `server.go`: embed `*foosapi.Handler` in `operations` and add it to `Deps`.
4. `coverage-exclusions.txt` already covers `infra/db`; nothing else is excluded.
5. Census tests pick the new routes up automatically; add the RBAC and cross-tenant cases they demand.

## Tests first

- Domain: constructors refuse invalid input (empty, too long, unknown enum), policies per role × own / foreign scope.
- Repository on `testdb`: round trip; not found; list order, limit, `after`; RLS — another tenant's row invisible, a cross-tenant reference refused.
- Then the first use case and operation (`writing-go-use-cases`, `adding-go-endpoints`).

Done when `make check` passes and the PR lists the new module, its arrows, and the Load and Compliance sections.
