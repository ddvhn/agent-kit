---
name: mocking-backend-for-tests
description: Run a Flutter app without a backend for Patrol flows, demos, design review, and agents — a mock_api dev package with a fixture catalog captured from the contract, playback API clients implementing every data-layer client, scripted errors per call, a steppable clock, injectMockApi replacing the real clients after injectDataLayer, a test/main_mock.dart entry and the mock launch config, never imported from lib. Use when a test or a demo needs the app without a server, building client tasks before the backend implements a merged contract, adding a scenario or fixture, or adding an API client method that every double must implement.
---

# Mocking the backend for tests

Policy: the `testing` rule → Rules; `writing-patrol-tests` → Policy. Patrol harness: `writing-patrol-tests` (each Patrol file still builds its own `mocktail` doubles; the playback clients here are for the mock app, demos, and agents). API clients: `generating-api-clients`.

## Layout

```
modules/mock_api/                       # dev-only package in the workspace
  pubspec.yaml                          # depends on data (testing.dart), domain, utils
  lib/mock_api.dart                     # injectMockApi, MockScenario, SteppableClock
  lib/src/fixtures/                     # JSON captured from the contract, by scenario
    default/foo_list.json
    empty/foo_list.json
  lib/src/clients/playback_backend_api_client.dart
  lib/src/scripted_errors.dart
  test/                                 # the playback clients' own tests
test/main_mock.dart                     # the app with the mock backend
```

- `mock_api` is a `dev_dependency` of the root app only. Nothing under any `lib/` imports it: `tool/check_layers.dart` denies `package:mock_api/` in the app, `data`, and `ui`. The package itself is not in the layer check's list (its `lib/` imports `package:data/testing.dart` by design), so review its imports by hand.
- Fixtures are real response bodies (captured from the local backend or the contract's examples) validated against the contract, never hand-edited to shapes the server cannot return. They contain fake names and reserved phone ranges only.
- **Before the backend exists** (`core:shipping-feature-branch` → Backend and client): fixtures are copied from the contract fixtures the contract PR ships, one folder per scenario, and compared with captures from the local backend at the integration pass. A difference is a defect: fix the side that breaks the contract (a backend bug, or the contract and its fixtures through a contract PR), never by editing the copy; captures replace the copies only once they match the contract fixtures.

## Playback client

```dart
final class PlaybackBackendApiClient implements BackendApiClient {
  PlaybackBackendApiClient(this._fixtures, this._errors);

  final FixtureCatalog _fixtures;
  final ScriptedErrors _errors;

  @override
  Future<FooDto> getFoo({required String fooId}) async {
    _errors.throwIfScripted('getFoo');                     // e.g. fail twice, then succeed
    // Fixtures are wire JSON: parse into the generated model, then convert
    // with the API store's own mapper (exported by package:data/testing.dart).
    final list = _fixtures.list('foo_list', (json) => Foo.fromJson(json).toDto());
    return list.firstWhere((foo) => foo.id == fooId,
        orElse: () => throw const ApiException(.notFound, statusCode: 404, serverCode: 'foo.notFound'));
  }

  @override
  Future<FooDto> saveFoo({required FooDto foo, required String idempotencyKey}) async {
    _errors.throwIfScripted('saveFoo');
    return _fixtures.remember(idempotencyKey, () => foo);  // same key → same answer
  }
}
```

- Every API client of the data layer has a playback client; a new client method gets its playback method in the same change (and the Patrol and unit doubles).
- Writes keep state in memory for the session, so the flow behaves like the server (save then list shows the item); idempotency keys return the first result.
- `ScriptedErrors` takes per-operation scripts: `{'saveFoo': [network, network, ok]}`, `{'getFoo': [api('foo.notFound')]}`, `slow(Duration)`.

## Scenarios and clock

- `MockScenario` names a fixture folder and an error script: `default`, `empty`, `offline`, `serverDown`, `expiredCursor`, `maxData`, `notImplemented` (every draft operation answers `501`, as the real server does: the client shows it as unavailable, and the path with the feature flag off never calls it) (the project adds its own).
- `SteppableClock` implements the domain clock port; the mock app shows a small debug panel (only in `main_mock.dart`) to pick the scenario and step the clock forward, so time-based states can be demoed.

## Wiring

```dart
// test/main_mock.dart
Future<void> main() async {
  await bootstrap(
    app: const Application(),
    overrides: (getIt) => injectMockApi(getIt, scenario: MockScenario.fromEnvironment()),
  );
}
```

- `bootstrap` runs `injectDataLayer` → `injectMockApi` (unregisters and re-registers every API client, the clock, push, analytics, and paid providers with doubles) → `injectDomainLayer` → `injectUiLayer`. Domain and UI run for real.
- Launch config `mock` (`program: test/main_mock.dart`, flavor `dev`) — `configuring-flutter-flavors`. A scenario is picked with `--dart-define=MOCK_SCENARIO=empty`.
- The mock app never reaches the network: the HTTP layer is not even registered, and `HttpOverrides` blocks stray requests in debug.

## Tests

`modules/mock_api/test/`: each playback client against its fixtures (every operation answers, idempotency returns the first result, scripted errors in order, unknown ids → the contract's error code); fixtures parse into the generated models. Add `modules/mock_api` to `flutter_packages` in `scripts/test.sh` (it depends on Flutter through `data`) in the same change, so its tests run in the unit suite and its `lib/` counts toward the coverage gate. The mock app itself (`test/main_mock.dart`) is exercised by agents (`driving-flutter-app`) and demos, not by the coverage gate.
