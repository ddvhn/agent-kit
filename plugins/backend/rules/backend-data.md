---
description: Backend data — Postgres as system of record, UUID v7, timestamptz UTC, integer money, text + CHECK enums, append-only records enforced in the database, forward-only expand/contract migrations, retention jobs, injected clock and zones, idempotent jobs in the same transaction
---

# Backend data

Defaults for a self-hosted relational store; an adopted platform keeps the store-independent parts. Migration how-to: the stack skill (Go: `writing-go-migrations`); queries under load: `planning-backend-load`.

## Schema

- Postgres is the system of record (state, money, audit, queue, outbox); object storage holds files only, referenced by id.
- Tables plural snake_case, one schema or prefix per module; cross-module references are ids without foreign keys.
- Ids: UUID v7 from the application. Instants: `timestamptz` in UTC; database defaults (`created_at DEFAULT now()`) are fine for row bookkeeping, but business time (deadlines, decisions) comes from the injected clock; local wall times as `time` + the owning entity's IANA zone.
- Money: `bigint` minor units + ISO 4217 currency; never floats. Enums: `text` + `CHECK`.
- Indexes lead with the tenant id when the product is multi-tenant; hot queries checked with `EXPLAIN` on realistic volume.

## Append-only records

- Ledgers, audit logs, histories are append-only in the database: the application role has `INSERT` and `SELECT` only, a trigger refuses `UPDATE` / `DELETE`. Corrections are reversal rows; balances are sums.
- Every state change writes an audit row (actor, action, entity ids, server time) in the same transaction.

## Migrations

- Numbered SQL files, forward-only, run before the new code. Expand / contract: the previous code works on the new schema. Destructive changes in two releases with the user's go-ahead. `lock_timeout` set; no blocking rewrite of a large table.

## Retention

- Each data class has a retention in `CLAUDE.md` (changing it is "ask first"), enforced by a scheduled job; large time-ordered tables are partitioned when they grow. Delete database rows first, files after.

## Time

- `now` comes from an injected clock; tests use a fixed or steppable clock and never sleep.
- Local deadlines and windows are computed on the server in the entity's zone; DST days, zones without DST, and midnight are test cases. The device clock is untrusted.

## Jobs

- Background work runs from a queue in the same database; a job is inserted in the same transaction as its cause.
- Jobs are idempotent, re-check state, retry with backoff and a cap, then land in a dead state with an alert. Every external call has a timeout.
