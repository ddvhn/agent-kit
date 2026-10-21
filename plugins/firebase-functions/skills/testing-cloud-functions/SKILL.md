---
name: testing-cloud-functions
description: Write, run, and debug Firebase Functions tests — pure domain unit tests, repository and migrator suites against the Firestore emulator, callable/HTTP/trigger/task integration suites against the full emulator stack — with entity builders and provider mocks. Use when adding or changing tests, covering changed behavior, running suites, or changing test infrastructure and provider mocks.
---

# Testing

Policy (which suite owns what, emulators only, mocks, concurrency, coverage): the stack `testing` rule. This skill is the how-to. Project specifics — test roots, helper names (emulator reset, auth token, callable client), the provider mock list, the mock composition root, coverage gates, commands — are in `CLAUDE.md` → Verification and the repository's rules; read them first. Building the harness from nothing: `scaffolding-functions-backend` → Test harness.

## Authoring workflow (tests first)

1. Read the target (or the spec, for new behavior) and the neighboring tests.
2. Build a **state machine** from the implementation path (handler → use case → repositories / transactions / storage / side effects), not from the public schema alone: start states, every success and failure transition, terminal outcomes, persisted effects.
3. Write **one test per transition**. At each state cover meaningful edges and, for every validated number, string length, or array length, the schema **min and max** (or enum extremes). Multi-step flows assert every intermediate persisted state, not only the final response. If business intent is ambiguous, ask before inventing product rules.
4. Run it and see it fail for the right reason; then implement.
5. `beforeEach`: reset emulator state. Seed only the entities the test needs, inline, through the typed registry and builders (below).
6. Unit: exercise the real repository API against emulator data. A narrow SDK spy only for an otherwise unreachable defensive branch.
7. Integration: call through the Functions emulator with a real emulator Auth token and the project's callable client. Never invoke handlers or use cases directly.
8. Assert observable behavior: response shape, mapped error code, persisted data, idempotency on a second identical call.
9. Run the narrowest suite; then lint and build if production code changed.

## Builders, not fixture files

- A **builder** is a function in the test mocks folder that returns a complete, valid latest entity and takes overrides: `mockFooEntity({status: "draft"})` → `FooEntity`. Tests state only the fields they assert; the builder fills the rest. One builder per entity, extended when the schema grows, named for the returned type.
- A **fixture file** is a static dataset per entity or per test (`foo.fixture.json`, a shared seeded database). Do not add them: they drift from the schema and hide which fields a test depends on. Seed inline: `await db.foos.doc(foo.id).set(mockFooEntity({...}))`.
- A versioned-entity migrator test seeds **raw** old-version documents on purpose (bypassing the converter) — that is the one place for literal document data.

## Background functions

- Firestore triggers: write the source document through the registry, then poll (`waitUntil`) for the persisted effect; assert a second delivery of the same event changes nothing.
- Task handlers: enqueue through the use case. `onTaskDispatched` queues run on the Cloud Tasks emulator; a raw Cloud Tasks client is swapped for a mock queue service that delivers serially to the local Functions emulator. Poll for the effect; no public tunnels; no real provider keys.
- Schedules: test the use case behind the schedule through a trigger the emulator can fire (the project's internal task or HTTP entry point), not by waiting for the clock.

## Coverage checklists

### Integration

- Every transition: auth reject, Zod reject, missing / foreign entity, permission deny, empty result, idempotent retry, cleanup.
- Inputs: optional vs required, empty / null / whitespace, invalid enum or union members, pagination cursors, schema bounds.
- Response compatibility: function name, region, request / response shape, error codes.

### Repository unit

- Each method: found / missing / unreadable; filter, order, `limit`, `startAfter`; transactional and non-transactional paths.
- Bounds: limits, date / status / optional-field edges, empty result sets, `_version` persistence (when versioned).
- Files under a coverage gate stay at the threshold; gate a new repository when its neighbors are gated.

### Migrators — exhaustive, not "fewest"

When the project versions entities:

- Each start version `v1 … latest-1` → latest schema parse; latest identity (a complete latest doc).
- Entities with draft / published sides: each hop with the published side empty **and** present.
- Missing `_version` (treated as v1) for every entity whose schema has `_version`, on every side; nested versioned objects at each parent version that embeds them.
- **Every pre-parse repair**, including a latest `_version` whose sides omit fields the migrator fills — a converter that `safeParse`s latest first never calls the migrator, so a complete latest fixture does not cover it.
- Assert repairs through the production read path (the converter's `fromFirestore` or a repository read of a raw-seeded doc), not only `fooMigrator()`.
- The converter: latest fast path, migrate path, failure throw.
- Draft / published round-trips: seed an old version with both sides → full-entity update of one side → re-fetch: the other side is readable and migrated. Partial-update tests assert the stored `_version` is unchanged.

## Placement of test-only code

- Domain-agnostic infrastructure (callable client, auth token, assertions, polling, emulator reset and safety) in the shared test utils folder.
- Provider mocks (`MockFooService`) in one mocks area, mirroring `core`; entity builders per feature.
- One composition root (`mockAssembly.ts`) registers every provider mock through the factories (`setFooService(new MockFooService())`, `setFooHelper(mockFooHelper)`).
- No new top-level test roots (`helpers/`, `setup/`, `fakes/`, …) beyond those the repository's rules list.

## Provider mock wiring

- Production code loads the mock composition root only when the test-mode gate says so (the project's test-mode helper, not ad-hoc `process.env` checks), and only inside the emulator.
- The Functions emulator runs the compiled build: mocks it needs are compiled into the emulator build (`npm run build:emulator`); the test runner can import mocks directly.
- Production builds and deploys exclude test code and mocks (`firebase.json` → `functions.ignore`).
- A mock exposes hooks for failure and delay (`failWith("rate-limit")`, `delayMs`) so tests reach error branches and mid-run races without a real provider.

## Running

Commands: `CLAUDE.md` → Verification. The narrowest suite while iterating; both suites only when the change crosses both boundaries. Read totals from the runner's final summary and report failures exactly.

## Before reporting done

- [ ] Tests written first and seen failing
- [ ] Hosts resolve only to localhost; emulator state resets before every test
- [ ] Provider mocks match the policy (no paid or remote calls)
- [ ] Test-only code stays in the test tree
- [ ] Targeted command passes; failures reported exactly
