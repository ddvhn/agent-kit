---
description: Flutter dependency injection with get_it and build configuration — one inject function per layer, constructor injection, lifetimes, the inject<T>() UI helper, implementations chosen at registration, test swaps, environments, flavors, and dart-defines
paths:
  - "**/*.dart"
---

# Dependency injection (get_it)

`get_it` is used only for wiring; no other DI package unless the project has one. Startup order and the lifetimes table: `scaffolding-flutter-app` → Bootstrap, DI lifetimes.

## Wiring

- One `di.dart` per layer: `Future<void> injectDataLayer(GetIt getIt, {required AppConfig config})` (with `skipSdkInit` once it sets up an SDK), `injectDomainLayer`, `injectUiLayer`; `bootstrap` runs them in that order after the logger, config, and error handlers.
- Repositories, clients, and services are lazy singletons keyed by their contract; use cases and blocs are factories; no singleton blocs and no `registerFactoryParam` for ids. Singletons owning streams or native resources register `dispose:`.
- Classes receive dependencies through their constructor; only DI files, `bootstrap`, harnesses, and `inject<T>()` in the UI touch the container. Widgets look up blocs only.
- Implementations are chosen once at registration from config and platform (factories, `architecture` rule → Platforms and assembly); no `if (isProd)` at call sites. Test doubles and the mock app swap at registration too (`replaceSingleton<T>`), never `allowReassignment`.

## Build configuration

Flavors, launch configs, and defines: `CLAUDE.md` → Project facts; mechanics: `configuring-flutter-flavors`.

- Environments (`dev`, `staging`, `prod`) exist on every target: one native flavor per environment on mobile, `--dart-define-from-file=config/web/<env>.json` on web; both read once into `AppConfig`.
- Flavor = native identity (bundle id, name, icon, Firebase config); dart-defines = switches and endpoints, never secrets.
- Production services turn on only from the prod flavor plus an explicit define, never from `kReleaseMode`; a missing value means the non-prod default. Flavor and define changes need a full rebuild.
- Nothing an agent runs reaches production: tests mock the backend; QA and live checks use staging or local on a non-prod flavor.
