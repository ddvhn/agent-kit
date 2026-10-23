---
name: testing-backends
description: Stack-independent backend test design — the edge-case checklist, table-driven and property-based tests, fuzzing and mutation testing, contract validation and error-code coverage, route and cross-tenant census, idempotency and race tests, coverage gates with a closed exclusion list, fakes for paid providers and blocked network, the manual live smoke with a spend cap, and load and chaos runs by stage. Use when planning what to test for a backend change, setting up a backend test policy or coverage gate, writing a live smoke, or planning load and chaos tests. Go how-to: testing-go-backends.
---

# Testing backends

Policy: the `backend-testing` rule. Stack how-to: Go `testing-go-backends`; Firebase `testing-cloud-functions`. The project's gate, review zones, and stage: `CLAUDE.md`.

## Edge-case checklist

Each test file goes through it and covers what applies to the code under test:

- empty, one, many;
- zero, negative, maximum, maximum + 1 (amounts up to integer limits, list sizes, string lengths, file counts);
- missing, null, unknown enum values;
- Unicode: non-Latin scripts, diacritics, emoji, very long text;
- time: deadline − 1 s / exactly / + 1 s, midnight, DST days in a zone with DST and a zone without, month and year end, leap day, a client in another zone;
- repeated and concurrent calls, retries after timeouts;
- permissions: role × own / foreign scope × own / foreign tenant × active / dismissed.

Adversarial cases first, the happy path last; each test named after the rule it protects (requirement id when there is one).

## Techniques

- **Table-driven** over the cross product of the inputs that matter (status × actor × timer state).
- **Property-based** for invariants: balance = sum of entries, every non-terminal state reaches a terminal one, ordering is total and stable, encode ∘ decode = identity.
- **Fuzzing** for every handwritten parser and decoder the contract validation does not cover (cursors, signed payloads, money, ids, instants).
- **Mutation testing** later, on money, state machines, and time; a surviving mutant is a missing test.

## Contract and census

- The API test harness validates every response against the contract with a copy of the spec whose response objects forbid extra properties, so hidden fields stay hidden.
- Contract fixtures (`designing-api-contracts`, step 7): every fixture validates against its operation's response schema, and every client-facing operation has them.
- One test per declared error code, provoked through real prior calls for state-based codes; `501` for drafts; a test fails when a stable operation has no handler.
- Route census: walk the router or the spec; each operation needs a policy and an entry in the RBAC table (allowed role + own scope succeeds; foreign scope, foreign tenant, insufficient role, dismissed member refused).
- Cross-tenant census (multi-tenant products): tenants A and B; every read, list, delta, export, and signed link with B's ids as A → `404`. Under the application role: no tenant context → no rows; A's context → no B rows; a reference to B's row fails the composite key; append-only tables refuse `UPDATE` / `DELETE`.

## Retries and races

- Same idempotency key twice in a row, twice concurrently, after a timeout of the first call → one row, one side effect; a different payload → `422`; a refused call retried → evaluated again.
- Two deciders on one item, a write racing a timer, a write racing a period close: real transactions, one winner, a stable code for the loser.
- Jobs: a second delivery changes nothing; a job for an item that changed since scheduling does nothing.

## Coverage gate

- Recommended: 100% statement coverage of handwritten code over all suites together; a closed exclusion list in one file (generated code, entry-point flag parsing, thin adapters to paid providers whose mapping is tested against stubs), changed only with a reason in the PR. The project decides in `CLAUDE.md`.
- An uncovered line is a missing test or dead code.

## Doubles and data

- Every paid or metered provider (SMS, email, push, chat bots, payments, models, maps, error tracking, cloud storage) is a fake behind its port in every suite, load and chaos included; storage tests use a local S3-compatible server.
- Outbound network blocked in the test process, and provider clients built on the transport the block covers (no client with its own transport); real adapters refuse to start unless a live flag and key are set, and the test binary fails if either is present.
- Fake identifiers from reserved ranges (`+1 555 0100`–`0199`, `example.com`); never real people's data or photos.
- The run's logs are scanned for those identifiers, codes, and tokens.

## Live smoke (manual)

- A small suite behind a build tag or flag proves real providers are wired: one cheap call each (one code to a team number, one push, put / signed get / delete of a tiny object, one model call with the cheapest model and a token cap).
- The smoke package has its own test entry point with the inverse guard: it runs only with the live flag and keys set and only against an API base URL on a committed allowlist file of non-production hosts (not a check of the environment name); the network block of the other suites does not apply to it, and no other package may skip that block.
- By hand only: before a production release and after a provider, key, or region change; never in a hook or schedule. The suite counts calls and stops at its budget; staging keys have provider-side spend limits. The result goes into the release PR.

## Load and chaos (stage 3, one scenario from stage 2)

- Staging runs the release build with real adapters on provider sandboxes or test credentials, never in-process fakes; for load, adapters point at the providers' sandboxes or at a stub provider server through their configured base URL.
- Load scripts in the repository against staging: the peak scenario at the profile ×7 (p95, error rate, queue lag), polling at client intervals, notification bursts within provider limits, `429` never shedding critical writes first, a long soak without memory, connection, or dead-job growth.
- Chaos on staging: kill job workers during a burst (nothing lost or sent twice), stop the primary (failover within target, money sums match), stop one app server under load, a provider returning errors and timeouts (fallback), storage down, a deploy under load (smoke never fails).
