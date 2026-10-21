---
description: Flutter test policy — test first, which suite owns which behavior (domain unit, data unit with a real temp database, widget and golden tests with real blocs, Patrol flows), every control in every state, goldens per state, no network or paid services in tests, the coverage gate, local checks
---

# Testing (Flutter)

Core `architecture-principles` → Test-Driven Development applies: a failing test first, failing for the right reason; adversarial cases before the happy path. How-to: `testing-flutter-apps`; use cases: `testing-use-cases`; screens and goldens: `writing-widget-tests`; Patrol: `writing-patrol-tests`; the app without a backend: `mocking-backend-for-tests`. Commands: `CLAUDE.md` → Verification.

## Where each behavior is tested

One behavior, one owning suite; a higher suite does not repeat a lower one's edge cases.

| Behavior | Suite | Doubles |
| --- | --- | --- |
| Models, use cases, calculators | `domain/test/`, `dart test` | `mocktail` repository contracts |
| API client requests, headers, error codes; mapping | `data/test/` | a stub HTTP session; captured JSON fixtures |
| Database, repositories, queue and sync | `data/test/` | a real database per test in a temp folder; API client mocked; steppable clock |
| Screens, their states, and their blocs | `ui/test/` widget and golden tests | real blocs over fake use cases; real theme and copy |
| Flows across screens, DI, navigation, native dialogs | Patrol in `patrol_test/` | only I/O replaced |

## Rules

- **Every control in every state**: enabled, disabled, loading, success, each error, offline, empty, maximum; a double tap makes one action; no overflow at text scale 1.3 and 2.0 on a 360-wide screen.
- One base golden per screen state and one stress golden per screen; `Adaptive*` widgets per platform. An updated golden is looked at before it is committed.
- Tests in the Flutter packages (`data`, `ui`) run with the network blocked (`HttpOverrides` in `flutter_test_config.dart`); pure-Dart packages have no HTTP client to block. No test at any level calls a real backend or a paid provider; real providers only in the manual live smoke (`testing-flutter-apps` → Live smoke).
- Time is injected; no test sleeps or reads the wall clock. Reset the service locator, database, and mocks per test.
- Every enum from the API has a test with an unknown value.
- **Coverage**: the recommended gate is 100% of handwritten lines per package, with a closed `coverage-exclusions.txt` (generated code, `main*.dart` and `bootstrap.dart`, thin SDK adapters, web-only conditional-import files), changed only with a reason; a package without tests or a file no test loads fails the gate. The project states its gate in Verification; coverage never drops.
- A test that fails without a code change is a defect; never skip or quarantine to get green.
- One script runs the suites (`scripts/test.sh unit | e2e | live`); git hooks run format, analyze, and `gitleaks` before a commit and the unit suite before a push. Never `--no-verify`.
