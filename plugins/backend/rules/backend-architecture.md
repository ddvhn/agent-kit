---
description: Backend architecture — modular monolith of feature-first modules (bounded contexts), clean layers inside a module, one use case per action, ports and adapters, a tiny shared kernel, a one-way module graph, outbox, DDD-lite, adopting a platform by ADR
---

# Backend architecture

Applies the core `architecture-principles` and `same-level-dependencies` to any backend. The stack plugin names folders, tools, and the linter; the project's modules, neighbors, and exceptions: `CLAUDE.md` and the repository's rules, which win. Companion rules: `backend-api`, `backend-security`, `backend-data`, `backend-operations`, `backend-testing`.

## Modules

- Start as a modular monolith: one codebase, one database, one deployable with a few processes (API, jobs). Split out a service only for a recorded reason (`recording-decisions`).
- A module is one bounded context named from the ubiquitous language; its folder holds all its layers and one public interface (root package or index). No shared `models` / `services` / `utils`. A stack plugin may fix another layout and say why.
- A module touches only its own tables; other modules' data comes through their public interface or an event.
- Calls between modules go one way through public interfaces, without cycles; the reverse direction is an event. A new arrow is named in the change.

## Layers inside a module

| Layer | Holds | Never |
| --- | --- | --- |
| `domain` | entities, value objects, policies, typed errors, repository and port interfaces | SQL, HTTP, generated API types, SDKs, the system clock |
| `app` | use cases | transport types, another use case, SQL |
| `infra` | repositories, provider adapters | business rules, use cases, other modules' internals |
| drivers (`api`, jobs) | handlers and workers: map types, run one use case | business rules, transactions |

- One composition root wires everything; tests build it with fakes.
- Boundaries are enforced by a linter where the stack allows; review checks the rest.

## Use cases

- One action = one use case = one file and one type named verb-first, one entry point with its own input and output; only the ports it needs; no module-wide service with a method per action.
- The use case owns the transaction and the permission check on the specific resource.
- Shared work moves down (domain function, one repository method) or up (the driver orchestrates), never use case → use case.

## Ports and adapters

- Everything outside the process (database, storage, queue, clock, messaging, payments, models) sits behind an interface owned by the module that needs it, with a fake for tests; SDK types never leave the adapter.
- The shared kernel is plumbing only (db, ids, clock, http, config, generated API, error type); no business rule.

## Events and outbox

- A state change and the events and jobs it causes are written in one transaction (outbox); consumers are idempotent and re-check state. No dual writes to a broker.

## DDD-lite and design

- Use bounded contexts, aggregates guarding invariants, value objects (money, instants, ids, statuses), events. Not without a measured, recorded need: event sourcing, CQRS read stores, generic repositories.
- Functional core: decisions are pure functions of inputs and `now`; I/O around them. Parse, don't validate: input becomes domain types at the edge; unknown values fail loudly. Status changes only through a transition table; value objects immutable. YAGNI (core `minimal-change`).

## Adopting a platform

The backend rules default to a self-hosted stack (Postgres, S3 API, a Docker image). A project or stack plugin may adopt a managed platform by an ADR stating what it overrides and how to leave; the stack plugin lists the overrides (`firebase-functions` → its `platform` rule).
