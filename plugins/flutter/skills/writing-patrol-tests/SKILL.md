---
name: writing-patrol-tests
description: Write, extend, run, and debug Patrol end-to-end tests in a Flutter app (web or mobile) the kit way — a testApp harness with per-test mock dependencies (mocktail double per remote source, real per-test database, platform fakes), FooModule page objects, System for native UI, shared widget keys, one test per file. Use when adding or editing anything under patrol_test/, assigning widget keys for tests, running Patrol tests, or investigating a failing Patrol test. First-time setup is setting-up-patrol.
---

# Writing Patrol tests

Policy: the stack `testing` rule. Suite folder, flavor, device (emulator, simulator, Chrome), and run commands: `CLAUDE.md` → Project facts and Verification. The project's harness, doubles, fixtures, module and key files: the repository's `.claude/rules/`. A project without Patrol: `setting-up-patrol`.

This is the kit's Patrol practice. It differs from LeanCode's upstream Patrol skills and docs: no `ApiClients` or real backends (every remote call is a stubbed double), per-test mock dependencies, `FooModule` naming, keys aggregated in the UI package, the Patrol MCP only where the repository configures it. If a repository still has the upstream skills installed (`patrol-write-test`, `patrol-test-architecture`), this skill wins where they differ.


## Policy

- One `testApp` per file, named after the observable result; each file arranges its I/O in a private `_mockDependencies()`; the body drives the UI only through page-object modules and widget keys from `keys.dart`. UI changes for tests are widget keys only. Never run Patrol files with `flutter test`.
- The harness resets the service locator, preferences, and secure storage, builds the real layers, and replaces every I/O boundary: API clients, the database (one per test), push, camera, device key, connectivity, clock, analytics, every paid provider.
- The changed feature's files run before each PR; the whole suite before a feature merges and before a release. Automated tests never call a real backend, production or staging.

## Suite layout

```
patrol_test/
  test_app.dart                 # testApp harness + MockDependencies record
  fixtures.dart                 # optional: DTO builders and presets (signedIn, loggedOut)
  mocks/
    mock_backend_api_client.dart # mocktail double per remote source
    mock_database.dart          # mockDatabase(): the real DB under a unique name
    fake_foo_service.dart       # FakeFooService per platform service a test configures or drives
  modules/
    module.dart                 # Module base
    modules.dart                # Modules aggregator
    system.dart                 # System: native UI outside the app
    app_module.dart             # launch()
    foo_editor_module.dart      # FooEditorModule, one per user-facing feature
  foo_editor_rejects_empty_title_test.dart   # one testApp per file
```

Real UI, blocs, use cases, and repositories run; only I/O is replaced. `lib/` never imports `patrol_test/`, and Patrol never imports another package's `test/` helpers.

## Harness (`test_app.dart`)

```dart
typedef MockDependencies = ({
  MockBackendApiClient apiClient,
  DatabaseClient database,
  FirebaseAuth firebaseAuth,
  FakeFooService fooService, // a platform service a test drives (optional)
});

var _fallbacksReady = false;

void testApp(
  String description,
  Future<MockDependencies> Function() mockDependencies,
  Future<void> Function(PatrolIntegrationTester $, Modules modules, System system) body,
) => patrolTest(
  description,
  config: const PatrolTesterConfig(settlePolicy: SettlePolicy.noSettle, printLogs: true),
  ($) async {
    final getIt = GetIt.instance;
    await getIt.reset();
    _registerFallbacks();
    MockDependencies? dependencies;
    try {
      await initializeLogger();
      dependencies = await mockDependencies();
      await dependencies.database.initialize(); // the one warm-up; seeding already awaited it lazily
      await injectDataLayer(getIt, config: AppConfig.fromEnvironment(), skipSdkInit: true);
      await replaceSingleton<DatabaseClient>(getIt, dependencies.database);
      await replaceSingleton<BackendApiClient>(getIt, dependencies.apiClient);
      await replaceSingleton<FirebaseAuth>(getIt, dependencies.firebaseAuth);
      await replaceSingleton<FooService>(getIt, dependencies.fooService);
      await replaceSingleton<PushNotificationsService>(getIt, InMemoryPushNotificationsService());
      injectDomainLayer(getIt);
      injectUiLayer(getIt);
      await body($, Modules($), System($.platform));
    } finally {
      await dependencies?.database.dispose(deleteFromDisk: true);
    }
  },
);

void _registerFallbacks() {
  if (_fallbacksReady) return;
  registerFallbackValue('');
  registerFallbackValue(0);
  registerFallbackValue(mockFooDto()); // every DTO type used with any()
  _fallbacksReady = true;
}

Future<void> replaceSingleton<T extends Object>(GetIt getIt, T instance) async {
  if (getIt.isRegistered<T>()) await getIt.unregister<T>();
  getIt.registerSingleton<T>(instance);
}
```

- Order: reset the service locator → logger → build the test's doubles (the file seeds its database here) → real data-layer DI with `skipSdkInit: true` (no Firebase or other SDK setup; the harness registers the SDK doubles) → replace I/O → domain and UI DI → startup steps `main()` runs before `runApp` (restoring a session, for example) → body → dispose and delete the test database.
- `injectDataLayer`, `replaceSingleton`, `skipSdkInit` (present once the data layer sets up an SDK), and `AppConfig` follow the `di` rule; a project with other flag names keeps them (repository rules).
- Imports: the app through its package barrels (`package:data/data.dart`, `package:ui/ui.dart`, `package:ui/keys.dart`), data internals the harness replaces or seeds (`BackendApiClient`, `DatabaseClient`, `IsarDatabase`, `DbRecord`, DTOs, service contracts and in-memory implementations) through `package:data/testing.dart` — never `package:data/src/`. The layer check rejects `testing.dart` in any `lib/`.
- **Replace only I/O:** API clients (one per remote source), the database client, the auth SDK, platform services (location, camera, playback, push, purchases, ads, review prompt, share, store-version lookup), the clock and monotonic time, connectivity, the device key and signing, analytics, every paid provider, and UI-level launchers of other apps (maps, browser).
- **Reset leftovers** from an earlier test before building the doubles: the service locator, shared preferences (`SharedPreferences.setMockInitialValues({})` does not reach a real device; call `clear()`), and secure storage (`FlutterSecureStorage().deleteAll()`), so tokens and queued items never leak between files.
- **Payloads come from the generated API models** built in the test file (or the file's DTO builders), never by reading the data package's test fixtures.
- Time: a steppable clock fake in the record when the flow depends on time (a deadline, a stale warning, a retry backoff); the test steps it instead of waiting.
- **The record** holds the doubles a test configures or drives. Doubles no test controls are replaced in the harness: the app's own in-memory implementation if it already ships one (for web or non-prod), otherwise a private class in the harness.
- The database is awaited once, in the harness; the file's seeding calls (`saveFoo`) open it lazily (`persisting-with-isar` → Database lifecycle).
- Mocktail fallbacks for `any()` argument types: once, in the harness. Some repositories register them in each test file instead — follow the repository rules.
- `settlePolicy: noSettle`: streams, timers, and animations keep the app from settling, so tests wait for visible results, never for idle.
- Pin the locale (`$.tester.platformDispatcher.localeTestValue`) and clear persisted preferences in the harness when tests assert text or the app restores state from them (common on web).
- No scenario flags on `testApp`. Scenarios live in each file's mock-dependencies function.

## Doubles (`mocks/`)

```dart
final class MockBackendApiClient extends Mock implements BackendApiClient {}

DatabaseClient mockDatabase() => IsarDatabase(
  customDatabaseName: 'e2e_test_${DateTime.now().microsecondsSinceEpoch}',
);
```

- One mocktail double per remote source (the backend, each store or third-party API the app calls).
- The database is the real `IsarDatabase` under a unique name per test; on web the same constructor builds the in-memory variant (the testing barrel exports `IsarDatabase` by conditional export). The harness deletes it from disk.
- Auth: the SDK's mock package (`MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _userId))` from `firebase_auth_mocks`); subclass it to override a method the app calls that the mock lacks.
- **Fakes** for platform services implement the app's contract (`FakeFooService implements FooService`): constructor parameters set the starting state (a position, a permission answer), control methods drive it (`moveTo(...)`, `emitFoo(...)`, `failNextCall = true`), read-only getters expose what to assert (`currentFooId`, `callsFor(fooId)`). Streams come from a broadcast controller and emit the current value to each new listener.
- A launcher that opens another app becomes a fake that pushes a keyed placeholder page (`Scaffold(key: keys.foo.externalAppPage)`), so the test asserts the hand-off.

## Test file

```dart
void main() {
  testApp('rejects an empty foo title', _mockDependencies, ($, modules, system) async {
    await modules.app.launch();
    await modules.fooList.tapFoo(fooId: _fooId);
    await modules.fooEditor.enterTitle('');
    await modules.fooEditor.tapSave();
    await modules.fooEditor.waitUntilTitleError();
  });
}

const _userId = 'foo-empty-title-user';
const _fooId = 'foo-empty-title-foo';

Future<MockDependencies> _mockDependencies() async {
  final apiClient = MockBackendApiClient();
  when(apiClient.getMyUser).thenAnswer((_) async => _user());
  when(
    () => apiClient.listFoos(cursor: any(named: 'cursor'), limit: any(named: 'limit')),
  ).thenAnswer((_) async => FooPageDto(items: [_foo()], nextCursor: null));
  final database = mockDatabase();
  await database.saveFoo(DbRecord(dto: _foo(), dbTimestamp: DateTime(2020))); // only for offline flows
  return (
    apiClient: apiClient,
    database: database,
    firebaseAuth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: _userId)),
    fooService: FakeFooService(),
  );
}

UserDto _user() => mockUserDto(id: _userId);
FooDto _foo() => mockFooDto(id: _fooId, title: 'First foo');
```

- **One `testApp` per file.** File name = the observable result (`foo_editor_rejects_empty_title_test.dart`, `guest_sees_sign_in_test.dart`); the description says the same in words.
- **The file owns its I/O** in the private `_mockDependencies()`: private `const _fooId` IDs prefixed with the scenario, used in the stubs, the database seed, and the module calls; `when(...)` stubs for every API method the flow reaches; the database seed limited to what the app cannot fetch (cached data for offline flows, local-only state).
- Shared builders and presets (`signedIn(userId: _userId, foos: [...], configure: (apiClient) {...})` in `fixtures.dart`, or a family helper beside the tests) only where the repository already has them; reuse them before writing new ones. Test-specific IDs and stubs stay in the file.
- Errors: `thenAnswer((_) => Future.error(...))` with the API client's exception type (never `thenThrow` for async methods) (the repository maps it to a domain exception, as in production). Offline: every reached method throws the network-unavailable exception and the database holds the cached data. Retry: count calls in the stub (`calls++; if (calls == 1) throw ...;`).
- A body that drives a fake keeps it in a file-private `late FakeFooService _fooService;` assigned in `_mockDependencies()`, with a small private helper (`_emitFoo(...)`).
- **The body** calls modules, drives fakes, and checks fake or call state with `expect` (`expect(_fooService.currentFooId, _fooId)`, `expect(calls, 2)`). It never touches the service locator, stubs, or raw `$()` finders.

## Modules

```dart
abstract class Module {
  Module(this.$);
  final PatrolIntegrationTester $;
}

final class Modules {
  Modules(this._$);
  final PatrolIntegrationTester _$;

  late final app = AppModule(_$);
  late final fooEditor = FooEditorModule(_$);
  late final fooList = FooListModule(_$);
}

final class AppModule extends Module {
  AppModule(super.$);

  Future<void> launch() => $.pumpWidget(const Application());
}

final class FooEditorModule extends Module {
  FooEditorModule(super.$);

  Future<void> enterTitle(String title) => $(keys.fooEditor.titleField).enterText(title);

  void expectNoTitleError() => expect($(keys.fooEditor.titleError), findsNothing);

  Future<void> tapSave() => $(keys.fooEditor.saveButton).scrollTo().tap();

  Future<void> waitUntilTitle(String title) async {
    final finder = $(keys.fooEditor.title);
    await finder.waitUntilVisible();
    expect(finder.text, title);
  }

  Future<void> waitUntilTitleError() => $(keys.fooEditor.titleError).waitUntilVisible();

  Future<void> waitUntilVisible() => $(keys.fooEditor.page).waitUntilVisible();
}
```

- `FooModule` in `foo_module.dart`, one per user-facing feature or screen, registered alphabetically in `Modules`. Match the repository's constructor style.
- Method names say the action or the expectation: `tapFoo`, `enterFoo`, `selectFoo`, `waitUntilFoo` (waits and asserts), `expectNoFoo` (absence; call it after a positive wait so it is not trivially true), `waitUntilFooGone` (a bounded `$.pump` poll until the finder no longer exists).
- Parameters are ids or enum values that feed parameterized keys: `tapFoo({required String fooId})`.
- Short one-step methods; a flow reused by many tests gets a public wrapper over private steps. Descriptive names instead of comments.
- Adjust an existing method only if every current caller still holds; otherwise add one.

## System

Native UI the app does not own: permission dialogs, the Android back button, notifications, airplane mode.

```dart
final class System {
  System(this._platform);
  final PlatformAutomator _platform;

  Future<void> grantLocationWhenInUse() => _platform.mobile.grantPermissionWhenInUse();

  Future<void> pressBack() => _platform.android.pressBack();
}
```

- Wrap `$.platform` (the harness passes it). A `System` that extends `PlatformAutomator` and is built without a config gets no-op automators, so its native calls do nothing. On web `System` usually stays empty.
- Prefer keeping native dialogs out of the flow: a fake service returns the permission state, or the Android runner pre-grants the permission (`setting-up-patrol`). Use `System` when the native step is the behavior under test.
- Handle a native dialog right after the action that triggers it; prefer the permission helpers over tapping native text. Find native selectors with `native-tree` (MCP).

## Widget keys

```dart
// UI package: lib/src/foo_editor/keys.dart
final class FooEditorKeys {
  final page = const AppKey('fooEditor', 'page');
  AppKey row(String fooId) => AppKey('fooEditor', 'row_$fooId');
  final saveButton = const AppKey('fooEditor', 'saveButton');
  final title = const AppKey('fooEditor', 'title');
  final titleError = const AppKey('fooEditor', 'titleError');
  final titleField = const AppKey('fooEditor', 'titleField');
}

// UI package: lib/keys.dart, imported by the app and patrol_test as package:ui/keys.dart
final keys = Keys();

/// Public: a private key type in a public getter fails the analyzer
/// (library_private_types_in_public_api).
final class AppKey extends ValueKey<String> {
  const AppKey(String screen, String value) : super('${screen}_$value');
}

final class Keys {
  final fooEditor = FooEditorKeys();
  final widgets = WidgetKeys();
}
```

- One `keys.dart` per feature folder in the UI package, aggregated in `Keys`; common widgets in `WidgetKeys` next to them. Class per screen whose keys are `AppKey(screen, value)` (one public `ValueKey<String>` subclass in `lib/keys.dart` that prefixes values); keys sorted alphabetically; values unique.
- In the app: `key: keys.fooEditor.saveButton`, as the first constructor argument. Never a hardcoded key value.
- Key only widgets a test touches; never a key nothing uses. Only add a `key:` argument — never change widget signatures, restructure the tree, or add widgets for tests.
- Widgets built from data take a parameterized key from an existing id, enum, or DTO property (`row(String fooId)`); compile-time widgets get fixed keys. Never mix the two for one widget.
- Finders use keys. A text finder is a last resort for a widget from a package that takes no key, and lives in a module.
- The repository's existing key layout wins if it differs.

## Patrol API rules

- `tap`, `enterText`, and `scrollTo` wait for their widget; no `$.pump` or `waitUntilVisible` between steps. Wait only for a result: the destination before asserting, the end state at the end.
- `scrollTo()` before tapping anything that can be off screen; `scrollTo(view: $(keys.foo.scroll))` when the screen has several scrollables.
- Assertions at the end and at the checkpoints a fake-driven flow needs; prefer `waitUntilVisible` (through `waitUntilFoo`), `expect` for text, values, absence, and fake state.
- No try/catch, no fixed delays, no `patrolSetUp` / `patrolTearDown` (the harness owns setup and teardown).
- Look up an API in neighboring modules and the Patrol docs before inventing one; `$.platform` covers native actions.

## Procedure

1. Read the harness, `mocks/`, fixtures (if any), `Modules`, the feature's modules and keys, the screen and bloc under test, and one or two neighboring tests of the feature (copy their stubs).
   - **Fix a broken `System` first.** If the harness builds `System()` with no argument, or `System` extends `PlatformAutomator` without a config, its native calls are silent no-ops. In the same change, as its own commit: make `System` wrap `$.platform` (System below) and pass `System($.platform)` from the harness; run one existing test to confirm nothing else changed. Tell the user it was fixed.
   - **Legacy test bodies** with raw `$()` or text finders: leave untouched files alone; a file you edit moves its UI steps into module methods (step 6).
2. Derive the transitions from the screen and bloc (stack `testing` rule → Rules); one file each.
3. Add the keys the flow needs.
4. Write `_mockDependencies()`.
5. Draft the steps (inline `$()` is fine while drafting) and run the file after each logical group of steps.
6. Once green, move every UI step into module methods so the body only calls modules and fakes. Re-run, and re-run the tests that use a module method you changed.

## Running

- **One file:** the `patrol` MCP when the repository configures it — `run` with `testFile: patrol_test/foo_test.dart` (a second `run` restarts the session), then `status`, `screenshot`, `native-tree`, `quit`. Otherwise the CLI: `patrol test --target patrol_test/foo_test.dart`, plus `--flavor dev` on mobile (unless the `patrol:` block sets it) or `--device chrome` on web, from the folder whose `pubspec.yaml` has the `patrol:` block.
- **Whole suite:** `patrol test` with the same flags, or the project task (a Gradle `integrationTestDev`); slow, so once at the end. The exact commands: `CLAUDE.md` → Verification.
- A booted emulator or simulator (or Chrome) is required; on Android, prefer an API 34 image: we observed Patrol discovering 0 tests on API 35 images (an observation to recheck with each Patrol release, not a documented limit). `scripts/test.sh e2e` runs on the booted device; it does not start one. Never `flutter test` for Patrol files.
- The changed feature's files run before each PR; the whole suite before a feature branch merges and before a release (`writing-patrol-tests` → Policy).

## Debugging

Reproduce first and fix one failure at a time (`systematic-debugging`).

| Symptom | Usual cause |
| --- | --- |
| `type 'Null' is not a subtype of type 'Future<…>'` | An API method the flow reaches has no `when(...)` stub |
| `Bad state: … registerFallbackValue` | A new argument type is used with `any()` |
| `WaitUntilVisibleTimeoutException` | Key not on the widget built in that state, widget off screen (`scrollTo`), wrong scrollable (`scrollTo(view:)`), a throwing stub keeps the screen loading, a native dialog on top (`screenshot`, `native-tree`) |
| Passes alone, fails in the suite | State leaks between tests: DB name, preferences, statics, a fake shared across files |
| Flaky timing | A fixed delay or a wait for settling; wait for a visible result and drive time-dependent fakes explicitly |
| A `System` call does nothing | `System` built without `$.platform` (System above) |
| Android finds 0 tests | Seen on API 35 images (observed, recheck per Patrol release): try an API 34 image; then check the native setup (`setting-up-patrol`) |
| Build or install fails | Flavor or package mismatch between the `patrol:` block, Gradle, and Xcode (`setting-up-patrol`) |

A real app bug found by a test: report it with the failing test; fix only when it is in scope.
