---
description: Flutter architecture — layer packages (domain, data, ui, log, utils, localization) with feature folders inside, the layer check, callable use cases, mobile and web from one project with platform factories at assembly, offline and sync levels declared in CLAUDE.md, error flow, logging, security, client API compatibility, live UI check
paths:
  - "**/*.dart"
  - "**/pubspec.yaml"
---

# Flutter architecture

Applies core `architecture-principles` and `same-level-dependencies` to every kit Flutter app. Packages, entry points, platforms, and the facts below: `CLAUDE.md` → Project facts; the repository's `.claude/rules/` win over these defaults. New app: `scaffolding-flutter-app`; new feature: `adding-flutter-features`; existing app: `refactoring-to-kit-architecture`.

## Layers

Packages under `modules/`; dependencies point inward: `ui → domain ← data`. `lib/main.dart` (and `lib/main_web.dart`) is the composition root, the only code importing all three.

| Package | Contains | Depends on |
| --- | --- | --- |
| `domain` | entities, value objects, repository contracts, use cases, calculators, sealed domain exceptions (`modeling-domain`) | `utils`, `log`; pure Dart |
| `data` | API clients, database, SDK services, DTOs, `FooRepositoryImpl` (`data` rule) | `domain`, `utils`, `log`, SDKs |
| `ui` | blocs, UI models, pages, widgets, navigation, theme | `domain`, `utils`, `log`, `localization` — never `data` |
| `log`, `utils` | the global `log`; app-agnostic helpers | pure Dart |
| `localization` | generated copy (`localizing-flutter-apps`) | Flutter only |

- Packages import each other only through their barrels; `tool/check_layers.dart` enforces the table.
- **Feature-first inside every layer**: the same feature folders, named from the domain language, in each package. A feature never imports another feature's folder; shared work goes down (domain, `ui/lib/src/common/`, `utils`) or up (the page or use case composing two).
- domain says what, not how: no DTOs, widgets, or service interfaces; device features are repository contracts. data owns every external dependency. ui reaches the app through blocs (`blocs` rule) calling use cases, or a repository contract for plain CRUD.

## Use cases

- **One job each**, verb-first, one file holding the params record (`typedef FooUseCaseParams = ({String fooId, CachePolicy cachePolicy});`), `abstract class FooUseCase with CallableUseCase<…>`, and `final class FooUseCaseImpl`. Called like a function. Templates: `modeling-domain`.
- The impl takes repository contracts and calculators, keeps no state, has no flag switching two jobs; cache behavior is a `CachePolicy` param. Failures are thrown sealed domain exceptions, never `Result`.
- Rules live in use cases, not in repositories (I/O + mapping) or blocs. A plain CRUD call with no rule may skip the use case.

## Platforms and assembly

- Mobile and web from one project when the product has both (`CLAUDE.md` fact "Web: yes"): `lib/main.dart` and `lib/main_web.dart`, shared layers, per-target screens in their own feature folders.
- Platform differences are chosen at assembly, never branched inside a class: `universal_platform` appears only in the `inject…Layer` functions and factories — service factories, the theme factory, the page helper, and `Adaptive*` widgets (`ui` rule). A library that does not compile on web comes through a conditional import in its factory.
- Environments (`dev`, `staging`, `prod`): native flavors on mobile, one config file per environment on web, read into one `AppConfig` (`di` rule → Build configuration).

## Offline and sync

The level is a `CLAUDE.md` fact; the default is the simple path.

- **Default:** reads paint from the local cache, then refresh (`data` rule → Caching); writes are online: a spinner in the button, the local copy updated from the server's answer.
- **"Offline writes: queued"** (points to the ADR core `architecture-principles` → Offline-first asks for): offline actions are optimistic in the local store and sent by one persistent queue with idempotency keys; a refusal rolls back; online-only actions are never queued (`queueing-offline-actions`).
- **"Sync: delta"**: data arrives through a cursor-based delta endpoint into the local store, triggered by push, resume, and per-screen polling (`syncing-server-changes`).
- **"Device signatures: verified by the backend"**: completion metadata signed with a non-exportable device key (`queueing-offline-actions` → Trusted time and signing).
- In every mode the server is the authority for statuses, verdicts, amounts, and permissions; the client renders them and never shows an optimistic state as a verdict.

## Errors

A store fails with its own exception (`ApiException(code, serverCode:)`, a database error) → the repository maps it to sealed domain exceptions by code → use cases let them through or throw their own → the bloc logs and emits a failed state holding it → the UI maps it to copy in one place (`error.message(context.strings)`). Templates: `handling-errors`.

## Logging

- The pure-Dart `log` package exposes a global `log`; no `print`. `bootstrap` initializes it first and sets `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
- Never log tokens, codes, request bodies, signed URLs, personal data, or file bytes; ids only (`loggedSecret(value)` when an identifier must appear).
- Analytics, when the project has it (`CLAUDE.md` fact "Analytics: …"): one `Analytics` port in domain, events with ids only (`tracking-analytics-events`).

## Security

- The backend enforces authorization; a widget check is not security. Least privilege for device permissions.
- Tokens and keys in `flutter_secure_storage`, never preferences, the database, or logs; one rotating token client. Never commit signing keys, `.env`, or service-account JSON. Audits: `auditing-flutter-security`.

## Client API compatibility

Contract-first: with an OpenAPI contract the client and models are generated (`generating-api-clients`); otherwise read the backend's real definition. Never invent a request shape; additive optional fields only, with the assumption stated.

## Live UI verification

User-visible changes are checked in the running debug app: M/L tasks through `flutter:qa`, small ones by the lead (`driving-flutter-app`).
