---
name: working-with-firestore
description: Plan Firestore access in a Firebase Functions backend — transactions in use cases, side effects after commit, batches and BulkWriter, multi-document races and idempotency, document and transaction size limits, queries and pagination, schema version changes, denormalization vs id-only modeling for read/write cost. Use when changing Firestore access patterns, multi-document writes, or entity schemas.
---

# Working with Firestore

Policy (registry, CRUD-only repositories, versioned entities, transaction rules): the `data` rule. Repository templates: `creating-firestore-repositories`. This skill is the planning how-to.

## Workflow

1. Name the invariants, the use case that owns the transaction, the read-before-write order, and the indexes the queries need.
2. Repository methods do the document operations; the use case composes them inside one `db.runTransaction` (below).
3. Side effects (network, Storage, task enqueue, provider calls) run after the commit, from the use case, idempotently.
4. Many independent writes: `db.batch()` (atomic, one payload cap) or `db.bulkWriter()` (not atomic; set `onWriteError` retry policy, `await close()`; each write must be idempotent).
5. A schema shape change: new `vN+1` + pure migrator + move `latest` (the `data` rule → Versioned entities); content writes after an in-memory migration persist the full entity.
6. Verify typed paths, empty-result semantics, indexes, lint, and the unit / integration suites.

## Transaction with side effects after commit

```typescript
export async function publishFooUseCase(params: {fooId: string; userId: string}): Promise<FooEntity> {
  const published = await db.runTransaction(async (transaction) => {
    const foo = await getFooOrThrow({fooId: params.fooId}, transaction); // reads first
    if (foo.createdBy !== params.userId) throw new FooPermissionDeniedError(foo.id);
    if (foo.status === "published") return foo; // a retry is a no-op
    const next = fooWithStatus(foo, "published"); // pure domain transition
    FooRepository.updateWithinTransaction(transaction, {foo: next}); // writes last
    return next;
  });
  await FooNotificationService.notifyPublished({fooId: published.id}); // after commit, idempotent on fooId
  return published;
}
```

The callback may run several times under contention: it only reads, decides, and writes. Anything that leaves Firestore happens once, after it returns.

## Multiple documents (races, consistency, idempotency)

Any change that reads or writes more than one document names all three during planning:

1. **Races.** Who else writes these documents (another instance, a client, a worker, a trigger)? Which interleavings are legal? The emulator does not show them (the `testing` rule → Emulator ≠ production concurrency).
2. **Invariants.** What must stay true together (parent + children, ids that point at existing documents)? If the payload cannot fit one transaction (Size limits), split **and** say what may lag or orphan, and how the final commit detects a stale snapshot: re-read and compare the copied source ids (the media, blobs, or fields you copied), then abort or restart. `updatedAt` alone is not a join key — other writers (triggers, denormalized-field updates) bump it without changing those sources. Never attach copies from snapshot A onto entity state B.
3. **Idempotency.** What does a retry or a second caller do with the same inputs? Prefer deterministic document ids so `create` fails on the duplicate; a status compare-and-set inside the transaction so a second run is a no-op. Partial success must be safe to resume (fill missing, never duplicate, never clobber a successor).

Prefer one transaction when the invariant needs atomicity and the size cap allows it. Split only with an explicit snapshot check on the join.

## Size limits (plan before you write)

Production Firestore — the emulator does not enforce them:

- **1 MiB per document**
- **10 MiB per transaction or batch payload** (reads count in a transaction)

Errors: document `exceeds maximum size`; `INVALID_ARGUMENT: Transaction too big`.

Estimate the **worst case**, not the sample: cardinality (locales, children, array length, nested maps) × per-item size (strings, number arrays, copied blobs) × documents in the same commit. Near either cap → split (per item, per locale, chunks) or keep large arrays out of that commit. Typical traps: N large array documents in one commit; a fat parent plus many children; reading all of them in the same transaction.

## Queries and modeling

- Equality filters plus one inequality / `orderBy` field; every composite query has an index in `firestore.indexes.json` (`securing-firebase-data` → Indexes).
- Paginate with `limit` + `startAfter`; no unbounded scans; no N+1 reads on hot paths.
- Collection-group queries only when intentional, as registry entries.
- Transactions or batches when several documents must stay consistent; single-document writes otherwise.

## Read / write cost and denormalization

- **Hot paths** (lists, feeds): embed what the client shows so a page of 50 costs about 50 reads, not 50 + N. Update embeds in the same write when cheap, otherwise asynchronously after commit (`writing-background-functions`); accept eventual consistency.
- **Cold paths**: store ids only and resolve on demand; no sync pipeline for rare lookups.
- When proposing duplication, state what is embedded, who updates it, failure and retry behavior, and what may be stale. Never denormalize secrets or large blobs into list documents.

## Checklist

- [ ] Transaction owned by one use case; reads before writes; no side effects inside
- [ ] Worst-case document < 1 MiB and transaction payload < 10 MiB (estimated at plan time)
- [ ] Multi-document change: races, invariants, idempotent retry named; split commits have a stale-snapshot check
- [ ] BulkWriter / batches: retry policy and idempotent writes
- [ ] Hot vs cold modeling chosen deliberately; indexes added
- [ ] Versioned entities: historical schemas untouched; new version + migrator for a shape change
