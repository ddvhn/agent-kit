---
description: Firebase Functions architecture — layers (api → domain → data → core), domain model, use cases as units of work, API boundary (handler shape, Zod, HttpsError mapping), typed errors, provider services, Firebase security, client API compatibility
paths:
  - "functions/**"
---

# Firebase Functions architecture

The Firebase realization of the core principles and the `backend-*` rules; overrides: the `platform` rule. Source root, entry point, region: `CLAUDE.md` → Project facts; the repository's `.claude/rules/` win over these defaults. Persistence: the `data` rule. A new backend: `scaffolding-functions-backend`.

## Layers

Dependencies: `api → domain → data → core`, each importing only layers to its right; `utils` (pure helpers, the test gate) from all. `src/index.ts` is the composition root: global options, test mocks behind the gate, re-export of `api`.

| Layer | Contains | Never |
| --- | --- | --- |
| `core` | entity and value schemas (`FooEntity`), enums, the DB registry and converters, provider services and their errors | imports from `data`, `domain`, `api` |
| `data` | repositories — Firestore I/O only (`data` rule) | business rules, `HttpsError`, ApiModels |
| `domain` | use cases, helpers, pure logic, domain errors, by feature | handlers, ApiModels, `HttpsError`, transport or auth checks, secrets |
| `api` | callables, HTTP, triggers, schedules, tasks, middleware, request schemas, `FooApiModel`s, options and params | business rules, transactions, provider services |

- A handler may call one repository directly for a single non-transactional read or write with no rule behind it. Two or more repositories, any rule, or any transaction → a use case.
- From `core`, handlers import only types, enums, and schemas; use cases call provider services.

## Domain model

- One name per concept along the path: `FooEntity`, collection `foos`, `FooRepository`, `createFooUseCase`, callable `createFoo`, `FooApiModel`, the client's `Foo`.
- Entities are immutable Zod-inferred data in `core`, validated by the converter; their behavior is pure functions in the owning feature (`canPublishFoo(foo)`), never in repositories, converters, or handlers.
- Domain errors are a closed set (`backend-api` rule → Shape and errors): `DomainError` subclasses per feature (`FooNotFoundError`, `FooAlreadyPublishedError`) carrying a `code` from one union type. Provider errors (`FooServiceError` with its own code union) sit beside the provider in `core`.

## Units of work

- A use case (`createFooUseCase(params)` under the feature's domain folder) is one unit of work: it checks its preconditions, owns its transaction (`db.runTransaction` through the registry — the `data` rule → Transactions), and returns entities or a domain result (dates as `Timestamp`), never a `FooApiModel`.
- Levels: handler, use case, repository, service. Shared work moves down into a domain helper, a `fooWithinTransaction(transaction, params)` helper, or a `core` service — never into a repository; a repository never calls a service or another repository.
- **Throwing reads are domain helpers**: `getFooOrThrow(params, transaction?)` wraps `FooRepository.getById` (`null`) and throws `FooNotFoundError`; it lives in the owning feature, others import it.
- A feature helper never imports another feature's repository; the use case that owns the transaction loads the other entity and calls that feature's `*WithinTransaction` helper.
- No parallel `helpers/`, `shared/`, or `services/` folders under `domain` (exact folder: repository rules).

## API boundary

- Handler shape: `onCall` through the project's callable middleware — auth, a `z.strictObject` request schema (request type `z.infer` of it), the use case (or the one repository), `fooApiModelFromEntity`. How-to: `writing-cloud-functions`; triggers, schedules, tasks: `writing-background-functions`.
- **Wire names**: callables are verb + noun — `getFoo`, `listFoos`, `createFoo`, `updateFoo`, `deleteFoo`; client API methods mirror them exactly. JSON keys are camelCase.
- **ApiModels are Zod schemas**: `FooApiModelSchema` with `type FooApiModel = z.infer<typeof FooApiModelSchema>` and `fooApiModelFromEntity(entity, …)` in the ApiModel file — the only `FooEntity` → `FooApiModel` mapping; tests parse responses with the same schema. No `*ModelMapper` classes. Dates are ISO 8601 UTC strings (`toISOString()`), never a `Timestamp` / `Date`.
- **Paged lists** (`backend-api` rule → Shape and errors): request `{cursor?: string, limit: number}` (1..50, default 20), response `{items: FooApiModel[], nextCursor: string | null}`. The cursor is the last item's document id, resolved to a snapshot for `startAfter`.
- **`HttpsError` exists only in `api`**; the callable middleware maps once: `HttpsError` as is (a request `ZodError` → `invalid-argument`), `DomainError` by code in one exhaustive `switch` (`invalid-input` → `invalid-argument`, `forbidden` → `permission-denied`, `conflict` → `already-exists`, `precondition-failed` → `failed-precondition`, `quota-exceeded` → `resource-exhausted`, same names otherwise), anything else → `internal` with a generic message and the cause logged. Template: `scaffolding-functions-backend`.
- A plain `Error` only for unclassified internal failures nobody branches on (a corrupt snapshot), surfacing as `internal`. Wrap once, at the helper that owns the read.
- A tenant resource the caller may not see is `not-found`, never `permission-denied` (`backend-security` rule → Authorization); `forbidden` is for actions on a resource the caller can see.

## Provider services

- A provider integration is an `interface FooService` in `core/{foo}/`, implemented per provider (`AcmeFooService`, never `ProdFooService`), reached through `fooServiceFactory.ts`, the seam tests swap (emulator only); doubles are `MockFooService`. Template: `scaffolding-functions-backend`.
- Secret values are read in the handler (`FOO_API_KEY.value()`) and passed down as params.

## Firebase security

On top of the `backend-security` rule:

- Never return Admin SDK objects, snapshots, or raw entities; responses are ApiModels.
- Callables authenticate through middleware by default (Firebase Auth); a public endpoint is intentional, validated, and least-privilege. Tenant and role checks run in the use case on the loaded document.
- Admin and internal access via custom claims or a verified secret header — never hardcoded UID lists.
- Secrets: `defineSecret` in function options, read in the handler, never in `.env*` files. Client access to Firestore and Storage, App Check, CORS: `securing-firebase-data`.

## Client API compatibility

Rules: `backend-api` rule → Contract first. Clients also depend on function names and regions: a breaking change ships as `fooV2` beside the old function; a new request field reaches the backend before any client sends it (schemas are strict); an export is removed or renamed only after every client moved off it (deploy deletes missing functions). Grep every client (`CLAUDE.md` → Related repositories) first.
