---
description: Backend API — contract-first OpenAPI with codegen, draft → stable with 501, additive changes inside a version, one error shape with stable codes, 404 for forbidden, cursor pagination, idempotency keys, acting-tenant header when users span tenants
---

# Backend API

How-to: `designing-api-contracts`; client sync: `designing-client-sync`. The contract path and the project's names: `CLAUDE.md` → Specs.

## Contract first

- One OpenAPI file is the single source for server and clients: change the contract, regenerate, implement the generated interface. No hand-written request or response types; generated code committed and checked for staleness.
- Every request is validated against the contract before a handler runs, unknown fields refused; server-computed fields never appear in request schemas.
- Each operation carries a milestone and a status: `draft` answers `501 notImplemented`; `stable` is implemented, tested, and only grows.
- Inside `/v1` changes are additive only (optional fields, operations, enum values clients map to `unknown`); anything else is a new version with an ADR.

## Shape and errors

- JSON, plural kebab-case paths, camelCase fields, opaque string ids, ISO 8601 UTC instants, money as integer minor units + currency.
- One error shape `{ "error": { "code", "message", "requestId", "fields"? } }`; codes stable and namespaced, mapped from typed domain errors in one place; clients branch on `code` only; `500` hides internals.
- A forbidden resource and a missing one both return `404`.
- Lists are cursor-paginated with a capped `limit`; the cursor encodes position only.

## Retries

- Writes a client may retry take an `Idempotency-Key`, scoped to the user, the acting tenant, and the route: the first successful result is replayed and a refused call is evaluated again; the same key with a different payload → `422`; still running → a bounded wait, then `409` with `Retry-After`; a failed call never leaves the key stuck.
- State transitions are guarded in the database (conditional update or row lock).

## Tenant context

- When one user can belong to several tenants, tenant operations name the acting membership in one header; the server checks it is the caller's own active membership (missing → `400`, foreign or inactive → `404`) and scopes the transaction to its tenant.
- When clients keep local data or work offline, they sync by hint → delta (`designing-client-sync`); otherwise plain reads.
- Over a rate limit → `429` with `Retry-After`.
