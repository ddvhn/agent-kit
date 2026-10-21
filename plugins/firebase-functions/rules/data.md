---
description: Firebase Functions data rules — CRUD-only Firestore repositories, the DB registry and typed converters, versioned entities (full vs partial writes), transactions, consistency and cost
paths:
  - "functions/**"
---

# Firebase Functions data

Firestore realization of the `backend-data` rule (store-independent parts: ids, instants, money, closed enums, append-only records, retention, time, idempotent background work). Owner of repositories, the DB registry, versioned entities, and transactions. Templates: `creating-firestore-repositories`; access patterns, multi-document consistency, size and cost: `working-with-firestore`.

## Repositories

- One `FooRepository` object per entity, **CRUD only**: `generateId`, reads, `*WithinTransaction` writes, deletes. No conditional transitions (`markFailedIfPending`, "update if status is X") — status policy belongs to the use case that owns it.
- No domain imports, no `HttpsError`, no ApiModels, no business rules.
- **Firestore I/O only**: no Auth, Storage, HTTP, provider services, other GCP products, or other repositories. A project exception is listed in `CLAUDE.md` → Project nuances and is never copied.
- Results: missing → `null`; empty list → `[]`; unreadable data → a plain `Error` with the id. No `*OrThrow` methods (the `architecture` rule → Units of work).
- Reads take an optional `transaction` (dual-mode); writes take `transaction` first, then `params`.

## DB registry

- Every collection, document path, and intentional collection-group query is an entry of the one registry object in `core/db` (`db.foos`, `db.foo(fooId)`), each with a typed converter (`createFirestoreConverter(FooEntitySchema, FooMigrator)`). No `firestore().collection("…")` and no path strings anywhere else.
- The registry also exposes `runTransaction`, `batch`, and `bulkWriter`, so use cases never reach the Admin SDK directly.

## Versioned entities

When the project versions entities (a Zod schema per version `vN`, a `_version` field, migrators, a `latest` export):

- Historical `vN` schemas are immutable. A shape change adds `vN+1`, a pure migrator `vN → vN+1`, and moves `latest`; reads go converter → migrator → latest. `_version` on the entity type is `z.literal(N)`.
- **Full-document writes for content.** Content, nested-object, or draft + published updates take the full latest `FooEntity` and `transaction.set` it. Callers read (migrated to latest), apply edits, and pass the whole entity.
- **Partial updates** (`partialUpdateWithinTransaction`): only fields with the same shape on every live schema version; never nested objects or draft / published sides; never stamp `_version` (disk would claim latest while untouched fields stay old, and the converter would skip the migrator).
- Create writes the full typed entity with `_version` (an entity with draft / published sides starts with an empty published side, e.g. `published: null`).

## Transactions

- The use case owns the transaction and opens it through the registry (`db.runTransaction`); template: `working-with-firestore`.
- Repositories and `*WithinTransaction` helpers run inside the caller's transaction and never open their own; never nest transactions.
- All reads before the first write.
- The callback can re-run on contention: no irreversible side effects inside it (network, Storage, task enqueue, provider calls). Do them after commit, idempotently.
- Production caps: 1 MiB per document; 10 MiB per transaction or batch payload (reads count). Separate batches are not atomic.

## Consistency and cost

A change touching more than one document names its races, invariants, retry behavior, and worst-case payload while planning; hot paths keep fan-out low, cold paths store ids only (`working-with-firestore`).
