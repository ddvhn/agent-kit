---
name: adding-flutter-features
description: Deliver one new feature end to end in a Flutter app that already follows the kit architecture, in TDD order — clarify the domain language, spec, backend contract, offline behavior, screens and states; then a backend subtask in a session opened in the backend repository when the contract is new, and client subtasks domain → data → DI → ui → integration tests → live check → docs, each naming the skill to load; a decision table for the frequent choices (use case or repository in the bloc, load / action / observe / paged bloc, cached or network-only, route or modal, new feature folder or extending one); a file checklist per layer with the kit's names and locations; and the review points the lead verifies per subtask. Use when adding a feature, screen, or user flow to a kit-shaped app, or when planning one with delivering-changes.
---

# Adding Flutter features

Policy: core `architecture-principles` (DDD, TDD, offline-first), `same-level-dependencies`, `minimal-change`; the stack `architecture`, `data`, `di`, `dart`, and `testing` rules. Workflow: `delivering-changes` — this skill supplies the plan's content (questions, subtasks, files, review points). An app not yet in kit shape: new code still goes into the kit packages in kit shape, and legacy code is touched per `refactoring-to-kit-architecture`. A new app: `scaffolding-flutter-app`.

## 1. Clarify (before the plan is approved)

| Question | Answer goes to | Skill |
| --- | --- | --- |
| The nouns, rules, and outcomes, in the spec's and backend's words | feature spec in `docs/` (new or updated) | `recording-decisions`, `modeling-domain` → Ubiquitous language |
| Acceptance criteria per flow (happy, empty, error, auth) | plan; they become the test cases | `testing-use-cases` |
| Backend contract: callable names, region, request, response, error codes — existing or new | read in the backend repository (`CLAUDE.md` → Related repositories); a new or changed contract is "ask first" and lands in the backend first (Subtask 0) | `calling-cloud-functions` |
| Paged list? | the shared paged contract: request `cursor` (optional) and `limit`, response `items` and `nextCursor` (null on the last page), camelCase keys; the client keeps the cursor opaque | `paging-lists` |
| Offline: cached or network-only, what shows offline with and without data, whether writes must work offline | plan; an offline write queue needs an ADR | `data` rule → Caching |
| Screens and states: entry points (tab, push, modal, deep link), loaded / empty / error / offline / saving, copy, design | plan, approved with it | the project UI skill (`CLAUDE.md` → Project facts), `theming-flutter-apps` |
| Does another screen show the same data and need to update? | plan | `observing-data` |
| New third-party provider or persisted schema change | ask first (mock coverage; schema strategy) | `persisting-with-isar` |

Output: the spec, an ADR when a real alternative was chosen, and the plan below.

## 2. Decisions

| Choice | Pick | When |
| --- | --- | --- |
| Use case or repository in the bloc | repository contract injected into the bloc | a plain CRUD call with no rule |
| | use case (`modeling-domain`) | a rule, ordering, several repositories, or a check before a write |
| Bloc kind | load (`writing-load-blocs`) | the screen shows one payload it fetches |
| | action (`writing-action-blocs`) | a button or form changes data |
| | observe (`observing-data`) | the value changes elsewhere (session, settings, counters, background sync) |
| | paged (`paging-lists`) | the list grows by pages |
| Cached or network-only | cached (`persisting-with-isar`, `CachePolicy`) | the user should see it offline or instantly on reopen |
| | network-only | live, one-off, or sensitive data; search results |
| Route or modal | route (`adding-flutter-routes`) | a screen reachable by link, back stack, or web URL; a sheet that must survive restoration |
| | modal without a route | a confirmation, picker, or toast owned by one page |
| Feature folder | extend the existing one | the concept belongs to that bounded context (same aggregate, same spec) |
| | new folder in every layer | a new concept with its own language, contracts, and spec; it reaches others only through their contracts |
| API client | a method on the existing `{Source}ApiClient`, named exactly like the callable (`getFoo`, `listFoos`, `updateFoo`) | always, per remote source; a new client only for a new remote source |
| Repository and use-case names | domain verbs, not wire names: `fetchFoo`, `fetchFoos`, `saveFoo`; live updates `observeFoo(...)` or `fooUpdates` | always (`creating-flutter-repositories` → Naming) |

## 3. Subtasks, tests first

### Subtask 0 — Backend (new or changed contract)

- **Where it runs**: a separate session opened in the backend repository. Its `CLAUDE.md`, `.claude/rules/`, and stack plugin load only there; `--add-dir` gives this session the files but not those plugins or rules. A repository that holds both (`functions/` with both stack plugins enabled) runs it in the same session.
- **Order**: the backend branch comes first — spec and contract in the backend (it owns the behavior, `recording-decisions`), callable, use case, repository, emulator tests: `firebase-functions:writing-cloud-functions`, `creating-firestore-repositories`, `testing-cloud-functions`. Additive fields or a `fooV2` export, never a breaking change to a deployed callable.
- **Client side**: client subtasks start once the contract is agreed (their tests mock the API client); the client live check runs against local emulators serving the backend branch until a human deploys it to staging — agents never deploy. Handoff names both branches; the backend merges and deploys before the client ships.

### Client subtasks

One commit per subtask (`delivering-changes`). After the domain subtask, the data and ui subtasks touch disjoint files and may run in parallel (ui mocks domain contracts); verify and commit them one at a time. Briefs name the neighbor feature to copy.

### Subtask 1 — Domain

Skills: `modeling-domain`, `testing-use-cases`, `handling-errors` (feature exceptions). `core:developer` on Sonnet.

1. Tests first from the acceptance criteria: entity behavior, draft validation, calculators, each use-case branch and repository outcome; contracts and `Impl` stubs exist so the tests fail on behavior.
2. Models, sealed feature exceptions and results, repository contract, use cases; barrels; use-case registrations in `injectDomainLayer`.

Lead verifies: names match the spec and backend; pure Dart (`dart test` passes); behavior on the model, time and ids injected; exceptions only for failures someone branches on; no use case calls another; contract methods named per `creating-flutter-repositories` → Naming, `CachePolicy` on cached reads.

### Subtask 2 — Data

Skills: `creating-flutter-repositories`, `calling-cloud-functions`, `persisting-with-isar`, `handling-errors`, `observing-data` (update streams). Sonnet; codegen and test-double stubs may go to Haiku.

1. Tests first: repository round-trips against the real per-test database with the API client mocked — mapping, each cache policy, each error mapping the feature adds, the update stream.
2. Api models (camelCase keys as the backend sends them), DTO, Db model with their conversions; API client method named like the callable (contract, implementation, every existing test double); database client methods; `FooRepositoryImpl` behind the guard; codegen run.

Lead verifies: store contracts speak DTOs and each store converts its own models; nothing leaves data but domain types and `AppException`s; writes update the local copy from the server response; the method name, region, request, and response match the backend export; every error code the callable can emit maps to an `ApiErrorCode` and a domain exception; schema change approved; no JSON outside Api models.

### Subtask 3 — DI

`scaffolding-flutter-app` → DI lifetimes. Usually folded into subtasks 2 and 4 (each registers its own types); a separate Haiku subtask only when wiring spans several features.

Lead verifies: registered by contract; factories for use cases and blocs; no factory parameters; the integration harness can replace every new I/O type with `replaceSingleton`.

### Subtask 4 — UI

Skills: the bloc skill from the decision table, `theming-flutter-apps` and the project UI skill, `localizing-flutter-apps`, `adding-flutter-routes`, `handling-errors` (UI mapping). Split blocs and pages into two subtasks when large.

1. Tests first where the project unit-tests blocs (repository rules): the state lists in the bloc skill's Tests section; UI-model factories in ui unit tests.
2. Blocs and UI models; pages and widgets on theme tokens and shared widgets; copy keys in every locale; the feature's exception copy; route classes and generator; widget keys for the flows; bloc registrations in `injectUiLayer`.

Lead verifies: blocs get dependencies through the constructor and ids through `configure`; states hold UI models and `AppException`; one bloc per boundary, no bloc-to-bloc calls; offline with data is not an error view; no hard-coded colors, sizes, or copy; accessibility per the `dart` rule; navigation only through route classes.

### Subtask 5 — Integration tests

Skill: `writing-patrol-tests`. One file per flow from the acceptance criteria: happy, empty, error with retry, offline with cache when cached, auth gate when gated. They may be written before subtask 4 (outside-in) when the screens are fully specified.

Lead verifies: every new API-client method stubbed in each test that reaches it; fallbacks registered; only I/O replaced; each test owns its ids and seed data; run with the Patrol command, never `flutter test`.

### Subtask 6 — Live check

`driving-flutter-app` for a small feature; `flutter:qa` for M/L, against a non-production backend (local emulators serving the backend branch while Subtask 0 is not deployed). Bugs go back through the subtask cycle as new commits; scenarios `qa` lists as candidates become Patrol tests.

### Subtask 7 — Docs and branch

The spec changed with the code in each subtask (`recording-decisions`); here: `CLAUDE.md` → Specs lists a new spec, a new convention goes to `.claude/rules/`, ADRs are Accepted. Then `reviewing-branch` (with `core:reviewer` for L).

## 4. File checklist

Feature `foo`, remote source `{source}`; the project's own layout wins (repository rules).

| Layer | File | When |
| --- | --- | --- |
| domain | `modules/domain/lib/src/foo/model/foo.dart` (+ `foo_draft.dart`, `foo_exception.dart`, `…_result.dart`) | always / editable input / branched-on failures / expected alternatives |
| | `…/foo/repository/foo_repository.dart` | new I/O |
| | `…/foo/usecase/fetch_foo_use_case.dart` | a rule or orchestration |
| | `…/foo/calculator/foo_…_calculator.dart` | a rule several use cases share |
| | `domain_model.dart`, `domain_repository.dart`, `domain_usecase.dart` (`hide …Impl`), `src/di.dart` | every new public type, every use case |
| | `modules/domain/test/foo/…_test.dart`, `test/mocks/mock_foo.dart` | always |
| data | `modules/data/lib/src/data_store/dto/foo/foo_dto.dart` | always |
| | `…/remote/api/{source}/models/foo/foo_api_model.dart` (+ request model), method on `{source}_api_client.dart` and its implementation | remote |
| | `…/local/database/isar_database/models/foo/foo_db_model.dart`, methods on `database_client.dart` and `isar_database.dart` (+ web) | cached |
| | `…/repository/foo_repository_impl.dart`, `src/di.dart` | new contract |
| | `modules/data/test/…/foo_repository_impl_test.dart`, `test/mocks/mock_foo_dto.dart` | always |
| ui | `modules/ui/lib/src/foo/blocs/load_foo_bloc.dart` / `create_foo_bloc.dart` / `observe_foo_bloc.dart` | per decision |
| | `…/foo/models/foo_ui_model.dart` | the bloc shows domain data |
| | `…/foo/pages/foo_page.dart`, `…/foo/widgets/foo_tile.dart` | screens |
| | `…/foo/keys.dart` + entry in `ui/lib/keys.dart` | widgets a flow touches |
| | the feature's exception copy extension in `…/foo/` + one line in the central UI mapping | new feature exceptions |
| | route class in the router file | new route |
| | ARB keys in every locale (`modules/localization`) | new copy |
| | `modules/ui/lib/src/di.dart`, `modules/ui/test/foo/…` | blocs; where blocs are unit-tested |
| app | `patrol_test/foo_…_test.dart`, `patrol_test/modules/foo_module.dart`, stubs in the mock dependencies | every flow |
| docs | `docs/foo.md`, `docs/decisions/NNN-….md`, `CLAUDE.md` → Specs | per section 1 |

## Checks

- [ ] Spec and acceptance criteria agreed before code; contract confirmed in the backend, or Subtask 0 done first in a backend session
- [ ] Each subtask: tests written first and seen failing for the right reason; narrowest suite green
- [ ] Decisions from section 2 recorded in the plan; ADR for real alternatives
- [ ] Every file in section 4 that applies exists, is exported, and is registered
- [ ] Integration flows cover the acceptance criteria; live check done on a non-production backend
- [ ] Spec, `CLAUDE.md`, and rules updated; `reviewing-branch` verdict ready to merge
