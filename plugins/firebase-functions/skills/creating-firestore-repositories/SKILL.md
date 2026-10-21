---
name: creating-firestore-repositories
description: Create or extend typed Firestore repositories in a Firebase Functions backend — object export, naming, dual-mode reads, WithinTransaction writes, partial updates, queries, and their emulator unit tests. Use when adding a repository, CRUD or query methods, or fixing repository transaction signatures.
---

# Creating repositories

Policy (CRUD only, Firestore only, registry, versioned writes, transactions): the `data` rule — this skill is the template. Transactions in use cases, batches, size and cost: `working-with-firestore`. Unit suites: `testing-cloud-functions`. The project's registry name, repository folder, and legacy outliers: the repository's rules.

Do not mass-refactor legacy repositories (for example class-based ones) unless asked; new work follows this shape.

## Workflow

1. Read the closest neighbor repository and its unit test.
2. Confirm the entity schema and its registry entry exist (add them first — `scaffolding-functions-backend` → `source-templates.md` → core/db shows the shape).
3. Write the unit test for the new method first (found / missing / transactional — see Tests) and watch it fail.
4. Add `fooRepository.ts` beside its peers (a feature subfolder only if peers use one): reads first, then `*WithinTransaction` writes.
5. If neighbors sit under a coverage gate, gate the new file too and keep it at the threshold.
6. Lint, typecheck, the unit suite (`CLAUDE.md` → Verification).

## Shape

```typescript
import {Transaction} from "firebase-admin/firestore";
import {db, FooEntity} from "@core/db";

export const FooRepository = {
  generateId(): string {
    return db.foos.doc().id;
  },

  async getById(
    params: {fooId: string},
    transaction?: Transaction,
  ): Promise<FooEntity | null> {
    const ref = db.foos.doc(params.fooId);
    const doc = transaction ? await transaction.get(ref) : await ref.get();
    if (!doc.exists) return null;
    const data = doc.data();
    if (!data) {
      // Unclassified internal failure: nobody branches on it.
      throw new Error(`Foo '${params.fooId}' has unreadable data`);
    }
    return data;
  },

  async getAllByCreatedBy(
    params: {createdBy: string; limit: number},
    transaction?: Transaction,
  ): Promise<FooEntity[]> {
    const query = db.foos.where("createdBy", "==", params.createdBy).limit(params.limit);
    const snapshot = transaction ? await transaction.get(query) : await query.get();
    return snapshot.docs.map((doc) => doc.data());
  },

  /** One page after the cursor document; `null` when the cursor document no longer exists. */
  async getPageByCreatedBy(params: {
    createdBy: string;
    limit: number;
    startAfterId?: string;
  }): Promise<FooEntity[] | null> {
    let query = db.foos
      .where("createdBy", "==", params.createdBy)
      .orderBy("createdAt", "desc")
      .limit(params.limit);
    if (params.startAfterId !== undefined) {
      const cursor = await db.foos.doc(params.startAfterId).get();
      if (!cursor.exists) return null;
      query = query.startAfter(cursor); // snapshot cursor: its orderBy values plus the document id break ties
    }
    const snapshot = await query.get();
    return snapshot.docs.map((doc) => doc.data());
  },

  createWithinTransaction(transaction: Transaction, params: {foo: FooEntity}): FooEntity {
    transaction.create(db.foos.doc(params.foo.id), params.foo);
    return params.foo;
  },

  updateWithinTransaction(transaction: Transaction, params: {foo: FooEntity}): FooEntity {
    transaction.set(db.foos.doc(params.foo.id), params.foo);
    return params.foo;
  },

  partialUpdateWithinTransaction(
    transaction: Transaction,
    params: {fooId: string; ratingCount?: number},
  ): void {
    const changes: {ratingCount?: number} = {};
    if (params.ratingCount !== undefined) changes.ratingCount = params.ratingCount;
    transaction.update(db.foos.doc(params.fooId), changes);
  },

  deleteWithinTransaction(transaction: Transaction, params: {fooId: string}): void {
    transaction.delete(db.foos.doc(params.fooId));
  },
};
```

- Object export, not a class. Entities, schemas, and `db` come from the `core` DB module.
- Return entities only; the API maps `FooEntity` → `FooApiModel`.
- `create` (fails when the document exists) for new documents — with a deterministic id it makes a retried create detectable; `set` for full updates.

## Naming

| Kind | Name |
| --- | --- |
| Id | `generateId()` |
| Single read | `getById`, `getByBarId` (returns `FooEntity \| null`) |
| Lists | `getAllBy…` (`getAllByCreatedBy`) — bounded by `limit` |
| Pages for a paged callable | `getPageBy…({…, limit, startAfterId?})` → `FooEntity[] \| null` (null: the cursor document is gone) |
| Create / full update / delete | `createWithinTransaction`, `updateWithinTransaction`, `deleteWithinTransaction` |
| Version-invariant partial | `partialUpdateWithinTransaction` (never stamps `_version`) |
| Narrow field write | a descriptive `*WithinTransaction` only when a full rewrite is wrong (`updateDraftUpdatedAtWithinTransaction`) |
| Non-transactional single write | `create`, `update`, `delete` — only where neighbors have them, for handler-level single writes |

- One argument object named `params` with an inline type; reads take `(params, transaction?)`, writes take `(transaction, params)`.
- Id fields: `{entity}Id` (`fooId`, `barId`).
- No `getByIdOrThrow`: the throwing read is the domain helper `getFooOrThrow` (the `architecture` rule → Units of work).

## Queries

- Paged callables (contract: the `architecture` rule → API boundary): the cursor is the last item's document id; the repository resolves it to a snapshot and calls `startAfter(snapshot)`; the use case fetches `limit + 1` to compute `nextCursor`. `offset` only when matching an existing peer (it still bills the skipped reads).
- No unbounded scans. A new composite filter or `orderBy` needs an entry in `firestore.indexes.json` (`securing-firebase-data` → Indexes); the emulator does not enforce indexes.
- Collection-group queries are intentional registry entries, never ad-hoc `collectionGroup` calls.

## Tests

Unit × Firestore emulator, in the repository unit-test folder, mirroring the neighbor:

- get: found / missing / unreadable data
- the transactional read path
- create / update / delete within a transaction (+ the persisted `_version` when versioned; partial updates leave `_version` unchanged)
- every new filter, ordering, `limit`, `startAfter`
- seed with `mockFooEntity({...})` builders through the registry; reset the emulator before each test

## Anti-patterns

- Class repositories for new entities; params-first write signatures; reads without the optional `transaction`
- Hardcoded collection paths or raw Admin SDK collections
- Domain logic, status transitions, `HttpsError`, or `*OrThrow` in a repository
- A partial content update that stamps `_version` (the `data` rule → Versioned entities)
- Optional nested `draft` + `published` patches instead of a full entity `set`
