---
name: writing-background-functions
description: Write Firestore / Storage triggers, scheduled functions, and Cloud Tasks queues in a Firebase Functions backend — at-least-once delivery and idempotency (event id dedupe or state compare-and-set), retries and poison events, enqueue after commit, no irreversible side effects in transactions, structured logging without personal data, cold starts, global init, concurrency, and minInstances. Use when adding or changing a trigger, schedule, task queue handler, or the code that enqueues tasks.
---

# Background functions

Layering, use cases, and errors: the `architecture` rule. Transactions: the `data` rule → Transactions. Callables and HTTP: `writing-cloud-functions`. Tests: `testing-cloud-functions` → Background functions.

A background handler is transport, like a callable: it parses the event, checks it is still relevant, calls one use case, and logs the outcome. The work, its preconditions, and its transaction belong to the use case.

## Delivery and idempotency

Every background invocation can arrive **more than once**, late, and out of order — triggers are at-least-once, tasks and schedules retry. Design each handler so a second run with the same input changes nothing. Pick one:

1. **State compare-and-set** (preferred when the entity has a status): inside the use case's transaction, read the entity and act only from the expected state (`pending` → `processing`); any other state returns without work. The transition itself is the dedupe.
2. **Event id dedupe** (when there is no natural state): `transaction.create(db.processedEvent(event.id), {...})` in the same transaction as the work — `create` fails if the id exists, so a redelivery aborts. Give the dedupe collection a TTL policy (`expireAt` field) so it does not grow forever.
3. **Deterministic output ids**: write results under ids derived from the input (`${fooId}_${locale}`) with `create` / full `set`, so a rerun overwrites or fails instead of duplicating.

Side effects outside Firestore (provider calls, emails, payments, enqueues) are not covered by the transaction: make them idempotent at the provider (idempotency keys, named tasks) or record the intent first and perform it from a retried step that checks the record.

## Retries and poison events

- Event triggers do not retry by default. Turn on `retry: true` only when the handler is idempotent; then a thrown error redelivers with backoff for hours or longer, depending on the event source. Drop events older than the work is useful for (compare `event.time` with now and return), and do not throw for permanent failures (invalid data, missing entity) — log and return, or the event retries until it expires.
- Throw only for transient failures (provider timeout, contention) you want retried.
- `onUpdate` / `onWritten` handlers that write back to the document they listen to must compare `before` and `after` and return when nothing relevant changed — otherwise they trigger themselves forever.

## Firestore and Storage triggers

```typescript
export const onFooPublished = onDocumentUpdated(
  {document: "foos/{fooId}", region: FUNCTIONS_REGION},
  async (event) => {
    if (!event.data) return;
    const before = fooConverter.fromFirestore(event.data.before);
    const after = fooConverter.fromFirestore(event.data.after);
    if (before.status === after.status || after.status !== "published") return;
    await indexPublishedFooUseCase({fooId: after.id, eventId: event.id});
  },
);
```

- Parse snapshots with the registry entry's converter (`fooConverter`, exported from `core/db` beside `db.foos`) so old versions migrate and the shape is validated; never read raw `snapshot.data()` fields.
- The document path string in the trigger is the one allowed place outside the registry; keep it next to the registry entry's path (a shared constant).
- A Firestore or Storage trigger runs in a region compatible with the database or bucket location (a multi-region `nam5` database → `us-central1`); a mismatch fails at deploy. The location: `CLAUDE.md` → Project facts.
- Delete triggers clean up dependents: database references first, files after; each cleanup tolerates "already gone".
- Fan-out over many documents: page through them, or enqueue one task per page; never one unbounded transaction.

## Scheduled functions

```typescript
export const syncFoos = onSchedule(
  {schedule: "every 15 minutes", timeZone: "Etc/UTC", region: FUNCTIONS_REGION, retryCount: 0},
  async () => {
    await syncFoosUseCase({now: Timestamp.now(), batchSize: 200});
  },
);
```

- Runs can overlap when one is slow; take a lease (a lock document with `leaseUntil`, claimed by compare-and-set) or make the work naturally partitioned and idempotent.
- Process a bounded page per run and continue next run (a cursor document), or enqueue tasks; never assume one run finishes everything.
- The schedule string is a param when environments differ (`defineString("FOO_SYNC_SCHEDULE")`).

## Task queues

Handler:

```typescript
export const processFoo = onTaskDispatched(
  {
    region: FUNCTIONS_REGION,
    retryConfig: {maxAttempts: 5, minBackoffSeconds: 30},
    rateLimits: {maxConcurrentDispatches: 4},
    timeoutSeconds: 540,
  },
  async (request) => {
    const payload = ProcessFooPayloadSchema.parse(request.data);
    await processFooUseCase({fooId: payload.fooId, attempt: request.retryCount});
  },
);
```

Enqueue — from the use case, **after** the transaction commits, through a `core` queue service (`FooTaskQueueService`) so tests can swap it:

```typescript
await getFunctions().taskQueue(`locations/${FUNCTIONS_REGION}/functions/processFoo`).enqueue(
  {fooId},
  {id: `processFoo-${fooId}-${revision}`, scheduleDelaySeconds: 0, dispatchDeadlineSeconds: 600},
);
```

- A task `id` makes the enqueue idempotent: a duplicate id is rejected (treat "already exists" as success). Ids cannot be reused for a while after the task ran, so include something that changes per logical job (a revision or attempt number).
- Never enqueue inside a transaction callback: it can run twice or roll back. Record the job state in the transaction (`status: "queued"`), enqueue after commit, and let a scheduled reconciler re-enqueue jobs stuck in `queued` / `processing` past a deadline (the outbox pattern).
- The handler validates its payload with Zod and checks the job state (compare-and-set) before working — a task may arrive after the job was cancelled or finished.
- `rateLimits` protect paid providers; `maxAttempts` and backoff bound the cost of a failing job; after the last attempt, mark the job `failed` from the handler (check `request.retryCount`) instead of leaving it `processing`.
- A raw Cloud Tasks HTTP-target client (when a queue must call a non-`onTaskDispatched` URL) authenticates with an OIDC token or a secret header checked in the handler (the `architecture` rule → Security).

## Logging

- `logger` from `firebase-functions/logger` with structured fields: `logger.info("Foo synced", {fooId, count, durationMs})`. Messages are constant strings; data goes in fields so logs are searchable.
- Log ids, counts, states, durations, error codes. Never personal data (names, emails, phone numbers, addresses, free-text content), tokens, secrets, or whole payloads / documents.
- One line per outcome (started is optional; finished or failed is required) with the event or task id for correlation.

## Cold start, global state, concurrency

- Module scope runs on every cold start and at deploy-time analysis: keep it to imports and cheap constants. Construct SDK clients and services lazily on first use (the service factory) and reuse them across invocations; no network, no `param.value()`, no secret reads at module scope. `onInit(() => …)` for expensive initialization that must run once per instance before the first request.
- v2 instances serve several requests at once (`concurrency`, default 80 when CPU ≥ 1): module-level mutable state is shared between concurrent invocations — never keep request data there. CPU-bound or memory-heavy handlers set `concurrency: 1`.
- `minInstances` removes cold starts at a constant cost per instance; use it only for latency-critical callables, take it from a param so stage can use 0, and say so in the plan.
- Set `timeoutSeconds` and `memory` per function from the work it does; event triggers allow at most 540 s; a task handler is bounded by the task's dispatch deadline (at most 1800 s).

## Checklist

- [ ] Handler is thin: parse, relevance check, one use case, log
- [ ] Idempotent: state compare-and-set, event id dedupe, or deterministic ids — named in the plan
- [ ] Retries: transient errors throw, permanent ones log and return; old events dropped
- [ ] No enqueue or provider call inside a transaction; outbox and reconciler for queued work
- [ ] Self-triggering writes guarded by a before / after comparison
- [ ] Structured logs with ids, no personal data
- [ ] Lazy global init; no request state in module scope; `minInstances` justified
- [ ] Integration test proves a duplicate delivery changes nothing
