---
description: Firebase Functions test policy — which suite owns which behavior, emulators only, provider mocks, emulator vs production concurrency, coverage, test-code isolation
paths:
  - "functions/**"
---

# Testing (Firebase Functions)

Firebase realization of the `backend-testing` rule: a behavior change starts with a failing test in the suite that owns it. How-to: `testing-cloud-functions`; a new harness: `scaffolding-functions-backend`; commands: `CLAUDE.md` → Verification.

## Suites

| Behavior | Suite |
| --- | --- |
| Pure domain functions (transitions, calculators, validators) | unit, no emulator |
| Repositories; migrators and converters when entities are versioned | unit × Firestore emulator |
| Callables, HTTP, triggers, task handlers — and the use cases behind them | integration × full emulator stack |
| Firestore and Storage security rules | `test:rules` × Firestore + Storage emulators, client SDK contexts (`securing-firebase-data`) |

- **Use cases bound to Firestore transactions are covered by emulator integration tests**, not unit tests with repository doubles; their pure rules move into domain functions with unit tests.
- Integration tests call through the Functions emulator with an emulator Auth token — never a handler or use case imported directly.

## Emulators only

- Firebase is real only via localhost emulators (Auth, Firestore, Functions, Storage, Pub/Sub, Cloud Tasks). Never production or staging, never in-memory stand-ins. The emulator project id is a label (prefer a `demo-*` id, which has no cloud resources); hosts stay on localhost, and a test setup asserts both.
- Paid and third-party providers are mocked through the service factories (`backend-testing` rule → Doubles); the project's provider list: the repository's rules.
- Idempotent and repeatable locally: reset emulator state before each test; no imported emulator state.

## Emulator ≠ production concurrency

The emulator serializes requests; production runs concurrently. A green suite does not prove a path race-free: design for production (transactions, idempotency, conflicts) and test races with provider hooks and synthetic delays.

## Coverage

Tests derive from the state machine (every transition, edge, schema min / max) and each fails if its logic breaks. The gate is the project's (`backend-testing` rule → Must cover); migrator suites cover every version hop.

## Test code isolation

- Test code stays in the test tree. Production source never imports test code, except the one documented test-mode gate that loads the mock composition root in the emulator.
- The Functions emulator runs the compiled build, so test-runner module mocks (`vi.mock`, `jest.mock`) never reach code it runs. Swap providers through the service factories (`setFooService`) from the mock composition root.
