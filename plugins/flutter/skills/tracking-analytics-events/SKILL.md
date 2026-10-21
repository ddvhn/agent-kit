---
name: tracking-analytics-events
description: Add product analytics to a Flutter app the kit way — one Analytics contract in domain, a sealed AnalyticsEvent per tracking-plan event with ids only, a buffered batch sender in data (persisted buffer, flush by size, age, interval, on background and on network, a 503 or offline keeps the buffer), screen views from route names, consent and opt-out, a fake for tests, and optional Diagnostics breadcrumbs and a local log file for support. Use when adding analytics, a new tracked event or property, screen tracking, or support diagnostics.
---

# Tracking analytics events

Policy: the `architecture` rule → Logging. Only for apps whose `CLAUDE.md` declares analytics and where events go ("Analytics: own backend" for the batch sender below; another destination is an ADR). The tracking plan (event names, properties, who receives them) and consent rules: `CLAUDE.md` → Project facts and the repository's `.claude/rules/`.

**Ask first:** adding a third-party analytics SDK, sending any property that is not an id or an enum, and tracking before consent where the market requires it.

## Shape

```
modules/domain/lib/src/analytics/
  analytics.dart             # abstract interface class Analytics { void track(AnalyticsEvent e); }
  analytics_event.dart       # sealed AnalyticsEvent + one final class per tracking-plan event
modules/data/lib/src/analytics/
  analytics_impl.dart        # buffers, persists, sends batches
  analytics_api_client.dart  # POST …/events
modules/ui/lib/src/application/router/
  analytics_route_observer.dart  # screen views from route names
```

## Events

```dart
sealed class AnalyticsEvent {
  const AnalyticsEvent();
  String get name;
  Map<String, Object> get properties;
}

final class FooSaved extends AnalyticsEvent {
  const FooSaved({required this.fooId, required this.source});

  final String fooId;
  final FooSaveSource source; // enum, sent as its name

  @override
  String get name => 'foo_saved';

  @override
  Map<String, Object> get properties => {'foo_id': fooId, 'source': source.name};
}
```

- One class per event in the tracking plan; names `object_verb` in snake_case; properties are ids, enums, counts, and durations. Never names, phone numbers, emails, free text, coordinates, tokens, or URLs.
- Events are tracked where the action succeeds: the use case or the action bloc on `Success`, not the button's `onPressed` (that would count failed and repeated taps).
- `track` is fire-and-forget and never throws; it must not slow the action.

## Sender

```dart
final class AnalyticsImpl implements Analytics {
  // _buffer is persisted (a small database collection or a file) so events
  // survive a kill; each event gets an id for server-side dedup.
  @override
  void track(AnalyticsEvent event) {
    if (!_consent.allowsAnalytics) return;
    _buffer.add(BufferedEvent.from(event, id: _uuid.v7(), at: _clock.now(), session: _sessionId));
    if (_buffer.length >= _maxBatch) unawaited(flush());
  }

  Future<void> flush() => _serial.add(() async {
    final batch = _buffer.take(_maxBatch);
    if (batch.isEmpty) return;
    try {
      await _api.sendEvents(batch);
      _buffer.remove(batch);
    } on Object catch (_) {
      // offline, timeout, 5xx, 503 with Retry-After: keep the buffer, try later
    }
  });
}
```

- Flush when the batch reaches its size (50), the oldest event reaches its age (60 s), every 30 s in the foreground, on `AppLifecycleState.paused`, and when the network returns. The buffer is capped (drop the oldest beyond 1000) so a long offline period cannot fill the disk.
- One `Analytics` instance (a lazy singleton in data); the dev flavor sends to the dev backend or a no-op, never production.

## Screen views

`AnalyticsRouteObserver` (a `NavigatorObserver` added to the router) tracks `ScreenViewed(name: route.settings.name)` on push and pop. Route names come from the typed routes, never from paths with ids.

## Consent and opt-out

- The consent state lives in the session or settings repository; `Analytics` checks it on every `track`. Opting out clears the buffer.
- Advertising ids and cross-app tracking are out unless the project decided them (and on iOS they need App Tracking Transparency).

## Diagnostics (optional)

For support without personal data: a `Diagnostics` contract that keeps a ring buffer of breadcrumbs (screen names, action names, error codes, request ids) and the logger's rotating `latest.log` in the app's support folder. A "Send diagnostics" action in settings attaches them to a support request; nothing leaves the device without that tap.

## Tests

- Domain: each event's `name` and `properties` (only allowed keys and types).
- Data (`modules/data/test/analytics/`) with a mocked API client and a steppable clock / `fake_async`: flush by size, by age, by interval, on pause; a failed send keeps the batch and the next flush resends the same event ids; the cap drops the oldest; no consent → nothing buffered.
- UI: the action bloc's screen test verifies `FakeAnalytics.events` contains `FooSaved` once after a double tap, and nothing on failure. `FakeAnalytics` records events in a list; Patrol replaces `Analytics` in the harness.
