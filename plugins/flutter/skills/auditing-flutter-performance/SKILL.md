---
name: auditing-flutter-performance
description: Audit and optimize Flutter performance — jank, rebuilds, lists, maps, images, network calls, and local DB.
---

# Performance Audit

Use this skill when the user asks to optimize performance, reduce jank, fix slow screens, or audit frame/build times.

## Steps

1. **Profile first** — in profile mode on a real device (`flutter run --profile`; debug-mode timings mean nothing), with DevTools Performance / CPU / memory. Don't guess. Name the slow route or screen (a list, a map, media playback, upload / download).

2. **Rebuilds and `build()`**
   - Missing `const`, creating large widgets/closures in `build`.
   - Blocs emitting too often; use value equality and `distinct` streams where neighbors do.
   - `setState` / cubit emit for work that could be a `Listenable` or selector.

3. **Lists and maps**
   - Unbounded `Column`+`map` instead of `ListView.builder` / slivers; long lists without `itemExtent` / `prototypeItem` where rows have a fixed height.
   - Map markers rebuilt on every camera / map-type / GPS tick.

4. **I/O**
   - Sequential network calls that could be parallel (`Future.wait`) without breaking ordering invariants.
   - Over-fetching (no `limit` / cursor pagination).
   - Local DB: missing indexes, loading all rows when one id is enough.
   - Image/audio decode, compression, hashing, large JSON parsing, uploads, and downloads on the UI isolate (`Isolate.run` / `compute`); reuse existing media pipelines.
   - Requests per screen and per poll: N+1 reads instead of one delta or batch; polling faster than the screen needs, without jitter, or continuing in the background (`syncing-server-changes`).
   - Offline queue flushes one item at a time but never blocks the UI; database queries behind each screen use indexes.

5. **Assets**
   - Oversized images, missing cache width/height, decoding full-size images for thumbnails.

6. **Platform**
   - Subscriptions not cancelled in `close()` / `dispose()` (leaks → jank later).
   - Location / sensor listeners and poll timers not paused in the background (mobile).
   - Cold start: work before the first frame in `bootstrap` (SDK setup, database open, network calls) that could run after it; measure on the slowest device the project supports (`flutter run --profile --trace-startup`).
   - Web: bundle size and first load (`flutter build web --release` output size, deferred imports for rarely used screens).
   - Platform splits (web vs mobile factories, mobile-only location / purchases / background audio) can differ in cost — call out which platform a finding applies to.

7. **Recommendations** — High / Medium / Low impact and effort. Measurable (frame time, fetch count), not premature micro-opts.

## Notes

- Core `minimal-change`: do not add memoization frameworks if a `const` widget or a `distinct` stream is enough.
