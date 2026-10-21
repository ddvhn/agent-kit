---
description: Backend test policy — owning suite per change, the real database engine, contract validation of every response, every declared error code, census tests, idempotency and races with real transactions, coverage gate as the project's choice, paid services never called and outbound network blocked
---

# Backend testing

Applies core `architecture-principles` → Test-Driven Development. Patterns, the edge-case checklist, live smoke, load and chaos: `testing-backends`; stack how-to: Go `testing-go-backends`. Commands and the coverage gate: `CLAUDE.md` → Verification.

## Suites

| Change | Suite |
| --- | --- |
| Entities, value objects, policies | domain unit, table-driven, no I/O |
| Use cases | unit with fakes, or integration when the stack says so |
| Repositories, migrations, constraints, RLS | integration on the real engine, a fresh database per test or package, as the application role |
| Handlers, auth, error codes, tenancy, idempotency | API tests through the HTTP layer |
| Jobs | job tests with a steppable clock |

- Persistence tests use the real engine (the same Postgres major, or an adopted platform's official emulator); never SQLite or in-memory stand-ins.

## Must cover

- Every API response is validated against the contract; an undocumented status or an extra field fails.
- Every declared error code has a test that provokes it.
- Route census: every route has a policy and an RBAC test. When multi-tenant, a cross-tenant census: every read with another tenant's ids → `404`.
- Retried writes: same key twice, concurrently, and after a timeout → one effect. Concurrent actions on one aggregate run real transactions; the loser gets a stable code.
- Every behavior has a test that fails when it breaks. A coverage gate is the project's choice (recommended: 100% of handwritten code with a closed exclusion list); coverage never drops.

## Doubles

- A test run never costs money: every paid provider is a fake in every suite; outbound network is blocked; real adapters refuse to start without an explicit live flag.
- Time is injected; test data uses reserved fake identifiers; logs of the run are scanned for personal data.

## Flaky tests

- A test failing without a code change is fixed or deleted within 2 working days; never skipped to get green.
