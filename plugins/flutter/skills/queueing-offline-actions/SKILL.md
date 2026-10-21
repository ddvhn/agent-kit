---
name: queueing-offline-actions
description: Requirements and test checklist for the persistent offline action queue of a Flutter app that declares queued offline writes — queue records behind DatabaseClient methods, the optimistic write and the enqueue in one transaction, pending rows that sync never overwrites, one queue owner (no user change while the queue holds items), one idempotency key per item reused on every retry, a serial flush in completion order that skips refused items, explicit rollback on refusal and backoff on transient failures, background flush, user and account scoping, sign-out that flushes or asks, files deleted only after the server confirms, optional trusted completion time and device-key signing, storage and backup. The project writes the code against these requirements, test first. Use when an action must work offline, adding a queued action type, or changing retry, rollback, or sync-on-network behavior.
---

# Queueing offline actions

Only for apps whose `CLAUDE.md` declares "Offline writes: queued" with its ADR (`architecture` rule → Offline and sync; core `architecture-principles` → Offline-first). Without it, writes are online: a spinner in the button and the local copy updated from the response (`writing-action-blocs`). Delta sync after a send: `syncing-server-changes`; database mechanics: `persisting-with-isar`. Queued vs online-only actions and the server's refusal codes: `CLAUDE.md` → Project facts.

This skill states **what** the queue must do and the test that proves each point; the project writes the code, test first (`testing` rule). The project's own queue, once it exists, is the neighbor to copy.

**Ask first:** introducing the queue (an ADR), making an online-only action queueable, purging queued items automatically, changing what counts as a refusal.

## Policy

- **Optimistic, not a verdict.** The UI shows what the user did ("will sync"), never what the server decides (accepted, an amount, a status it has not returned). The server's answer replaces the optimistic state.
- **Online-only actions** (sign-in, account deletion, permissions, payments, and the project's list) are never optimistic or queued; offline their button is disabled with a "needs network" hint.
- **Rollback is explicit and only for queued actions.** A timeout, 5xx, 429, or no network is never a refusal.

## Shape

```
modules/data/lib/src/data_store/local/database/database_client.dart   # queue methods (contract below)
modules/data/lib/src/data_store/local/database/isar_database/models/queue/queued_action_db_model.dart
modules/data/lib/src/data_store/dto/queue/queued_action_dto.dart
modules/data/lib/src/queue/      # the flusher, one sender per action kind, the background entry
modules/data/lib/src/repository/foo_repository_impl.dart   # save = one DatabaseClient call + kick
```

The contract the requirements refer to (names are suggestions; keep one method per step):

```dart
// DatabaseClient
Future<void> saveFooAndEnqueue({required FooDto foo, required QueuedActionDto action});
Future<QueuedActionDto?> nextQueuedAction({required String userId, required String accountId, required DateTime now});
Future<void> completeQueuedAction({required String actionId, FooDto? serverFoo});
Future<void> refuseQueuedAction({required String actionId, required String code, FooDto? serverFoo});
Future<void> rescheduleQueuedAction({required String actionId, required DateTime nextAttemptAt});
```

`QueuedActionDto` holds the item id (uuid v7, which is also the completion order), `kind`, `idempotencyKey`, `userId`, `accountId`, `entityId`, `createdAt`, `attempts`, `nextAttemptAt`, `failureCode`, and the item's file paths. isar_plus: a field named `id` takes `@Id()`, because the field shadows the package's `@id` constant.

## Requirements

Each requirement names the test in `modules/data/test/queue/` that proves it (real database per test in a temp folder, the API client mocked, a steppable clock, fake connectivity).

**Writing**

1. **Optimistic write and enqueue are one transaction.** `saveFooAndEnqueue` writes the row with `pending: true` and the item together. *Test:* a failing put leaves neither the row nor the item.
2. **One idempotency key per item, created once.** The key is made when the user acts and reused on every retry; two fast taps make one item (the action bloc ignores re-entry). *Test:* three transient failures then success → four sends with the same key; a double tap → one item (a widget test in `modules/ui/test` through the real bloc).
3. **No JSON in the repository.** The repository passes DTOs to `DatabaseClient`; the item stores no serialized payload. The sender reads the row by `entityId` through `DatabaseClient` and sends that DTO through the API client, whose store does the wire conversion (`data` rule → Repositories). An action whose input is not an entity row (a delete, a comment) keeps its input in a queue-owned collection written in the same transaction. *Test:* the sender sends the DTO the row holds at send time; the repository file imports no `dart:convert`.
4. **Resending the latest state is safe only because a save is a full replace.** Two saves before a send make two items with two keys; both send the row's latest state. The server does not deduplicate different keys, so this is correct only for a full-replace save. An action that is not idempotent as a whole (an increment, an append) carries its own input (requirement 3) instead of reading the row. *Test:* two saves offline, then network → two sends with different keys, both with the latest state; the server double records it once (by id).

**Flushing**

5. **One item at a time, in completion order.** A flush never runs twice at once. *Test:* two `kick()` calls at once → one send at a time; items sent in id order.
6. **The head blocks the queue until it is due.** `nextQueuedAction` returns the oldest non-refused item of this user and account, or null when that item's `nextAttemptAt` is after `now`; a later item never jumps ahead. *Test:* the second of three fails transiently → `nextQueuedAction` is null until its backoff ends, then returns the second; the third waits.
7. **Refused items are skipped, not retried.** A refusal (a business error code) restores the server's copy, marks the item with its `failureCode`, and tells the user; `nextQueuedAction` skips marked items so the rest flush. The item stays visible until the user dismisses it. *Test:* a refused head → the next item is sent; the row shows the server's copy.
8. **Transient failures reschedule with backoff.** Timeout, 5xx, 429, and no network keep the item and set `nextAttemptAt` (`2^n` seconds with jitter, at most 15 minutes). *Test:* each transient kind reschedules; none marks the item refused.
9. **Success replaces the optimistic row.** `completeQueuedAction` writes the server's copy and removes the item in one transaction. *Test:* after success the row equals the server's answer and the item is gone.
10. **Files are deleted only after the server confirms.** Files upload one by one with resume, before the item. *Test:* a failed send keeps the files; success deletes them.

**Pending rows**

11. **A row with an open item stays as the user wrote it.** It is `pending` from the enqueue until the **last** open item for its `entityId` completes or is refused. *Test:* two items for one row → it stays pending after the first completes.
12. **A delta never overwrites or removes a pending row.** The sync's `applyChanges` skips pending rows for upserts and removals (`syncing-server-changes`, requirement 3). *Test:* a delta page with an upsert and a removal for a pending row leaves it unchanged; non-pending rows in the same page are updated and removed.
13. **A bundle reload protects pending rows the same way.** `replaceBundle` keeps queue items and pending rows. *Test:* an expired cursor reloads the bundle; pending rows and items survive.

**Users and sign-out**

14. **One owner of the queue at a time.** Items carry `userId` and `accountId`, and `nextQueuedAction` filters by both. While the queue holds items of user A, no other user signs in on the device: after a forced sign-out (a refused token refresh) the sign-in screen offers only "sign in as A to send N items" or "delete N items" (with A's confirmation text), so the entity collections never hold two users' data and a completion never lands in another user's rows. A project that needs shared devices with several users' queues designs it in an ADR (owner on every row and read, or per-user databases). The auth side is in `adding-flutter-auth` → User change. *Test:* with A's items queued, signing in as B is refused until A's items are sent or deleted, and after "delete N items" B sees none of A's data, also after a restart; a forced sign-out keeps the items and A's pending rows; signing in as A again flushes them.
15. **Clearing user data never wipes the queue silently.** `clearUserData` runs on a user change only, and a user change happens only with an empty queue (14, 16), so it clears every collection; it counts the queue inside its own write transaction and throws a typed `QueueNotEmptyException` when items are there (a check outside it races an enqueue). *Test:* `clearUserData` with queued items throws and changes nothing.
16. **Sign-out flushes or asks.** Sign-out flushes first; with items left (no network, or refused items still listed) it asks "sign out later" or "sign out and delete N items"; only that choice deletes the user's items and clears the user data in one write transaction (one `DatabaseClient` method), so nothing of the user stays for the next one, even if the app is killed midway. The same holds for "delete N items" after a forced sign-out (14). *Test:* offline sign-out → both choices behave as named; a refused item left at sign-out → it is shown, then deleted with the user's choice.

**Lifetime and storage**

17. **The queue survives restarts, app updates, and schema changes.** A database that holds the queue never takes the cache-only reset (`persisting-with-isar` → Schema changes): give the queue its own small database, or migrate the shared one with a tested startup step. *Test:* reopening the database keeps the items; the project's schema-change path keeps them.
18. **Triggers.** `kick()` after an enqueue, when connectivity returns, on resume, after sign-in, and after a sync; a background task (`workmanager`: a periodic task with a network constraint on Android, a `BGProcessingTask` on iOS) builds the data layer only, flushes, and exits; never a flush from a widget. After a successful send, trigger the delta when the app has one. *Test:* a full offline session, then network → every item sent once, in order.
19. **Storage.** Database and queued files in the app support folder, excluded from OS cloud backup (Android `dataExtractionRules`, iOS `isExcludedFromBackup` through `bridging-native-code`). Encryption at rest only where the store supports it: `isar_plus` encrypts only with its SQLite engine (`engine: IsarEngine.sqlite, encryptionKey:` from secure storage); with the default engine rely on the OS file protection and say so in the ADR. Warn when free space is low; never purge.

## Trusted time and signing (when the backend verifies them)

Only when `CLAUDE.md` declares "Device signatures: verified by the backend".

20. An interceptor stores the signed server-time anchor (the project's header pair, for example `Server-Time` and its signature) with the monotonic time and boot id at receipt.
21. At completion the item records the device clock, monotonic time since boot including sleep, the boot id (`bridging-native-code`), the last anchor, and clock changes since it. The server computes the proven time; the client never shows it as a verdict.
22. The completion metadata (times, file SHA-256s, item id, idempotency key, a per-device sequence number) is signed with a non-exportable Keystore / Secure Enclave key registered at sign-in.

*Tests:* moving the device clock does not change the recorded monotonic and anchor values; the sequence number grows by one per item and survives a restart.

## Checks

- [ ] Every requirement above that applies has its test, written first and seen failing
- [ ] No JSON or engine type in a repository; queue methods only on `DatabaseClient`
- [ ] Pending rows are protected from sync and bundle reloads; no user change while the queue holds items
- [ ] Online-only actions are never queued; a refusal is never inferred from a transport failure
