---
description: Main architecture rule — units of the same level never inject or call each other; such dependencies are resolved one level up (the caller orchestrates) or one level down (shared work moves into a lower unit)
---

# Same-level dependencies

**Main rule: units of the same level never depend on each other.** Every dependency goes to a lower level or comes from a higher one, never sideways. A use case never injects or calls another use case. A repository never injects or calls another repository. The same holds for every level: blocs, screens, services, data sources and stores, API clients, adapters, calculators, transport handlers, job workers; an aggregate never changes another aggregate. It holds between features and modules as well as inside one. No exceptions for "just one call", a shared helper method on a peer, or a peer passed in as a callback.

When one unit needs what a peer has, resolve it in exactly one of two ways:

| Resolve | When | How |
| --- | --- | --- |
| **One level up** — the caller orchestrates | The peers are separate steps of a larger flow; the order or combination is the caller's business | The unit above takes both peers and sequences them: a use case calls two repositories; a transport handler calls two use cases; a page wires two blocs (a listener on one triggers the other). |
| **One level down** — shared work moves into a lower unit | Both peers need the same capability or data | Extract it into a unit below both peers: a domain helper or calculator both use cases call; a `*WithinTransaction` helper both use cases call; on a client, a data store or service both repositories use, or a repository stream both blocs observe through their own use cases. Where a stack restricts a level (for example backend repositories that may only talk to the database), the stack rule names the allowed lower units. |

- Pick by meaning: if the shared piece is a rule or a capability, push it down; if it is a sequence of steps, lift it up. Never create a "manager" peer that injects the others — that is the same violation one name later.
- A unit that owns a unit of work (a transaction, a lock, preconditions) keeps it. Lifting orchestration up must not open a second unit of work inside the first; pushing work down must not move the ownership — the lower helper runs inside the caller's transaction and never opens its own.
- Moving down must not break layering: domain rules never move into data, transport or auth never moves into domain. If neither direction fits, stop and ask.
- **Between modules or features the graph is one-way and acyclic**, from higher-level contexts to lower ones, and only through the lower one's public interface (its root package or barrel), never its internals. The reverse direction is a domain event (an outbox on a backend), never a call back. A new arrow between modules is named in the PR.
- **Allowed exceptions, and only these:** a module's value objects, ids, and enums are its shared vocabulary, used by all its units (and by other modules through its public interface); the composition root sees every layer and module; a module's public interface assembles its own layers; shared UI or support packages sit below the features by design; tests build any unit of their own module with fakes.
- **Checked by machine where possible**: the package graph, an import linter, or an import-check script refuses another module's internals and imports between same-level folders; the project names the tool. What an import check cannot see (a constructor taking a same-level type) is a review item.
- Existing violations are not copied. Leave them unless the task touches them; then fix them the same way, or ask when the fix grows beyond the task.
- The stack rules name the levels and give examples (Flutter `architecture` → Layers / Use cases; Firebase Functions `architecture` → Units of work; backends `backend-architecture` → Use cases).
