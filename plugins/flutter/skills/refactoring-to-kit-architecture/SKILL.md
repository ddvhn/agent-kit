---
name: refactoring-to-kit-architecture
description: Migrate an existing Flutter app onto the kit architecture step by step, without a big-bang rewrite — assess packages and dependency direction (layer check), state management, DI, routing, persistence, data-layer conversions, errors, logger, theme, and tests; write a gap table and a migration ADR; migrate in an order that keeps every commit green (agent setup, guards in report mode, logger, errors, DI, data contracts and conversions, use cases, blocs, routing, persistence, theme), feature by feature with the strangler pattern; record exceptions and migrate-when-touched items in .claude/rules; safeguard risky moves (local database package or file format, routes and deep links, backend contracts, shared modules used by another app); characterization tests first; done criteria. Use when an existing app does not follow the kit layout or conventions and the user wants it moved there, or when planning which legacy parts to migrate.
---

# Refactoring to the kit architecture

Policy: core `architecture-principles`, `same-level-dependencies`, and `minimal-change` (a migration step is the asked scope — nothing beyond it); the stack `architecture`, `dart`, `data`, `di`, and `testing` rules. The target shape: `scaffolding-flutter-app` (layout, packages, templates). Every step runs through `delivering-changes`; agent setup through `adopting-agent-kit`. New features during the migration: `adding-flutter-features`.

Ground rules:

- **No big bang.** One step = one approved plan and branch; subtasks commit green (build, analyzer, suites). The app ships between steps.
- **Refactoring steps preserve behavior.** Characterization tests come first; a bug found on the way is a separate fix with its own test, never folded into a move.
- **New code follows the kit from the moment the ADR is accepted.** Old code migrates in its planned step or when touched. Never copy a legacy neighbor.
- **One concept, one implementation.** A step ends with the legacy unit deleted, not kept beside its replacement (`minimal-change`: no parallel terms).

## 1. Assess (read-only)

Fan out with `Explore` agents, one per area; the lead reads the key files itself. Record facts with paths and counts, not impressions.

| Area | Find | Kit target |
| --- | --- | --- |
| Packages and dependency direction | workspace or single package, `modules/` or `lib/` folders, path dependencies, git submodules and which other apps consume them; each package's declared dependencies (a `flutter` or SDK dependency in domain, utils, or the logger) | `architecture` rule → Layers |
| Composition roots | every `main.dart`: one app (`lib/main.dart`) or several apps in one workspace (`apps/<name>/lib/main.dart`), each with its own startup order and DI calls | `di` rule → Wiring |
| Layer violations | copy `tool/check_layers.dart` from the `scaffolding-flutter-app` templates to the scratchpad, map `_layers` (section 3 → Layer-check mapping), run it; count violations per layer pair | zero violations |
| State management | Cubit / Bloc / provider / riverpod / `setState` doing I/O; `*Cubit` names, singleton blocs, bloc-to-bloc calls, ids in constructors or factory params | `writing-load-blocs`, `writing-action-blocs`, `observing-data`, `paging-lists` |
| Business logic placement | blocs or widgets with several repositories, ordering, or rules; repositories with rules | use cases and models (`modeling-domain`) |
| DI | container, entry-point names, `GetIt.instance` inside classes, `registerFactoryParam`, startup order in `main` | `di` rule |
| Data layer | API clients per feature or per source; where conversions live (on the DTO or on store models); DTOs exported from the data barrel; JSON outside Api models | `data` rule, `creating-flutter-repositories`, `calling-cloud-functions` |
| Persistence | engine and package version, what each collection holds (re-fetchable cache or user data), side effects in constructors, cache policy and TTL | `persisting-with-isar`, `data` rule → Caching |
| Errors | exception types, branching on message text, raw errors or `toString()` on screen, empty catches | `handling-errors` |
| Logger and crash reporting | logging package, `print`, logger in GetIt, crash handlers, secrets in logs | `architecture` rule → Logging |
| Routing | `Navigator`, string-path or typed `go_router`; every inbound link: deep links, push payloads, web URLs, redirects, `extra` objects | `adding-flutter-routes` |
| Theme and copy | hard-coded colors, text styles, sizes; copy outside ARB | `theming-flutter-apps`, `localizing-flutter-apps` |
| Tests | suites, harness, Patrol, which critical flows and repositories have no test | `testing` rule, `setting-up-patrol` |
| Build configuration | flavors, defines, `kDebugMode` switches for prod services | `configuring-flutter-flavors` |
| Launch configs and live checks | which debug configs disable VM-service auth codes or pin a port, and which of them talk to production | `scaffolding-flutter-app` → Launch configs, `configuring-flutter-flavors`, `driving-flutter-app` |

## 2. Gap table and ADR

Turn the assessment into one table, one row per gap:

| Area | Current | Kit | Strategy | Kind | Risk |
| --- | --- | --- | --- | --- | --- |
| Blocs | `FooCubit`, ids via factory param | `LoadFooBloc` + `configure` | per feature, step 10 | Sonnet | low |
| Persistence | legacy Isar 3 package | `isar_plus` | cache reset, step 12 | Lead + ADR | high |
| Navigation | string paths | typed routes | kept exception | — | — |

- **Strategy** is one of: migrate in step N, migrate when touched, kept exception (with the reason).
- **Kind**: Haiku (mechanical: `core:developer` with `model: haiku`), Sonnet (pattern known, judgment per file), Lead + ADR (a design choice). Any step that changes a shared module another app consumes is Lead-owned whatever its kind here (section 6).
- Write the migration ADR (`recording-decisions`): context (the assessment), the gap table, the step order, kept exceptions, and the rule for new code. High-risk rows get their own ADR when their step is planned. The user's approval makes it Accepted; nothing moves before that.

## 3. Order

Each step leaves the app releasable. Later steps assume the earlier ones.

| # | Step | Owner skill / rule | Kind |
| --- | --- | --- | --- |
| 0 | Agent setup: `CLAUDE.md`, `.claude/rules/`, settings; the migration status file (section 5) | `adopting-agent-kit` | Lead |
| 1 | Safety net: characterization tests for the critical flows and every persisted entity (section 7) | `setting-up-patrol`, `writing-patrol-tests`, `persisting-with-isar` | Lead picks flows, Sonnet writes |
| 2 | Guards in report mode: the layer check with a baseline of today's violations (new violations fail, old ones are listed); stricter lints at `info` severity in packages not migrated yet (`analyzer: errors:` in that package's `analysis_options.yaml`), never `// ignore` | `scaffolding-flutter-app` → Layer check | Haiku |
| 3 | Workspace skeleton when the app is not split: root workspace, `modules/` packages from the templates; legacy code stays in its package and may import the new ones, never the reverse | `scaffolding-flutter-app` | Lead, then Haiku |
| 4 | Logger: an existing app logger is renamed and reshaped into the template's `log` package (folder `modules/logger`), not added beside it — package renamed to `log`, Flutter and `path_provider` dropped (the logs directory comes from `main` through `initializeLogger`), console formatting without Flutter. Then `initializeLogger()` and crash handlers in `main`, `print` and stray loggers replaced call by call; `utils` may keep re-exporting it | `scaffolding-flutter-app` → Logger, `handling-errors` → Logging | Lead designs, Haiku applies |
| 5 | Pure core: `domain` and `utils` become pure Dart. SDK and Flutter types in domain models become domain value objects (a `GeoPoint` instead of a location-SDK position), converted in data; Flutter or device helpers in `utils` move to `ui` or `data`; unused `flutter` dependencies leave the pubspecs; domain tests run on `package:test` with `dart test` (create the suite when there is none) | `modeling-domain`, `testing-use-cases`, `architecture` rule → Layers | Lead + shared-module safeguards |
| 6 | Error types: `AppException` base, `ApiException` and the store call helper, the repository guard, the UI extension; old exception types mapped in the guard, then removed as callers move; message-text branches replaced by types | `handling-errors`, `modeling-domain` | Lead designs, Sonnet applies |
| 7 | DI names and wiring in every composition root: `injectDataLayer` / `injectDomainLayer` / `injectUiLayer`, `main` order, contract-keyed registrations, `GetIt.instance` out of classes; a different container only with an ADR | `di` rule | Haiku |
| 8 | Data layer, per feature: one API client per remote source, repository contracts in domain, `FooRepositoryImpl` behind the guard, `CachePolicy` on cached reads. Conversions move per store, all of one store's models in one step (the `data` rule forbids mixed directions inside a store) | `creating-flutter-repositories`, `calling-cloud-functions`, `persisting-with-isar` | Sonnet; conversion moves Haiku |
| 9 | Use cases where logic lives in blocs, per feature, test first; plain CRUD stays repository-in-bloc | `modeling-domain`, `testing-use-cases` | Sonnet |
| 10 | Blocs, per feature: names, load and action states, `configure`, UI models, presentation events, no bloc-to-bloc calls | `writing-load-blocs`, `writing-action-blocs`, `observing-data`, `paging-lists` | Sonnet |
| 11 | Routing (high risk, section 6) | `adding-flutter-routes` | Lead + ADR |
| 12 | Persistence package or file format (high risk, section 6) | `persisting-with-isar` | Lead + ADR |
| 13 | Theme tokens, then hard-coded values replaced screen by screen; copy into ARB | `theming-flutter-apps`, `localizing-flutter-apps` | Lead for tokens, Haiku for sweeps |
| 14 | Guards to blocking: empty layer-check baseline, lints back to their severity, analysis without relaxations | — | Haiku |

Steps 8–10 run per feature and may interleave (feature A through 8–10 before feature B starts). Steps 11–13 may be reordered by product need; record that in the ADR.

**Layer-check mapping.** `_layers` keys are package folders relative to the workspace root (`'modules/domain'`, or `'modules/common/domain'` when the layers sit in a shared folder or submodule); a configured folder that does not exist fails the check, so the map must match the tree. Each app is mapped as its own folder (`'.'`, `'apps/<name>'`) and may import layers only through their barrels. A workspace with several apps maps every app-specific package too (an app's own `modules/ui` gets the `ui` rules). Each repository that consumes a shared submodule maps it with the same keys, so both run the same check on it.

**Shared modules.** A step that changes a package or submodule another app consumes is Lead-owned, whatever its kind above: each subtask runs the other app's analyzer and tests against the change, the other app gets its submodule pointer bump (or migration) in its own branch, and the row appears in both repositories' `migration.md` (section 6).

## 4. Strangler per feature

For each feature in steps 8–10:

1. Pick the next feature: a leaf (nothing else depends on it) or the one the next product task touches.
2. Characterization tests for it are green on the old code.
3. Build the kit-shaped unit in its target package next to the old one: contract, implementation, tests.
4. Switch callers one at a time: the DI registration for the contract points to the new implementation; old blocs or pages call the new use case or repository through their constructor. The old code may delegate to the new unit while callers remain; the new unit never calls the old one.
5. Delete the old unit when its last caller moved, in the same branch. Remove its entries from the layer-check baseline.
6. Update the migration status (section 5) and `CLAUDE.md` → Project facts → Neighbors to copy when the feature becomes the best example.

A feature too large for one branch is split by sub-flow, not by layer: each sub-flow ends deleted-and-replaced.

## 5. Record exceptions and stop drift

- **Migration status** in `.claude/rules/migration.md` (no `paths:`, so it is always loaded; under 9,000 characters): one row per gap with its status — migrated, in progress (branch), migrate when touched, kept exception — how to recognize the legacy shape (path or pattern), and the ADR. Rows leave the file when migrated; the file is deleted at the end or keeps only kept exceptions. A row about a shared module appears in every consuming repository's `migration.md`, with the same status.
- **Kept exceptions** go in the topic rule they override (`.claude/rules/architecture.md`: "Exception: navigation keeps string paths (ADR-00N)"), stated as an exception so agents follow it on purpose.
- **Migrate when touched** means: a task that changes a legacy unit's behavior migrates that unit (not its neighbors) in its own subtask before the change, when it fits one subtask; larger → ask. A one-line bug fix in legacy code stays legacy-shaped and says so in the handoff.
- **Drift stops at review**: new code in a legacy shape listed in `migration.md` is a Must fix (`reviewing-branch`, `core:reviewer`); the layer check fails on any violation not in the baseline; `CLAUDE.md` → Project facts → Neighbors to copy names only migrated code.

## 6. Risky migrations

| Migration | What can go wrong | Safeguards |
| --- | --- | --- |
| Persistence package or file format (for example a legacy Isar 3 package → `isar_plus`) | the new engine cannot read the old file; user data (offline downloads, drafts, unsynced state) lost; both native cores in one binary may conflict | Ask first (persistence schema). Classify every collection: re-fetchable cache → cache reset (schema version check deletes the old file before first open, `persisting-with-isar` → Schema changes); user data → re-sync from the backend or a one-release migration that reads the old file and writes the new one, only if both engines can ship together, otherwise an export step in a prior release. Round-trip tests on the new engine; an upgrade test: install the last release, create data, install the new build, check the data or the planned reset. |
| Routing (`Navigator` or string paths → typed `go_router`) | dead deep links and push targets, broken web URLs and bookmarks, redirect loops, lost back-stack behavior, objects passed in `extra` | Inventory every inbound link (platform link config, push payload routes, web paths, the deep-link handler) into the ADR; keep the paths identical; one Patrol test per deep link and per redirect state before the switch. Typed routes can join an existing `GoRouter` next to string routes, so string paths migrate per feature; `Navigator` → `go_router` moves the shell and redirect in one step, screens per feature after. |
| Backend contract | a refactored Api model changes the wire: field names, nulls, enum values, callable name or region | Refactoring never changes the wire: pin today's JSON in API-client tests with fixtures captured from a non-production backend before moving models. A contract change is a working-agreement "ask first"; the backend adds `fooV2` and keeps the old one for clients in the field. |
| Shared module used by another app (a package or git submodule) | a renamed or moved public symbol breaks the other app; the other app pins an older pointer | Ask first (shared-module contract). Grep every consumer (`CLAUDE.md` → Related repositories). Lead-owned subtasks. Add the new API beside the old one, mark the old `@Deprecated`, migrate each app, remove the old API last. Every subtask runs the other app's analyzer and tests against the branch; each app bumps its submodule pointer in its own branch; a package becoming pure Dart (step 5) must still build for every platform each consumer targets. |
| State management library change | rewriting screens loses edge-case behavior | Per screen, behind Patrol flows; the old and new libraries coexist only until the feature's branch ends. ADR. |

## 7. Tests

- **Characterization before moving code.** Patrol flows for the critical journeys, asserting what the user sees (they survive any internal move; the only UI change allowed for them is widget keys, `writing-patrol-tests`). Repository round-trips against a real test database with the API client mocked, pinning today's mapping and cache behavior. API-client tests pinning the wire JSON.
- They pin current behavior, odd parts included. A wrong behavior gets its own fix later, with a test that states the right behavior.
- **TDD for new logic**: extracting rules from a bloc into a use case starts with use-case tests derived from the bloc's current behavior (`testing-use-cases`), then the extraction.
- A test that moves with its code changes imports and names only; an assertion change needs a reason in the commit body. Never weaken, skip, or delete a test to get a step green.

## 8. Done

Per step:

- [ ] Builds; analyzer clean at the agreed severities; layer check shows no new violations and the step's baseline entries are gone
- [ ] Characterization and unit suites green, unchanged except for moves; Patrol flows for the touched features green
- [ ] UI touched → live check (`driving-flutter-app`, or `flutter:qa` for large steps) shows no visible change
- [ ] The legacy unit is deleted, not kept beside its replacement
- [ ] `migration.md`, kept exceptions, `CLAUDE.md` (Neighbors to copy, Verification), and the ADR status updated
- [ ] Risky step: its ADR accepted and its safeguards from section 6 verified, the upgrade test included

Whole migration:

- [ ] Layer check blocking with an empty baseline; lints at full severity in every package; both in CI
- [ ] Every gap-table row is migrated or a kept exception with an ADR in the topic rule
- [ ] `migration.md` deleted or reduced to kept exceptions
- [ ] `reviewing-branch` over a sample of features reports no kit-rule findings
- [ ] A new feature can be delivered with `adding-flutter-features` without touching legacy shapes
