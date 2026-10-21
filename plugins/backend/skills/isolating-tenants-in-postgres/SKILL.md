---
name: isolating-tenants-in-postgres
description: Set up or extend multi-tenant isolation in a shared Postgres database — database roles (owner, application without BYPASSRLS, system), schemas per module, transaction-local tenant context with set_config, forced fail-closed Row-Level Security policies, composite (tenant_id, id) foreign keys, append-only triggers, read-only global tables, and the tests that prove isolation. Use when creating the first tenant table, adding a tenant table or a cross-scope policy, adding a global job that spans tenants, or reviewing tenant isolation.
---

# Isolating tenants in Postgres

Policy: the `backend-security` rule → Multi-tenancy; storage conventions: the `backend-data` rule. Role names, schema list, and context settings of the project: the repository's rules and its tenancy ADR. Write the ADR first if there is none (`recording-decisions`).

## Roles (bootstrap, once per installation)

```sql
CREATE ROLE app_migrator LOGIN PASSWORD :'migrator_password';         -- owns schemas, runs migrations, grants on its tables
CREATE ROLE app_runtime  LOGIN PASSWORD :'app_password' NOBYPASSRLS;  -- API and jobs, owns nothing
CREATE ROLE app_system   LOGIN PASSWORD :'system_password' BYPASSRLS; -- global jobs only, its own pool
CREATE DATABASE app OWNER app_migrator;
```

- The runtime role never owns a table (owners bypass RLS unless `FORCE`), never has `BYPASSRLS`, and gets only the grants each table needs.
- The system role bypasses RLS but not privileges: the migration that adds a global job grants it `USAGE` on the schemas and exactly the table rights that job needs.
- Bootstrap lives in a script (not a migration), because migrations assume the roles exist. Tests create the same roles once per run.

## Context helpers (first migration)

```sql
CREATE SCHEMA platform;
CREATE FUNCTION platform.current_tenant_id() RETURNS uuid
  LANGUAGE sql STABLE PARALLEL SAFE
  AS $$ SELECT NULLIF(current_setting('app.tenant_id', true), '')::uuid $$;
GRANT USAGE ON SCHEMA platform TO app_runtime;
GRANT EXECUTE ON FUNCTION platform.current_tenant_id() TO app_runtime;

CREATE FUNCTION platform.refuse_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is append-only', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
    USING ERRCODE = 'insufficient_privilege';
END $$;
```

Unset and reset settings both read as `NULL`, so every policy fails closed. Add `app.user_id` (and similar) only for narrow, named cross-tenant reads, such as a user listing their own memberships.

## Tenant table template

```sql
CREATE SCHEMA foos;                              -- owned by the migrator
GRANT USAGE ON SCHEMA foos TO app_runtime;        -- without it every grant below is useless

CREATE TABLE foos.foos (
    id         uuid        PRIMARY KEY,
    tenant_id  uuid        NOT NULL REFERENCES tenants.tenants (id),
    name       text        NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
    status     text        NOT NULL CHECK (status IN ('draft', 'published', 'archived')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, id)
);
CREATE TABLE foos.foo_items (
    id        uuid PRIMARY KEY,
    tenant_id uuid NOT NULL,
    foo_id    uuid NOT NULL,
    FOREIGN KEY (tenant_id, foo_id) REFERENCES foos.foos (tenant_id, id),
    UNIQUE (tenant_id, id)
);
CREATE INDEX ON foos.foo_items (tenant_id, foo_id);

ALTER TABLE foos.foos ENABLE ROW LEVEL SECURITY;
ALTER TABLE foos.foos FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant ON foos.foos
  USING (tenant_id = platform.current_tenant_id())
  WITH CHECK (tenant_id = platform.current_tenant_id());
-- same three statements for foos.foo_items
GRANT SELECT, INSERT, UPDATE ON foos.foos, foos.foo_items TO app_runtime;
```

- Every index on a tenant table leads with `tenant_id`.
- Cross-module references are plain ids (no foreign key); the owning module checks them. The one exception is the tenant root: every tenant table may reference `tenants.tenants (id)`, because no tenant row outlives its tenant and the tenants module is below every other module.
- Append-only tables: `GRANT SELECT, INSERT` only, plus `CREATE TRIGGER refuse BEFORE UPDATE OR DELETE ON … FOR EACH ROW EXECUTE FUNCTION platform.refuse_change();`.
- Global tables (no `tenant_id`, no RLS): `GRANT SELECT` only; changed by a reviewed content import run as the migrator.

## Transaction context in code

Every use-case transaction sets the scope first, transaction-local, so it resets at commit and works behind a transaction-mode pooler:

```sql
SELECT set_config('app.tenant_id', $1, true), set_config('app.user_id', $2, true);
```

- The tenant id comes from the resolved acting membership, never from the request body or path.
- A use case without a tenant (sign-in) leaves it unset and sees no tenant rows; a use case that forgets it gets nothing back, which fails its tests instead of leaking.
- A transaction may switch scope (reading each of the user's tenants for a profile screen) by calling `set_config` again; name the tenant explicitly in such queries.
- Jobs work one tenant at a time and set the same context from the job's arguments. A truly global job (retention of a global log, billing) connects as the system role through its own pool in its own package, and is a review zone.

## Tests that prove isolation

Run as the runtime role against a migrated database:

0. The runtime role has `USAGE` on every module schema and the grants each table needs (a missing schema grant shows up as `permission denied for schema`, not as zero rows).

1. No context → `SELECT` on every tenant table returns zero rows; `INSERT` fails the policy.
2. Context A → no row of B is visible; `UPDATE` / `DELETE` of B's row by id affects zero rows.
3. An insert in A that references B's parent fails on the composite foreign key.
4. `UPDATE` and `DELETE` on every append-only table fail for every role.
5. The runtime role cannot write global tables.
6. A census test lists every table in tenant schemas and fails when one has no `FORCE` RLS or lacks `tenant_id` (unless it is on the global allowlist; a platform table such as the idempotency store, reached only by its full user-scoped key, lives outside the tenant schemas):

```sql
SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p') AND n.nspname = ANY($1) AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
```

Plus the API-level cross-tenant census (`testing-backends` → Contract and census).
