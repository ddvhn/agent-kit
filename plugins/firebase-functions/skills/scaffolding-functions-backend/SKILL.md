---
name: scaffolding-functions-backend
description: Create a Firebase Functions backend from scratch the kit way, or bring an existing one onto the kit layout — functions/ folders by layer, package.json scripts and Node engines, tsconfig path aliases, ESLint, firebase.json with emulators, Functions v2 API choice and shared options, callable middleware (auth, Zod, typed error to HttpsError mapping), DB registry with typed converter and versioned schemas, params and secrets, the emulator test harness, CI, and what to record in CLAUDE.md. Use when starting a new backend, adding the first callable or entity to an empty one, or unifying an existing backend's structure.
---

# Scaffolding a Functions backend

The result follows the `platform`, `architecture`, `data`, `testing`, and `typescript` rules of this plugin and the `backend-*` rules it builds on; record the platform choice in an ADR (`recording-decisions`). Templates use `Foo` / `foo` and `demo-foo`; replace them with the real names once, everywhere (ubiquitous language: the `architecture` rule → Domain model).

Reference files in this folder:

- [project-config.md](project-config.md) — `package.json`, tsconfigs, ESLint, `firebase.json`, `.firebaserc`, params and env files, `.gitignore`, test scripts, CI.
- [source-templates.md](source-templates.md) — `src/index.ts`, options, middleware, domain errors, DB registry, converter, versioned schema, migrator, repository, provider service and factory, use case, callable, ApiModel.
- [test-harness.md](test-harness.md) — runner config, emulator safety, reset, auth token, callable client, polling, mock composition root, builders, first tests.

## Workflow

1. **Ask first** (they are expensive to change later): Node major (the newest LTS the Cloud Functions runtime supports), region (Firestore and Storage triggers must run in a region compatible with the database and bucket location — ask for those too), project ids or aliases (stage, prod), the client repositories that will call it, the first entities and provider integrations, whether entities are versioned (default: yes, `v1` from day one), and the App Check plan (default: log `request.app` from day one, enforce once every client ships it — `securing-firebase-data` → App Check).
2. **Existing backend?** Inventory it against the layout below and the rules; list the differences and ask which to converge now. Do not mass-move files in one change — converge per feature, each subtask green.
3. Create the layout and config files (`project-config.md`), then `npm install`.
4. Write the test harness (`test-harness.md`) and one failing integration test for the first callable.
5. Write the source skeleton (`source-templates.md`) for one feature end to end: entity schema `v1` + migrator + registry entry → repository + its unit test → use case → callable + ApiModel → export.
6. Run `npm run lint`, `npm run typecheck`, `npm run build`, `npm run test:unit`, `npm run test:integration` until green; `npm run test:rules` once the rules exist (step 7).
7. Write the security rules and indexes (`securing-firebase-data`): deny-all by default.
8. Add CI (`project-config.md` → CI).
9. Record the project in `CLAUDE.md` and `.claude/rules/` through the core skill `adopting-agent-kit` (What to record, below).

## Layout

```
firebase.json  .firebaserc  firestore.rules  firestore.indexes.json  storage.rules
functions/
  package.json  tsconfig.json  tsconfig.build.json  tsconfig.mocks.json
  eslint.config.js  vitest.config.ts  .nvmrc
  .env  .env.stage  .env.prod  .env.demo-foo  .env.local.example  .secret.local.example
  scripts/  test-unit.sh  test-integration.sh  test-rules.sh  build-emulator-mocks.sh
  src/
    index.ts                       composition root
    utils/                         testMode.ts, getErrorMessage.ts (pure, importable from all layers)
    core/
      firebaseApp.ts
      db/                          firestoreDb.ts (registry `db`), index.ts
        utils/                     createFirestoreConverter.ts, firestoreDocumentMigrator.ts, withId.ts
        common/                    shared value schemas (identifierSchema.ts, …)
        entity/foo/                schema/v1.ts, schema/latest.ts, migration.ts
      foo/                         fooService.ts, fooServiceFactory.ts, acmeFooService.ts, fooServiceError.ts
    data/
      repository/                  fooRepository.ts
    domain/
      error/                       domainError.ts
      usecase/foo/                 createFooUseCase.ts, utils/getFooOrThrow.ts, utils/fooRules.ts, error/fooErrors.ts
    api/
      index.ts                     exports every function
      config/                      functionsConfig.ts (region, global options, shared params)
      common/middleware/           onCallWithMiddleware.ts, authMiddleware.ts, validateSchemaMiddleware.ts, toHttpsError.ts
      common/validation/schemas/   request value schemas
      endpoints/foo/               createFoo.ts, model/fooApiModel.ts
  test/
    unit/  integration/            mirror src paths
    rules/                         firestore.rules.test.ts, storage.rules.test.ts
    utils/                         setup/emulatorSafety.ts, resetEmulatorState.ts, authToken.ts, callableClient.ts, waitUntil.ts
    mocks/                         mockAssembly.ts, core/foo/mockFooService.ts, foo/mockFooEntity.ts
```

Dependencies point `api → domain → data → core`; ESLint enforces it (`project-config.md` → ESLint).

## Functions v2 API choice

| Need | API (`firebase-functions/v2/...`) |
| --- | --- |
| The app calls the backend with a signed-in user and a typed payload | `onCall` (`https`) through the callable middleware |
| Webhook, redirect, public link, a third party calls it | `onRequest` (`https`) — verify the caller, set CORS |
| React to a document change | `onDocumentCreated` / `Updated` / `Deleted` / `Written` (`firestore`) |
| React to an uploaded file | `onObjectFinalized` (`storage`) |
| Periodic job | `onSchedule` (`scheduler`) |
| Deferred, rate-limited, or retried work | `onTaskDispatched` (`tasks`) + enqueue after commit |
| Gate sign-up or sign-in | blocking `beforeUserCreated` / `beforeUserSignedIn` (`identity`; needs Identity Platform) |

Background kinds (triggers, schedules, tasks): `writing-background-functions`. Every function takes the shared options: `setGlobalOptions(FUNCTIONS_GLOBAL_OPTIONS)` in `src/index.ts` before any function is defined, and `FUNCTIONS_REGION` wherever the region must be named (task queue paths, the test callable client). A function's region is part of the client contract: never change it for a deployed function.

## Params and secrets

- Non-secret config: `defineString` / `defineInt` / `defineBoolean` in `api/config` or the function file; values in `.env` (all projects), `.env.<alias or project id>` (per project, committed), `.env.local` (emulator-only personal overrides, git-ignored, `.env.local.example` committed).
- Secrets: `defineSecret("FOO_API_KEY")`, listed in the function's `secrets` option, read with `.value()` inside the handler only, and passed down as params. Production values live in Secret Manager (`firebase functions:secrets:set` — run by a human). The emulator reads them from `functions/.secret.local` (git-ignored; `.secret.local.example` committed with fake values). Never put a secret in `.env*`.
- Never call `.value()` at module scope; deploy-time analysis has no values. Lazy construction in factories covers services that need params.
- The test project `demo-foo` has its own committed `.env.demo-foo` with test values and the test-mode switch.

## Callable middleware

One wrapper (`onCall(functionName, options, handler, ...middlewares)`) runs the middlewares in order, then the handler, logs start / finish / failure with duration and uid (never payloads), and converts every thrown error once with `toHttpsError` — `HttpsError` as is (`validateSchemaMiddleware` throws `invalid-argument` for a request that fails its schema), `DomainError` by code in an exhaustive `switch`, anything else (a converter's `ZodError` too) → `internal` with a generic message. Middlewares: `authMiddleware({allowAnonymous?, requiredClaim?})`, `validateSchemaMiddleware(schema)` (replaces `request.data` with the parsed value), plus project ones (ownership, subscription). Templates: `source-templates.md`.

## Test harness

Three suites, each starting its own emulators through `firebase emulators:exec --project demo-foo`: `test:unit` (Firestore only; repositories, migrators, pure domain functions), `test:rules` (Firestore and Storage, client SDK; security rules), and `test:integration` (Auth, Firestore, Functions, Storage, Pub/Sub, Cloud Tasks; runs `build:emulator` first so the compiled mocks are in `build/test`). The `demo-` prefix makes the Firebase CLI refuse to touch any cloud resource. Safety setup, reset, token, client, mock composition root, builders: `test-harness.md`.

## What to record

Through `adopting-agent-kit`:

- `CLAUDE.md` → Project facts: platform and Node major, source root `functions/src`, layers, exports entry `functions/src/api/index.ts`, region, project aliases and the emulator project id, integration and release branches, neighbors to copy (one repository, use case, callable, test of each); Test suites; Review zones (exported names, regions, request / response shapes; transactions and multi-document writes; versioned entities and migrators; auth middleware, claims, secrets, payment or store verification; security rules); Verification commands (`lint`, `typecheck`, `test:unit`, `test:rules`, `test:integration`, `build`, `build:emulator`); Related repositories (the clients).
- `.claude/rules/` → the real names: registry object, middleware and helper names, helper folders, the provider mock list, coverage gates, any exception to a kit rule (stated as an exception).

## Done when

- [ ] `npm run lint`, `npm run typecheck`, `npm run build`, all three suites green locally and in CI
- [ ] One feature end to end with tests written first
- [ ] Layer imports enforced by ESLint; no `HttpsError` below `api`
- [ ] Emulator safety asserts a `demo-*` project id and localhost hosts
- [ ] Firestore and Storage rules deny all by default; indexes file present
- [ ] No secret in a committed file; `.secret.local` and `.env.local` git-ignored
- [ ] `CLAUDE.md` and `.claude/rules/` written
