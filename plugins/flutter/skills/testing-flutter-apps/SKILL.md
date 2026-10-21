---
name: testing-flutter-apps
description: Write, run, and verify unit, widget, golden, and integration (Patrol) tests in a Flutter app (web or mobile), test first — picking the owning suite, the scripts/test.sh unit / e2e / live entry points, the coverage gate, and the manual live smoke against real providers with a spend cap. Use when adding tests, covering changed behavior, executing tests, diagnosing suite setup, or changing test infrastructure.
---

# Testing

Policy: the stack `testing` rule (which suite owns which behavior, doubles, coverage). Use cases: `testing-use-cases`; screens, blocs, and goldens: `writing-widget-tests`; the app without a backend: `mocking-backend-for-tests`; Patrol how-to: `writing-patrol-tests`; first-time Patrol setup: `setting-up-patrol`; database round-trips: `persisting-with-isar` → Tests. Suites, harness names, and the project's unit / integration split: `CLAUDE.md` → Project facts and the repository's `.claude/rules/`.

Once a suite exists for a unit, further changes require tests. Automated tests never call a real backend.

## Authoring (test first)

1. Read the target and neighboring tests before designing cases.
2. Pick the suite by the layer that owns the behavior (`testing` rule → Where each behavior is tested): use cases and domain logic in domain unit tests with mocked repositories; stores and repositories as round-trips against a real test database with the API client mocked; screens and their blocs as widget and golden tests; flows across screens in Patrol.
3. Build a state machine from the implementation's branches (widget → bloc → use case → repository → client / DB), not the schema alone. One test per transition; cover empty / error / auth edges and bounds.
4. Write the tests first and run them: each fails, and for the right reason (a missing behavior, not a compile error or a broken stub). A bug fix starts with a test that reproduces the bug.
5. Implement the minimum to pass; refactor with the tests green.
6. Seed only what the case needs (DTO builders, test database, API-client stubs). Assert observable behavior, not private state.
7. Run the narrowest command below, then `flutter analyze` if production code changed.

Prefer the fewest tests that still fail if the logic breaks. No tests beside production files under `lib/`; integration tests keep their own fixtures and mocks and do not import another package's `test/` helpers.

## Commands

- Everything before a push: `scripts/test.sh unit` — format, analyze, layer check, generated code up to date, unit, widget, and golden tests per package with coverage, then the coverage gate (`tool/check_coverage.dart` over `coverage-exclusions.txt`). The pre-push hook runs it.
- One file while working: `flutter test test/path/foo_test.dart` in the package directory; `dart test` in the pure-Dart `domain` and `utils` packages.
- Goldens: `flutter test --update-goldens test/path/foo_page_test.dart`, then look at every changed image.
- Patrol: `scripts/test.sh e2e [patrol args]` on a booted device (`writing-patrol-tests` → Running).
- Live smoke: `scripts/test.sh live` (below), never from a hook or another target.
- Coverage of one package: `flutter test --coverage` in the package, then `dart run tool/check_coverage.dart modules/<package>` from the root.

## Live smoke

A short manual suite proving the real providers are configured and wired together; the only place a test may call a paid or metered service (`testing` rule → Rules).

- **When:** before a production release; after a provider, key, region, or bundle id change; once for a new environment. Never on a schedule or in a hook.
- **Where:** a real device, the staging flavor, staging keys with provider-side spend limits.
- **What:** one cheap call per provider along the main loop the project lists (sign in with a real one-time code to a team test number, one real push to the test device, one upload to object storage, one AI call on a tiny image, sign out).
- **Cost cap:** the script counts calls and stops at its budget (the project sets it, a handful per provider); `scripts/test.sh live` asks for confirmation before it starts.
- **Record:** the result and the call count go into the release PR or release notes.


## Coverage and edge cases

- Cases come from the implementation's state machine (widget → bloc → use case → repository → store): each branch, each repository outcome (value, empty, each exception), each cache policy, each conversion edge.
- The recommended gate: 100% line coverage of handwritten code per package, from `flutter test --coverage` over unit, widget, and golden tests; coverage never drops in a change. The project states its gate in Verification.
- **Closed exclusion list** in one `coverage-exclusions.txt`, changed only with a reason in the PR: generated code (`*.g.dart`, generated API client and models, localization, routes), `lib/main*.dart` wiring, and thin SDK adapters whose fakes are tested instead (their mapping and error handling stay covered). No `// coverage:ignore` elsewhere.
- Each test file walks the edge checklist that applies: empty / one / many; zero, negative, maximum, maximum + 1; null, missing, unknown enum values; Unicode and very long text in every locale; time boundaries (−1 s / exactly / +1 s, midnight, DST days, another time zone); network lost mid-upload; repeated taps and retries.
- Table-driven tests over the cross product of inputs that matter; property-based tests for invariants (ordering is total and stable, the queue sends each item once and in order).
- A test that fails without a code change is a defect, fixed or deleted within days; never skip or quarantine a test to get green.

## Offline-first cases

Where the app queues actions (`architecture` rule → Offline and sync): a retry with the same idempotency key creates one item; a restart and an app update keep the queue; a full session offline then network sends every item once and in order; another user never sends the queue; a refusal rolls back, a network error retries; online-only actions are never queued; an expired cursor reloads the bundle; nothing optimistic shows a server verdict.

## Checklist

- Tests written first and seen failing for the right reason.
- No real backend; paid providers mocked; the network is blocked in the Flutter packages' tests (`flutter_test_config.dart`).
- Every new screen state has its widget test and golden; coverage gate green.
- New API-client methods stubbed in every integration test that reaches them.
- Targeted command passes; failures reported exactly.
