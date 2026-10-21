---
name: designing-client-sync
description: Design or extend server-to-client sync the hint → delta way — an ids-only change log per tenant and scope written in the same transaction, opaque cursors that never skip a late-committing transaction, the delta endpoint reading entities through module policies, op remove, 410 on an expired cursor with a bootstrap bundle, poll-interval header, silent push hints, and later SSE. Use when a client needs to see server changes, when adding a new topic to the change log, or when choosing polling, push, SSE, or WebSocket.
---

# Designing client sync

Use it when clients keep local data or work offline (`backend-api` rule → Tenant context). Tenancy: the `backend-security` rule → Multi-tenancy. The project's endpoint names, topics, retention, and poll intervals: `CLAUDE.md` and the repository's rules.

## Why hint → delta

- One read path for every channel: push, poll, screen open, and SSE only *hint*; the client always pulls the delta. A missed hint costs latency, never data.
- Writes stay REST with idempotency keys (offline queues retry them); no WebSocket server to scale, no connection state, works through every proxy and on bad mobile networks.
- The change log holds ids only, so it never leaks data a plain `GET` would refuse: the delta reads each entity fresh through the owning module's policy.

## Change log table

```sql
CREATE TABLE sync.changes (
    tenant_id   uuid        NOT NULL,
    scope_kind  text        NOT NULL CHECK (scope_kind IN ('tenant', 'site', 'membership')),
    scope_id    uuid        NOT NULL,
    topic       text        NOT NULL,          -- 'foo', 'bar'; one per entity type
    entity_id   uuid        NOT NULL,
    op          text        NOT NULL CHECK (op IN ('upsert', 'remove')),
    txid        xid8        NOT NULL DEFAULT pg_current_xact_id(),
    seq         bigint      GENERATED ALWAYS AS IDENTITY,
    created_at  timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (created_at);              -- daily partitions, dropped after the retention
```

- Written by the use case in the **same transaction** as the data change, through one recorder port (`changes.Record(tx, topic, entityID, scope, op)`), never by triggers that hide it.
- Row-Level Security like every tenant table; index `(tenant_id, txid, seq)`.
- Scope decides who sees the hint: the whole tenant, one site, or one membership (personal items). Visibility is still decided by the policy at read time.

## Cursor that never skips

A sequence alone is unsafe: transaction T1 takes seq 10, T2 takes 11 and commits first; a client reading up to 11 skips 10 forever. Order by transaction id and read only transactions older than the oldest running one:

```sql
SELECT … FROM sync.changes
WHERE tenant_id = $1 AND (txid, seq) > ($2, $3)
  AND txid < pg_snapshot_xmin(pg_current_snapshot())
  AND (scope_kind = 'tenant' OR scope_id = ANY($4))
ORDER BY txid, seq
LIMIT $5;
```

- The cursor encodes `(txid, seq)` plus an issue time, signed or encrypted so a client cannot forge one; filters come from the caller's permissions, never from the cursor.
- The horizon is cluster-wide: one long transaction holds every delta back. Keep transactions short, run analytics on a replica, and alert on transaction age over a minute.
- A cursor older than the log retention → `410 sync.cursorExpired`; an unknown or tampered cursor → `400 sync.cursorInvalid`; no cursor → no changes and a fresh cursor.

## Delta endpoint

1. Resolve the acting membership; load the page of change rows; collapse repeats of one entity to the last op.
2. For each row, ask the owning module's public interface to fill the entity for this actor (`FillChange(ctx, actor, change)`); not visible any more → emit `op: remove`. Unknown topics are a server bug, not a client one.
3. Return `{ changes: [{ topic, entityId, op, entity? }], cursor, hasMore }` and the `Sync-Poll-After` header. The client repeats at once while `hasMore`.
4. Batch the reads per topic (one query per topic per page), never one query per change (N+1).

## Bootstrap bundle

- `GET /v1/me/offline-bundle` (or the project's name) returns everything a client needs to start for one membership plus a cursor, read in one repeatable-read, read-only transaction so data and cursor agree.
- Clients load it on first start, on switching tenant, and after `410`. A change may arrive twice (after the bundle, after a retry); every change is an upsert or a remove, so applying it twice is harmless.

## Hints

- **Silent push**: `{ t: "sync", m: membershipId }` and nothing else; collapsed per membership and sent at most once per few minutes per device unless urgent; clients wait a random delay before pulling.
- **Poll**: per screen intervals on the client, never in the background; the server raises `Sync-Poll-After` under load; clients add ± 20% jitter.
- **SSE later** (`GET /v1/me/events`): events carry only the new cursor; heartbeat every 25 s; one connection per client; the same delta afterwards. Add it when polling cost or latency is measured as a problem.
- WebSocket only by an ADR with a measured need (collaborative editing, sub-second presence).

## Adding a topic

1. Name the topic after the entity; add it to the contract's topic enum (clients skip unknown topics but keep the cursor).
2. Record a change in every use case that creates, updates, deletes, or changes visibility of the entity (membership or permission changes produce `remove` / `upsert` for the affected scopes).
3. Implement the fill in the owning module with the same policy as its `GET`.
4. Tests: each write records exactly one change in the same transaction (rolled back write → no change); the delta returns the entity to an allowed actor and `remove` or nothing to others; a cross-tenant cursor sees nothing; a late-committing transaction is not skipped; `410` and `400` paths.
