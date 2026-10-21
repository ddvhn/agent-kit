---
name: scaffolding-flutter-app
description: Create a new, empty Flutter app the kit way — pub workspace with domain / data / ui / utils / logger / localization packages (optional analytics), per-package pubspecs and allowed dependencies, a layer-check script that fails on forbidden imports, shared strict analysis_options, the logger, the CallableUseCase base and AppException hierarchy, DI per layer, one example feature wired through every layer (repository, use case, load bloc, home screen with a skeleton and its widget test), the per-platform theme factory, an adaptive widget and the adaptive page helper, localization, utils (rate limiter, serial queue, memory cache), lib/main.dart bootstrap with error handlers, the one app config, launch configs, scripts/test.sh with the coverage gate, setup.sh and git hooks, the Flutter version pin, then the hand-offs (agent setup, flavors, web entry, backend, cache, auth, Patrol, mock backend). Use when starting a new app; an existing app moves to this layout with refactoring-to-kit-architecture.
---

# Scaffolding a Flutter app

Policy: core `architecture-principles` and `same-level-dependencies`; the stack `architecture`, `di`, `data`, `dart`, and `testing` rules. This skill lays an **empty project**: the layers, their wiring, and the cross-cutting pieces every app needs (logger, errors, theme, localization, DI, the layer check). No backend, database, auth, or SDK — each arrives with its own skill when the app needs it (hand-offs at the end).

Every file below is in `templates/` next to this skill, laid out as in the new repository. Copy it, rename `foo_app` / `Foo`, and set dependency versions to the current stable ones (`flutter pub add`, `flutter pub outdated`) — the template versions are examples. The copied templates analyze clean, pass the layer check, and their tests pass as they are, after `flutter pub get`, `flutter gen-l10n` in `modules/localization`, and `dart run build_runner build` in `modules/ui` (typed routes).

**Ask first** (one batch, recommended defaults in brackets): app and package name, org / bundle ids, platforms [iOS, Android], a web app from the same project [no], environments [`dev`, `staging`, `prod`], separate analytics package [no], coverage gate [100% of handwritten code]. Backend, local cache, auth, and Patrol are decided when the first feature needs them, not here.

## Layout

```
foo_app/
  pubspec.yaml                      # app + workspace root (composition root)
  analysis_options.yaml             # shared strict lints
  lib/main.dart                     # bootstrap; the only file that imports every layer
  lib/main_web.dart                 # optional web entry, same layers (architecture rule → Platforms and assembly)
  tool/check_layers.dart            # fails on forbidden imports
  tool/check_coverage.dart          # the coverage gate over coverage-exclusions.txt
  scripts/test.sh                   # unit | e2e | live
  scripts/setup.sh, scripts/hooks/  # Flutter version check, pre-commit and pre-push hooks
  coverage-exclusions.txt           # the closed exclusion list
  .flutter-version                  # the pinned Flutter version
  .vscode/launch.json
  modules/
    domain/        # pure Dart: models, repository contracts, use cases, domain exceptions
    data/          # repository implementations; later API clients, database, SDK services, DTOs
    ui/            # blocs, UI models, pages, widgets, router, theme
    utils/         # pure Dart helpers shared by every layer
    logger/        # package `log`: the app logger
    localization/  # gen-l10n output and the context accessor
    analytics/     # optional, see below
```

Each layer is a package under `modules/`, not a `lib/` folder, so its pubspec states what it may depend on, and the layer check enforces imports on top.

## What the templates contain

| Package | Files (under `lib/`) |
| --- | --- |
| app | `main.dart`, `bootstrap.dart`, optional `main_web.dart` and `config/web/{dev,staging,prod}.json` (bootstrap below) |
| `domain` | barrels; `src/common/` (`callable_use_case.dart`, `app_exception.dart`); `src/foo/` (`Foo`, `FooRepository`, `FetchFooUseCase`); `src/di.dart` |
| `data` | `data.dart` (composition-root barrel), `testing.dart` (test-only barrel); `src/config/app_config.dart`; `src/core/disposable.dart`; `src/repository/foo_repository_impl.dart` (empty: returns a placeholder until the first data source); `src/di.dart` |
| `ui` | `ui.dart`, `keys.dart`; `src/application/` (`application.dart`, `router/router.dart`, `router/helpers/adaptive_page.dart`); `src/common/theme/` (`theme.dart` with `makeTheme(platform:, brightness:)`, `theme_colors.dart`, `app_theme_x.dart`, `ui_platform.dart`, `app_scroll_behavior.dart`); `src/common/widgets/` (`error_view.dart`, `adaptive/adaptive_spinner.dart`); `src/common/extensions/app_exception_x.dart`; `src/foo/` (`LoadFooBloc`, `FooUiModel`); `src/home/pages/home_page.dart` (the one screen); `src/di.dart` |
| `localization` | `l10n.yaml`, `l10n/app_en.arb` (seed keys), `localization.dart` (`context.strings`) |
| `log`, `utils` | the logger (below); `utils.dart` re-exporting `log`, `RateLimiter`, `SerialQueue`, `MemoryCache` (TTL + LRU), each with its tests |
| tests | `test/flutter_test_config.dart` in `data` and `ui` (logger, network blocked with `HttpOverrides`); seed tests that show the conventions: `domain` (`FetchFooUseCase`), `ui` (`HomePage` widget test with the real `LoadFooBloc` over a mocked use case — skeleton, loaded, retry double tap, failed refresh, tap targets, 2× text at 360 wide — through `test/helpers/pump_screen.dart`; `AppExceptionX` copy and `isRetryable`), `utils` |
| analysis options | `analysis_options.yaml` in every package (`include: ../../analysis_options.yaml`; the logger also allows `print`) |
| root | `pubspec.yaml`, `analysis_options.yaml`, `tool/check_layers.dart`, `tool/check_coverage.dart`, `scripts/` (`test.sh`, `setup.sh`, `hooks/pre-commit`, `hooks/pre-push`), `coverage-exclusions.txt`, `.flutter-version`, `.vscode/launch.json`, `.gitignore` lines |

The `Foo` feature is the wiring example — `FooRepository` → `FetchFooUseCase` → `LoadFooBloc` → `HomePage`, each registered in its layer's DI. The first real feature renames or replaces it.

## Packages and allowed dependencies

| Package | Depends on | Never |
| --- | --- | --- |
| `domain` | `utils`, `log`, `equatable`, `meta`, `collection`, `rxdart`, `get_it` (its `di.dart` only) | Flutter, `dart:ui` / `dart:io`, SDKs, JSON |
| `data` | `domain`, `utils`, `log`, SDKs, transport, database, `json_annotation` | `ui`, `localization`, blocs, `go_router`, `domain_usecase.dart` |
| `ui` | `domain`, `utils`, `log`, `localization`, `flutter_bloc`, `bloc_presentation`, `go_router`, `skeletonizer`, `universal_platform`, presentation-only plugins | `data`, storage / network / auth SDKs |
| `utils` | `log` (may re-export it), `collection`, `meta` | Flutter, any layer |
| `log` (folder `modules/logger`) | `stack_trace` (pure Dart) | Flutter, `path_provider`, any layer |
| `localization` | Flutter, `flutter_localizations`, `intl` | any layer |
| app (`lib/`) | everything | — |

- The pubspecs declare only what the templates use; add a dependency in the change that first imports it (and, for a pure package, to the layer check's allowlist).
- Every layer may log, domain included: `log` is pure Dart, so domain stays pure and testable with `dart test`. Failures are still thrown as typed exceptions and logged once by whoever handles them (`handling-errors`).
- The logger package is named `log` because `logger` collides with the pub.dev package as soon as a dependency pulls it in.
- **Optional `analytics`**: a pure-Dart event catalog (`sealed class AnalyticsEvent`) when several apps share it or it is large. Sending events is a data service behind a domain repository contract, like any SDK; never a global client called from domain or widgets.
- Templates: `pubspec.yaml` (root, `workspace:`), `modules/*/pubspec.yaml` (`resolution: workspace`).

## Layer check

`tool/check_layers.dart` scans each configured package's `lib/` for `import` / `export` directives, conditional alternatives included: domain, utils, and the logger against an allowlist (`log` allowed everywhere; only platform-free `dart:` libraries in pure packages), localization against its allowlist, data and ui against a denylist (ui by prefix: `package:firebase_`, `package:cloud_`, `package:isar`, …), the app (`'.'`, its package name in the table) for barrels only, any `package:other/src/` import, and `package:data/testing.dart` from any `lib/`. Keys are folders relative to the root (`'modules/domain'`, or `'modules/common/domain'` for a shared module); a configured folder without `lib/` fails the check. `dart run tool/check_layers.dart` from the root; it goes into `CLAUDE.md` → Verification and CI next to `flutter analyze`.

An existing app with known violations (`refactoring-to-kit-architecture`): `dart run tool/check_layers.dart --write-baseline` records them in `tool/layer_baseline.txt` (committed); later runs fail only on violations not in the baseline and list baseline lines that were fixed, to delete. The baseline only shrinks; a new app has none.

## Test-only barrel (`data/lib/testing.dart`)

Harnesses need data internals the composition-root barrel hides: store contracts to replace, the database for per-test instances, DTOs to seed, service contracts and in-memory implementations. `testing.dart` exports them as they appear (the empty project exports only `Disposable`); only `test/`, `patrol_test/`, and `integration_test/` import it, and the layer check fails on any `lib/` that does. Never import `package:data/src/` from tests in other packages.

## Domain base

- `src/common/usecase/callable_use_case.dart` — the four mixins (`CallableUseCase`, `CallableUseCaseSync`, `CallableUseCaseWithoutParams`, `CallableUseCaseWithoutParamsSync`). Use-case shape: `modeling-domain`.
- `src/common/exception/app_exception.dart` — `sealed class AppException` with `NetworkUnavailableException`, `NotFoundException`, `UnauthorizedException`, `PermissionDeniedException`, `QuotaExceededException`, `ValidationException`, `UnknownException`, and the `FeatureException` base for a feature's own sealed hierarchy; `AppException.from(error)` for catchers. Flow: `handling-errors`.
- Barrels: `domain_model.dart` (models, exceptions, calculators), `domain_repository.dart` (contracts), `domain_usecase.dart` (use-case contracts with `hide FooUseCaseImpl`, plus `injectDomainLayer`). data imports the first two; ui all three.

## Logger (`modules/logger`)

Pure Dart, so any layer can import it. `lib/log.dart` exports `log`, `initializeLogger({String? logsDirectoryPath})`, `isLoggerInitialized`, `loggedSecret`, `redactedLogValue`, `snapshotLogFilesForShare`.

- Console output (`print`, allowed only in this package's `analysis_options.yaml`) outside release builds, detected with `const bool.fromEnvironment('dart.vm.product')` instead of Flutter's `kReleaseMode`.
- A rotating file sink (1 MB, two rotated files) in the directory `main` passes — `main` owns `path_provider`; no directory (tests, web) means console only. The sink is picked by conditional import (`dart:io` vs a web stub). `snapshotLogFilesForShare()` copies the files for a "report an issue" share. Logging never throws, even when the file cannot be written.
- Caller location per line; `initializeLogger()` is idempotent; `main` and every test setup whose code logs call it first. Not registered in GetIt. What to log: `handling-errors`.

## Bootstrap (`lib/main.dart`, `lib/bootstrap.dart`)

Each entry (`main.dart` for mobile, `main_web.dart` for a web app) sets up its binding and calls the shared `bootstrap(app:, logsDirectoryPath:)`. Order, each step depending on the ones before:

1. Binding: `MarionetteBinding` in debug (live checks, `driving-flutter-app`), else `WidgetsFlutterBinding`.
2. `await initializeLogger(logsDirectoryPath: …)` with `<application support>/logs` from `path_provider` on mobile, none on web — everything after it may log.
3. `AppConfig.fromEnvironment()` — the environment (native flavor on mobile, the config file on web) and dart-defines, read once (`modules/data/lib/src/config/app_config.dart`; switches join with their features: `configuring-flutter-flavors`).
4. Error handlers: `FlutterError.onError` and `PlatformDispatcher.instance.onError` log through `log.e` with the stack trace. A crash reporter forwards from here (`configuring-flutter-flavors` → Firebase and crash reporting).
5. `await injectDataLayer(getIt, config: config)`, `injectDomainLayer(getIt)`, `injectUiLayer(getIt)`.
6. `runApp(const Application())`.

Steps that features add, in place: SDK initialization (Firebase) after the config; service warm-ups (`initialize()` of the database) after DI — await only what the first frame needs, start the rest with `unawaited`, each logged and never fatal. No business logic in `main`: a startup step that restores a session is a use case it calls after DI.


## DI lifetimes

| What | Registration |
| --- | --- |
| API and database clients, repositories, app-wide controllers | `getIt.registerLazySingleton<FooRepository>(() => FooRepositoryImpl(getIt(), getIt()))` — keyed by the contract, implementation hidden |
| Values created during startup (preferences, config, package info) | `getIt.registerSingleton(value)` |
| Data-internal services (SDK wrappers) | `getIt.registerLazySingleton<FooService>(() => config.useProdServices ? FcmFooService() : InMemoryFooService())` — resolved only by repositories |
| Use cases | `getIt.registerFactory<FooUseCase>(() => FooUseCaseImpl(getIt(), getIt()))` in `injectDomainLayer` |
| Blocs, app-wide ones included | `getIt.registerFactory(() => FooBloc(getIt(), getIt()))` — a new instance per `BlocProvider`; app-wide blocs are created once by `Application` (`blocs` rule); never a singleton bloc |

- No `registerFactoryParam` for ids or entities: blocs get them through `configure` (`blocs` rule). Existing factory-param registrations migrate when touched.
- A singleton that owns streams, subscriptions, or native resources registers a `dispose:` callback: a contract with `dispose()` calls it; a repository implements the data-internal `Disposable` and registers `dispose: disposeIfDisposable` (a capability check, no cast).
- The logger is not registered: it is the global `log`.

## Application widget (`modules/ui/lib/src/application/application.dart`)

- `MaterialApp.router` on every platform, never `CupertinoApp`: `theme` / `darkTheme` from `makeTheme(platform:, brightness:)` and `scrollBehavior: AppScrollBehavior(platform)` (`theming-flutter-apps`, `building-adaptive-widgets`), `localizationsDelegates` / `supportedLocales` from gen-l10n, `onGenerateTitle` from copy. The `UiPlatform` comes from the container (`injectUiLayer` detects it once).
- The router is resolved once into the state (`inject<GoRouter>()`), never built in `build`. Routes: `adding-flutter-routes`.
- App-wide blocs (a session for the router redirect — `adding-flutter-auth`; an in-app locale) are `registerFactory` blocs created **once** in a `MultiBlocProvider` above `MaterialApp.router`, so routes and the redirect read the same instances. No singleton blocs.
- UI DI: `modules/ui/lib/src/di.dart` with `inject<T>()` and `injectUiLayer` (router lazy singleton with `dispose:`, bloc factories).

## Feature folders

One folder per feature (a bounded context, `modeling-domain`) in each layer, same name everywhere:

```
modules/domain/lib/src/foo/
  model/          foo.dart, foo_draft.dart, foo_exception.dart
  repository/     foo_repository.dart              # abstract interface class
  usecase/        fetch_foo_use_case.dart          # FetchFooUseCase + FetchFooUseCaseImpl
  calculator/     foo_schedule_calculator.dart     # pure rules, when shared
modules/data/lib/src/
  data_store/...                                    # stack `data` rule layout
  repository/foo_repository_impl.dart
modules/ui/lib/src/foo/
  blocs/          load_foo_bloc.dart, create_foo_bloc.dart
  models/         foo_ui_model.dart
  pages/          foo_page.dart
  widgets/        foo_tile.dart
```

Shared UI: `ui/lib/src/common/{widgets,widgets/adaptive,theme,extensions,formatters}`; app shell: `ui/lib/src/application/{application.dart,router}`; widget keys for tests: `ui/lib/keys.dart` (`writing-patrol-tests`).

## Launch configs

`.vscode/launch.json`: `dev-debug` (the default; VM-service auth codes on), `dev-agent` (fixed VM-service port and `--disable-service-auth-codes`, so the Dart and Marionette MCP servers attach — `driving-flutter-app`; debug, non-prod, trusted machine only), `dev-local` (`--dart-define-from-file=.dart_defines.local.json` for a local backend), `mock` (`test/main_mock.dart`, added by `mocking-backend-for-tests`), `web-dev` (`lib/main_web.dart` on Chrome with `config/web/dev.json`; delete it when the app has no web entry — `configuring-flutter-flavors` → Web environments), `release-staging`. None runs against the production backend. The mobile configs pass `--flavor`, so they start once the flavors exist (Procedure step 4).

## Local checks

- `scripts/test.sh unit`: `dart format` check, `flutter analyze`, the layer check, generated code up to date (gen-l10n and build_runner leave no diff), every package's tests with coverage (`dart run coverage:test_with_coverage` in pure Dart packages, `flutter test --coverage` in Flutter ones), then `tool/check_coverage.dart` (100% of lines outside `coverage-exclusions.txt`; `--min=` for a project that chose a lower gate). `e2e` runs Patrol; `live` the manual live smoke.
- `scripts/setup.sh` once per clone: fails when the installed Flutter differs from `.flutter-version`, requires `gitleaks`, sets `core.hooksPath scripts/hooks`. pre-commit: format, analyze, `gitleaks` on staged files; pre-push: `scripts/test.sh unit`. Never `--no-verify`.
- These commands go into `CLAUDE.md` → Verification and the README.

## Procedure

1. `flutter create --org com.example --project-name foo_app --platforms ios,android foo_app`; delete `test/widget_test.dart`.
2. Create the packages, one command each (neither tool takes several directories): `flutter create --template=package modules/data`, the same for `modules/ui` and `modules/localization`; `dart create --template=package modules/domain`, the same for `modules/utils` and `modules/logger` (pure Dart; then set `name: log` in the logger's pubspec). Remove the generated sample code, tests, and `analysis_options.yaml` files (the templates replace them).
3. Copy the templates (table above) — the web files only when the app has a web entry (asked above): `lib/main_web.dart`, `config/web/`, the `flutter_web_plugins` dependency in the root `pubspec.yaml`, and the `web-dev` launch config; a mobile-only app leaves them out and copies them from these templates when it gains a web entry (`configuring-flutter-flavors` → Web environments). Then set the app's package name in `tool/check_layers.dart`, the installed stable Flutter version in `.flutter-version`, append the `.gitignore` lines; `scripts/setup.sh`, `flutter gen-l10n` in `modules/localization`, `dart run build_runner build` in `modules/ui`. Verify (below) passes here.
4. Make it the team's app: `configuring-flutter-flavors` (native flavors, app names, icons), the palette and component themes (`theming-flutter-apps`), copy (`localizing-flutter-apps`), then `adopting-agent-kit` (CLAUDE.md Project facts — packages, entry point, flavors, launch configs, and the levels the rules read: "Web: yes / no", "Offline writes: online / queued (ADR)", "Sync: refresh / delta", "Device signatures: none / verified by the backend", "Analytics: none / own backend"; defaults are the first value — Verification commands including the layer check, `.claude/settings.json`, repository rules). Record the stack choices as the first ADR (`recording-decisions`).
5. First feature, test first, renaming or replacing `Foo` (`adding-flutter-features`). Hand-offs as the feature needs them: a backend (`generating-api-clients` for an OpenAPI contract, `calling-cloud-functions` for Firebase callables, with an app per flavor from `configuring-flutter-flavors`), a local cache (`persisting-with-isar`), offline actions and sync (`queueing-offline-actions`, `syncing-server-changes`), sign-in (`adding-flutter-auth`), routes (`adding-flutter-routes`), adaptive widgets (`building-adaptive-widgets`), analytics (`tracking-analytics-events`), native code (`bridging-native-code`), then `setting-up-patrol` with its first flow, the mock backend (`mocking-backend-for-tests`), and store releases (`releasing-flutter-apps`).
6. Backend: by default a **separate repository** scaffolded with `firebase-functions:scaffolding-functions-backend` (or `go:scaffolding-go-backend`) in its own session (its plugins and rules load only there; `--add-dir` does not load them), with the callable names, region, paged contract, error codes, and emulator ports agreed with the app; each repository's `CLAUDE.md` → Related repositories points at the other. One repository with `functions/` beside the app and both plugins enabled (`flutter@agent-kit`, `firebase-functions@agent-kit`) is allowed when the team wants it; record the choice in the ADR.

## Verify

- `flutter pub get` at the root resolves one workspace; `flutter analyze` is clean.
- `dart run tool/check_layers.dart` passes, and fails when you add `import 'package:data/data.dart';` to a ui file or `import 'package:data/testing.dart';` to any `lib/` file (then remove it).
- `scripts/test.sh unit` passes: every package has tests (the templates ship them, logger and localization included), coverage at the gate. The gate fails on a package without `test/`, a missing `lcov.info`, or a `lib/` file no test loads.
- `flutter run` starts (with `--flavor dev` once the flavors exist): the home screen shows a skeleton, then the placeholder `Foo`, and the log shows the environment line. On iOS a pushed route swipes back; on web there is no transition.

## Checks

- [ ] Workspace root lists every package; each package has `resolution: workspace` and includes the root analysis options
- [ ] `domain` and `utils` are pure Dart; `ui` does not depend on `data`; the layer check runs in Verification and CI
- [ ] `main` order: binding → logger → config → error handlers → DI → `runApp`; both handlers log with the stack trace
- [ ] Config read once in `main`, passed to `injectDataLayer`; no `fromEnvironment` or `appFlavor` elsewhere; platform checks only in `main` and the inject functions
- [ ] `scripts/test.sh unit` passes; hooks installed by `scripts/setup.sh`; `.flutter-version` matches the installed Flutter
- [ ] DI order data → domain → ui; the example feature resolves through all three
- [ ] Router resolved once; app-wide blocs, when they appear, created once in `Application`
- [ ] No SDK, backend, database, or auth code yet; `testing.dart` imported only from test folders
- [ ] Hand-offs planned: `adopting-agent-kit`, `configuring-flutter-flavors`, and the feature skills above as the first feature needs them
