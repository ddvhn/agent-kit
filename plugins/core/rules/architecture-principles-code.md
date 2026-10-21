---
description: Architecture principles for code — SOLID, DRY, KISS, YAGNI, separation of concerns, coupling and cohesion, state, errors, security, and contracts, each as what it means in practice for an agent, its limit, and how conflicts between them resolve
---

# Architecture principles for code

The classic engineering principles, as practice. Each line says what to do and where it stops. Where principles pull apart, the conflict rules at the end decide; `minimal-change` and `architecture-principles` stay in force.

## SOLID

- **Single responsibility**: a unit has one reason to change (one use case, one repository per aggregate, one widget per concern). Limit: not one function per file; split when two reasons to change actually appear.
- **Open–closed**: add behavior by adding a case, implementation, or handler next to the existing ones, not by editing a stable shared core. Limit: no plugin points for variants nobody asked for.
- **Liskov substitution**: an implementation accepts at least the same inputs (no stricter preconditions), gives no weaker postconditions, and throws no error kinds the contract does not declare; fakes behave like the real adapter. Limit: an override that throws "not supported" means the abstraction is wrong; fix the abstraction.
- **Interface segregation**: a consumer depends only on the methods it calls; split a fat interface along its callers. Limit: no one-method interface per call site by reflex.
- **Dependency inversion**: inner layers own the interfaces, outer layers implement them (`architecture-principles` → Clean Architecture). Limit: SOLID never justifies a speculative interface; an interface needs a boundary the architecture requires or a second implementation (a test fake counts only at an I/O boundary).

## Simplicity

- **KISS**: the simplest code that meets the criteria; boring over clever. Limit: not simpler than correct (validation, error handling, security stay).
- **YAGNI**: build what this task needs (`minimal-change`); no options, flags, or generality for a future caller. Limit: what the architecture requires (contracts, layers) is not speculation.
- **DRY**: one source of truth for each piece of knowledge — a rule, a constant, a schema, a mapping. Knowledge the change needs is reused, never copied; existing duplication outside the touched lines is a follow-up. Similar-looking code is not knowledge: it waits for the third occurrence (rule of three).
- **Convention over configuration**: where the stack or the project has a convention (layout, naming, generators), follow it instead of configuring around it. Limit: a convention never overrides a rule.
- **Principle of least astonishment**: names say what the code does; a function does what its name says and nothing else; follow the neighbors' patterns.
- **Explicit over implicit**: dependencies injected (`architecture-principles` → Clean Architecture), data through parameters, effects visible in the signature; no hidden globals, magic strings, or reliance on call order.

## Structure

- **Separation of concerns**: transport, storage, domain rules, and presentation in their own units and layers; a unit that both decides and does I/O is split (functional core below).
- **High cohesion, low coupling**: what changes together lives together (feature folders); modules meet through small public contracts, never through each other's internals.
- **Composition over inheritance**: build behavior from small injected parts; inherit only from framework base classes the stack requires. Limit: no deep hierarchies for code reuse.
- **Law of Demeter**: talk to direct collaborators; `a.b().c().d()` across units means a missing method on `a` or a parameter that should be passed in. Limit: fluent builders and value-object chains are fine.
- **Tell, don't ask**: ask the object that owns the data to act (`order.cancel()`), instead of reading its state and deciding outside. Limit: read models and UI mapping may read freely.
- **Command–query separation**: a method either changes state or returns data, not both. Limit: atomic operations whose result is the point (`insertAndGetId`, a compare-and-set) are allowed and named so.

## State and data

- **Functional core, imperative shell**: a non-trivial decision (transitions, deadlines, prices, ordering) moves into a pure function of its inputs and `now`; orchestration with simple guards stays in the use case; I/O happens around them. Inject the clock; domain code never reads the wall clock.
- **Immutability and explicit state machines**: entities and value objects never change after creation; status changes go only through one transition table, and every other transition is refused.
- **Parse, don't validate**: input becomes domain types at the edge, validated when built; inside the domain a value is always valid, never a raw string.
- **Make illegal states unrepresentable**: sealed types and required fields instead of nullable combinations and boolean flags that can contradict each other.
- **Idempotency**: every operation a client, queue, or job may retry carries an idempotency key or is naturally idempotent; a retry returns the first result and creates nothing new.

## Errors

- **Fail fast**: check preconditions at the boundary and stop with a typed error; never continue with a half-valid value.
- **Never swallow errors**: no empty or broad catch, no logged-and-ignored failure, no fallback that hides a failed call. Catch only to map to a typed error, recover deliberately, or report.

## Security

- **Least privilege**: each role, token, service account, and agent gets only the access it needs, scoped to the tenant and resource.
- **Defense in depth**: check authorization in the use case even when a router guard or the UI already hides the action; the storage layer scopes queries too, so a forgotten check returns nothing. A forbidden resource and a missing one get the same not-found answer, so existence never leaks across tenants.
- **Secure by default**: closed until opened — private storage, deny-by-default rules, collecting or sharing personal data beyond what the feature needs is opt-in; secrets never in code or logs.

## Contracts

- **Postel's law does not apply to internal contracts**: between our own repositories, modules, and layers be strict in what you send and accept. A server rejects an unknown or malformed value in a request with a typed error. The only tolerance is a client reading a newer server: it maps unknown enum values to `unknown` and ignores additive fields.
- **Bounded by default**: lists are paginated (cursor by default), never unbounded; errors carry a stable machine code that clients branch on, never the message.

## When principles conflict

| Conflict | Resolution |
| --- | --- |
| DRY vs `minimal-change` ("one call site → do not extract") | Duplicate knowledge is removed now; incidental code similarity waits for the third occurrence. |
| SOLID vs YAGNI | No interface, abstraction, or extension point without a required boundary or a second real implementation. |
| Boy-scout rule vs `minimal-change` | Leave the code you touch cleaner, but only within the lines you change; anything wider is a follow-up, not part of the diff. |
| Open–closed vs a root-cause fix | Fix the shared function once (`minimal-change`), even when it means editing stable code. |
| Tell, don't ask vs separation of concerns | Behavior that belongs to the entity goes on it; I/O and orchestration stay in use cases. |
| Convention vs a kit or project rule | The rule wins; record the exception in the project's rules. |
