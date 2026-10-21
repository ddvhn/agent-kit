---
description: Firebase as an adopted platform — which backend-rule defaults it overrides and what still applies
paths:
  - "functions/**"
  - "firebase.json"
---

# Firebase platform

Firebase is adopted on purpose (`backend-architecture` rule → Adopting a platform); the project's ADR records why and how it would leave. Only what is listed here replaces a backend default; a part of the backend rules marked self-hosted or Postgres does not apply.

Overrides:

- **Vendor independence**: the platform is Google's; other providers still sit behind services.
- **Data**: Firestore is the system of record. No Row-Level Security, SQL migrations, composite keys, or Postgres job queue: tenant isolation is server-side checks plus deny-all client rules (`securing-firebase-data`), shape changes are versioned entities (the `data` rule), background work is triggers and Cloud Tasks (`writing-background-functions`).
- **Contract and shapes**: callable names, `z.strictObject` request schemas, and ApiModel schemas are the contract (the `architecture` rule → API boundary), not OpenAPI, paths, or HTTP statuses. The acting-tenant header becomes a request field, and delta sync exists only if the project builds it.
- **Authentication**: Firebase Auth issues, refreshes, and revokes tokens; the backend's opaque refresh-token rotation and HttpOnly cookie rules do not apply. Callables verify the ID token through middleware; custom claims carry admin roles. Logout-all maps to `revokeRefreshTokens`; sensitive and step-up actions verify with `checkRevoked: true` and require a recent `auth_time`.
- **Rate limits and abuse**: App Check, Firebase / Cloud quotas, and per-user counters in Firestore instead of `429` with `Retry-After` from our own limiter.
- **Operations**: no Docker image, OpenTofu, self-hosted monitoring, hot standby, WAL shipping, or migrations-before-code. Deploys are `firebase deploy`; backups are managed Firestore exports or point-in-time recovery, restored to another project in a drill; monitoring is Cloud Monitoring and an uptime check.
- **Layout**: layer folders with features inside, not feature-first modules; a handler may call one repository directly for a plain read or write with no rule (the `architecture` rule → Layers).
- **Errors**: an action refused on a resource the caller can see is `permission-denied`; an invisible one stays `not-found`.
- **No dependency inversion**: `domain` imports concrete repositories and the `db` registry, and Firestore types (`Timestamp`, `Transaction`) are part of the model; the emulator plays the database. Seams are module factories (the `architecture` rule → Provider services).

Still applies: stable error codes, cursor pagination, idempotent retried writes, per-action authorization, no personal data in logs, retention, UTC instants, the stages of the `backend-operations` rule, the Load and Compliance sections, and the test policy with the emulators as the real engine. The coverage gate is the project's choice (`CLAUDE.md`).
