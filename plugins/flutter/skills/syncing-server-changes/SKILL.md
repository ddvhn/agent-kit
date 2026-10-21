---
name: syncing-server-changes
description: Requirements and test checklist for keeping a Flutter app's local store in step with the server through "hint, then delta", for apps that declare delta sync — a full bundle on first load, a delta endpoint with one cursor per account, removals, unknown topics skipped, an expired cursor (by the server's code) reloading the bundle, rows with an open queue item never overwritten, coalesced sync runs, triggers (push, silent push, resume, screen open, sent queue item, poll timer), foreground polling with jitter and the server's poll-after hint that stays paused while a poll is in flight, freshness and stale warnings. The project writes the code against these requirements, test first. Use when adding sync, a new synced entity or topic, polling for a screen, handling silent pushes, or fixing stale or duplicated data.
---

# Syncing server changes

Only for apps whose `CLAUDE.md` declares "Sync: delta" with its endpoints. Without it, screens use cache-then-refresh reads (`data` rule → Caching; `writing-load-blocs`) and observe the store (`observing-data`). Sending local actions: `queueing-offline-actions`; storage: `persisting-with-isar`. Endpoint paths, topic names, error codes, headers, poll intervals, and the stale threshold below are examples; the project's values: `CLAUDE.md` → Project facts.

This skill states **what** sync must do and the test that proves each point; the project writes the code, test first (`testing` rule). The project's own sync, once it exists, is the neighbor to copy.

## Policy

- **The local store is the screen's truth.** Every screen paints from the store at once (use case → repository → database), then sync refreshes it; screens observe the store, so a sync repaints them by itself. No screen keeps its own copy of server data.
- Push (visible or a silent data message such as `{"t": "sync"}`), resume, opening a screen, a sent queue item, and the poll timer only **trigger** the delta; a silent push changes nothing on screen by itself.
- No background polling, no WebSocket unless the project decided one. Offline is a banner, not an error screen.

## Shape

```
modules/domain/lib/src/sync/
  repository/sync_repository.dart        # contract (below)
  usecase/sync_now_use_case.dart         # params ({SyncReason reason})
  usecase/next_poll_delay_use_case.dart  # params ({Duration screenInterval}) → Duration
  usecase/observe_freshness_use_case.dart
modules/data/lib/src/
  data_store/local/database/database_client.dart  # + syncCursor, applyChanges, replaceBundle
  sync/                                  # topic appliers: topic → batch read of changed ids
  repository/sync_repository_impl.dart
modules/ui/lib/src/common/sync/          # the poll timer owner and the widget that provides it
```

```dart
abstract interface class SyncRepository {
  Future<void> syncNow({required SyncReason reason});
  Duration? get serverPollAfter; // last hint from the server, null when none
  Stream<DateTime?> observeLastSyncAt();
}
```

Use cases follow `modeling-domain` (a `CallableUseCase*` mixin, record params). The account comes from the session inside the repository; callers never pass it.

## Requirements

Each requirement names its test: `modules/data/test/sync/` (a real database per test, the API client mocked, a steppable clock), `modules/domain/test/sync/`, and the poller's widget test with its real bloc over fake use cases under `fake_async`.

**Bundle and delta**

1. **No cursor loads the bundle; a cursor reads the delta.** Pages are read until the server says there are no more. *Test:* no cursor → bundle; a cursor → delta; paging until `hasMore` is false.
2. **Each page is one transaction with its cursor.** `applyChanges` writes the page's upserts, removals, and next cursor together, so a crash replays a page and appliers stay idempotent (upsert by id). *Test:* a failure on the second page keeps the first page and its cursor; a rerun applies the rest once.
3. **A delta never overwrites a row with an open queue item** (apps with the queue; the queue has one owner, the signed-in user). `applyChanges` skips pending rows for upserts **and** removals; the queue's own answer replaces them (`queueing-offline-actions` → Requirements, 11–12). *Test:* a page with an upsert and a removal for a pending row leaves it unchanged; other rows in the page are updated and removed.
4. **`replaceBundle` protects pending rows the same way.** It replaces the account's cached collections and stores the bundle's cursor, keeping queue items and pending rows. *Test:* after a bundle reload the items and pending rows are unchanged.
5. **Removals and unknown topics.** A removal deletes the local copy; an unknown topic is skipped while the cursor still advances; unknown topics never reach the database. *Test:* both cases.
6. **An expired cursor reloads the bundle — by the server's code.** The data layer's `ApiException` carries the contract's error code as `serverCode` (`handling-errors`); the repository matches `serverCode == 'sync.cursorExpired'` (the project's code), never the transport `code` enum and never the message. *Test:* the expired-cursor answer reloads the bundle; requirement 4 holds through it.
7. **One cursor per account.** Switching accounts never mixes rows. *Test:* an account switch reads and writes only that account's cursor and rows.
8. **Runs are coalesced.** A trigger during a run asks for exactly one more run after it; every caller's future completes. *Test:* three triggers during a run → one more run, all three futures complete.

**Polling**

9. **Delay.** The next poll waits the larger of the screen's interval and the server's poll-after hint (for example a `Sync-Poll-After` header), with ±20% jitter from an injected random source; after a silent push, a random short delay (for example 0–30 s). *Test:* the delay stays within ±20% of the larger value; the hint wins when larger.
10. **Only in the foreground, for the visible screen.** The timer lives in a bloc provided by a small widget that forwards app lifecycle (`AppLifecycleListener` pause and resume) and closes with its screen; widgets never hold timers or call use cases. *Test:* the poller stops on pause and on dispose.
11. **Pause sticks while a poll is in flight.** A pause during a running poll is not undone when that poll ends: the reschedule checks a paused flag. *Test:* pause while the sync future is pending, complete it → no new timer until resume.
12. **A failed poll is logged and retried on the next tick**, never shown as an error screen. *Test:* a failing sync reschedules the timer.
13. **The timer owner is the one `Cubit<void>`.** It renders nothing, so it may be a `Cubit<void>` (the `blocs` rule's single exception) or carry a small state; no other bloc uses `void`.

**Freshness**

14. Freshness is shown ("Updated at 08:42") with a soft warning past the stale threshold. *Test:* the warning appears exactly at the threshold, not a second before.

## Checks

- [ ] Every requirement above that applies has its test, written first and seen failing
- [ ] Pending rows survive deltas and bundle reloads; the expired cursor is matched by `serverCode`
- [ ] No polling in the background; pause sticks through an in-flight poll
- [ ] The UI imports no data package; the sync repository is reached only through use cases
