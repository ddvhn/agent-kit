---
description: The architecture principles every kit project follows — spec-driven, contract-first, Clean Architecture, Domain-Driven Design scaled to size, Test-Driven Development, offline-first clients, cross-cutting load, security, and compliance — and what each requires in practice (the engineering principles for code: architecture-principles-code)
---

# Architecture principles

These principles shape every project that uses the kit. Stack rules apply them; when a choice is unclear, pick the option that serves them, in this order.

## Spec-driven

- Every task names the requirements it implements: requirement IDs and acceptance criteria from the project's spec (`CLAUDE.md` → Specs). Code follows the criteria, not a guess.
- A task without acceptance criteria gets them before work starts; the criteria become test cases.

## Contract-first

- An API between repositories (OpenAPI or an equivalent schema) is the single source for both sides. Models, clients, and server interfaces are generated from it; never hand-write request or response types next to generated ones.
- Changes inside a version are additive only; a breaking change is a new version. The client never invents an API shape: it builds against the operation in the merged contract, a draft one included (mocked from the contract's fixtures until the server implements it, behind a flag until then).

## Clean Architecture

- Dependencies point inward, to the domain. The domain is pure (no framework, no SDK, no transport, no storage); outer layers adapt to it: data stores and services, transport handlers, UI.
- Each layer talks to the next one through contracts the inner layer owns (repository interfaces, use cases). Implementations are hidden behind them and chosen in one composition root (the app's `main`, the backend's exports and DI).
- Units of one level never depend on each other (`same-level-dependencies`).
- **One use case, one job, one type.** Each use case is its own file and type, named verb-first after the action (`CreateFoo`, `ObserveFooList`), with one public entry (`call` / `run` / `execute`, per the stack) taking its own input type and returning its own result. It holds only the ports and repositories that action needs, set once at construction, and no state between calls; no flag switches it between two jobs (two jobs are two use cases), and no module-wide service has a method per action. Work two use cases share is a domain function, a calculator, or a repository method, never a third use case.
- Constructor injection everywhere; only the composition root and the DI files touch the container.

## Domain-Driven Design

Scaled to size: full DDD where the domain is rich; DDD-lite for small services — bounded contexts as modules, the ubiquitous language, aggregates guarding their invariants, value objects. No event sourcing, CQRS, or generic repositories until a recorded need (`recording-decisions`).

- **Ubiquitous language**: a concept has one name everywhere — specs, backend, client, tests, UI copy keys. Do not rename a domain concept per layer (`Route` is a `Route`, not `Trip` in the UI and `Path` in the API).
- **Model the domain in the domain layer**: entities and value objects (immutable, parsed at the edge: `architecture-principles-code` → State and data) carry their own behavior (derived values, state transitions) where it belongs to them. Rules and calculations live in domain (entities, domain services / calculators, use cases) — never in data, transport, or UI.
- **Features are bounded contexts**: each feature owns its models, contracts, and use cases; another feature reaches it only through its public contracts.
- Domain errors are part of the model: a sealed hierarchy of domain exceptions, not transport codes or strings.

## Test-Driven Development

- Behavior changes start with a failing test, adversarial cases first and the happy path last: a bug starts with a test that reproduces it; a feature starts with tests derived from its acceptance criteria. Then the minimum code to pass, then refactor with the tests green.
- Test at the layer that owns the behavior: domain logic by unit tests; stores and repositories by round-trips against real local storage or emulators with the network mocked; user flows by integration / E2E tests with only I/O replaced. Where use cases are tested (unit tests with repository doubles, or emulator integration tests when they own database transactions) is set by the stack's `testing` rule.
- One behavior has one owning suite; a higher suite covers the path through the system and does not repeat a lower suite's edge cases.
- **Edge cases on purpose**: each test file goes through this checklist and covers every item that applies: empty, one, many; zero, negative, maximum, and maximum + 1; missing, null, and unknown enum values; Unicode and very long text; time boundaries (just before, exactly at, just after; midnight, DST days, another zone; the clock injected, never the wall clock); repeated and concurrent calls and retries (same idempotency key); each role and permission combination. Table-driven tests for cross products of inputs that matter, property-based tests for invariants; every error code an operation declares has a test that provokes it.
- Every I/O boundary has a double; test data uses fake names and reserved number ranges, never real people's data.
- A test that cannot fail when the logic breaks is not a test. Never weaken, skip, or delete a test to get green.
- `delivering-changes` runs this per subtask (tests first, confirm they fail for the right reason).

## Engineering principles

SOLID, DRY, KISS, YAGNI, and the other classic principles for code, with their limits and how conflicts between them resolve: `architecture-principles-code`.

## Offline-first (client apps)

- The local database is the source of truth for what the user sees; the network refreshes it. A screen paints cached data first and refreshes in the background.
- Offline with cached data is a normal state, not an error; offline without data is an explicit empty / offline state.
- A failed refresh keeps the data on screen and reports the failure non-destructively.
- Writes go to the backend (it owns business invariants); the local copy is updated from the server's response. A queued offline write needs an explicit sync design (ADR), never an ad-hoc retry.

## Cross-cutting concerns

Each is one line in every plan and in the PR sections the project requires (`delivery` rule → Pull requests; what goes in Load and Compliance: `shipping-feature-branch` → PR description). A performance trade-off or an unclear legal case is agreed with the user before it is implemented:

- **Performance and capacity**: a "Load" note when a change touches requests, queries, payloads, or background work — what it costs and where it breaks first.
- **Security first**: authentication, authorization, input at trust boundaries, secrets, personal data in logs.
- **Legal and compliance** per market, when `CLAUDE.md` defines markets: what personal data, where it goes, how long it stays.

## Pragmatism

- Use cases exist for business logic and orchestration. A plain CRUD call with no rule behind it may go straight from the presentation unit to the repository contract; the stack rule says how.
- Minimal change still applies: these principles decide *where* code goes, not that more code should be written.
