---
name: writing-go-migrations
description: Write a forward-only goose SQL migration for a Go backend on Postgres — numbering, Up only, StatementBegin blocks, NO TRANSACTION for concurrent indexes, lock_timeout, expand/contract steps for renames and type changes, batched backfills, grants and Row-Level Security for new tenant tables, append-only triggers, partitions, and the migration tests on an empty and a seeded database. Use when changing the database schema, adding a table, column, index, constraint, policy, or trigger, or planning a destructive change.
---

# Writing Go migrations

Policy: the `backend-data` rule → Migrations; the `go-data` rule. Tenant table template and isolation tests: `isolating-tenants-in-postgres`. Destructive changes need the user's go-ahead.

## File

`migrations/000NN_<verb>_<what>.sql`, the next number, one concern per file:

```sql
-- +goose Up
-- Adds archiving to foos (expand step: nullable column, old code keeps working).
SET LOCAL lock_timeout = '5s';   -- goose runs each file in a transaction; LOCAL ends with it

ALTER TABLE foos.foos ADD COLUMN archived_at timestamptz;
ALTER TABLE foos.foos ADD CONSTRAINT foos_archived_after_created
    CHECK (archived_at IS NULL OR archived_at >= created_at) NOT VALID;
```

```sql
-- +goose Up
-- The next file: validate without blocking writes (SHARE UPDATE EXCLUSIVE lock only).
SET LOCAL lock_timeout = '5s';
ALTER TABLE foos.foos VALIDATE CONSTRAINT foos_archived_after_created;
```

- Only `-- +goose Up`; never a Down section (rollback is the previous image, which works with the expanded schema).
- Functions, triggers, and `DO` blocks between `-- +goose StatementBegin` and `-- +goose StatementEnd`.
- `CREATE INDEX CONCURRENTLY` (and `DROP INDEX CONCURRENTLY`) in a file of its own that starts with `-- +goose NO TRANSACTION`; name the index; lead with `tenant_id`.
- New constraints on big tables: add `NOT VALID` in one migration and `VALIDATE CONSTRAINT` in the next, so the short exclusive lock and the long scan are never held in one transaction. `SET LOCAL lock_timeout` in every file that touches existing tables (a plain `SET` in a `NO TRANSACTION` file).
- Never edit a migration that ran anywhere shared; add a new one. After editing an unmerged one, rerun the tests from an empty database.

## Expand / contract recipes

| Change | Release 1 (expand) | Release 2 | Release 3 (contract, user's go-ahead) |
| --- | --- | --- | --- |
| Rename a column | Add the new column; write both; backfill in batches | Read the new one | Stop writing the old; drop it |
| Change a type | Add a column of the new type; write both; backfill | Read the new one | Drop the old |
| Make a column required | Add with a default or backfill; `CHECK (col IS NOT NULL) NOT VALID`; validate | `SET NOT NULL` (uses the validated check) | — |
| Drop a table | Stop using it in code | Drop | — |
| Split a table | Create the new table; write both; backfill | Read the new | Drop the old columns |

Backfills of large tables run as a job or a maintenance step in batches by id (`UPDATE … WHERE id IN (SELECT id … LIMIT 5000)`), never one statement over millions of rows inside the migration.

## New tables

- Schema of the owning module; a new schema gets `GRANT USAGE ON SCHEMA foos TO app_runtime` in the same file. Tenant tables per `isolating-tenants-in-postgres` (`tenant_id`, `UNIQUE (tenant_id, id)`, composite foreign keys, `ENABLE` + `FORCE` RLS, policy, grants).
- Enums as `text` + `CHECK (status IN (…))`; adding a value later is `DROP CONSTRAINT` + `ADD CONSTRAINT … NOT VALID` in one file and `VALIDATE CONSTRAINT` in the next.
- Money `bigint` + `char(3)` currency with a `CHECK (currency ~ '^[A-Z]{3}$')`; instants `timestamptz`; `created_at` default `now()`.
- Append-only tables: `GRANT SELECT, INSERT` only and the `platform.refuse_change()` trigger for `UPDATE` and `DELETE`.
- Large time-ordered tables: `PARTITION BY RANGE (created_at)` with partitions created by the maintenance command ahead of time and dropped by retention.
- Grant the runtime role exactly what the queries need (`SELECT, INSERT, UPDATE`, rarely `DELETE`); global tables `SELECT` only.

## Running

- Files are embedded (`migrations/embed.go`: `//go:embed *.sql`) and applied by `app migrate` through `goose.NewProvider(goose.DialectPostgres, db, migrations.FS)` as the migrator role; River's schema follows with `rivermigrate` in the same subcommand, then the runtime role is granted River's tables (`scaffolding-go-backend` → platform-templates.md); a River upgrade that adds a table is covered by the same grant step.
- Roles come from the installation's bootstrap script (`scaffolding-go-backend` → project-files.md), never from migrations.

## After writing

1. `make migrate` locally (or let `testdb` apply it), then `make generate` (sqlc reads `migrations/`).
2. Tests:
   - the migration test applies every migration to an empty database and runs maintenance;
   - a seeded test: data inserted under the previous schema survives and reads correctly after the new migration (write it when the migration touches existing rows);
   - constraints exist and bite: a row violating the new `CHECK`, the composite key, or the policy is refused; append-only `UPDATE` fails;
   - the tenant census (every tenant table has forced RLS) still passes.
3. PR: the expand / contract step this is, what the previous code version does with the new schema, the lock taken and its duration on the largest table (Load section), and for destructive steps the user's go-ahead.
