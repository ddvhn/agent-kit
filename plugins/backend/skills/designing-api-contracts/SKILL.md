---
name: designing-api-contracts
description: Add or change a REST operation contract-first in an OpenAPI file — paths and schemas in the kit conventions, milestone and draft/stable status with 501 for drafts, error codes and the conventions page, cursor pagination, idempotency keys, the acting membership header, breaking-change review, and regenerating server and client code. Use when adding an endpoint, a field, an error code, or an enum value, promoting a draft operation to stable, or reviewing whether an API change is breaking.
---

# Designing API contracts

Policy: the `backend-api` rule. Stack how-to after the contract is written: Go `adding-go-endpoints`; Firebase callables `writing-cloud-functions`. The contract path, the conventions page (for example `docs/api.md`), and the project's extension names: `CLAUDE.md` → Specs.

## Workflow

1. **Name it** from the ubiquitous language: `operationId` verb + noun (`listFoos`, `getFoo`, `createFoo`, `updateFoo`, `archiveFoo`), path plural kebab-case (`/v1/foos/{fooId}`), schema `Foo`, input `FooCreate` / `FooUpdate`, page `FooPage`. Reuse existing components (`Error`, `Money`, cursor parameters) instead of copying them.
2. **Write the operation** in the contract (template below). Mark the milestone and `draft` until the handler and its tests exist.
3. **List every error** the operation can return as a response with the shared `Error` schema, and add new codes to the conventions page (code, status, when). Codes are `module.camelCase` (`foo.alreadyPublished`); generic ones (`validation.invalid`, `notFound`, `auth.unauthorized`, `notImplemented`, `internal`) are shared.
4. **Check compatibility** (below). A breaking change to a released operation is a new version plus an ADR (`recording-decisions`), never an edit.
5. **Regenerate** server and client code (`CLAUDE.md` → Verification) and commit the generated output; the stale-code check must pass.
6. **Tests first** in the stack (API tests per declared code, contract validation of every response), then the handler; flip the status to `stable` in the same change that makes them pass.
7. **Contract fixtures** for every operation a client calls: example responses beside the contract (for example `api/fixtures/<operationId>/<scenario>.json`), one per scenario the client shows (success, empty, maximum, each declared error code). A test validates every fixture against its operation's response schema and fails for a client-facing operation without fixtures. Fixtures change only in the same PR as the contract and travel with it to the client (the client's contract sync).
8. Clients: the client repository regenerates from the merged contract; list the client changes needed in the PR. For a feature with a client, the whole feature contract is its first task PR, with example responses (contract fixtures) for every scenario the client shows, so client work starts on mocks while the backend implements the drafts (`core:shipping-feature-branch` → Backend and client).

## Operation template

```yaml
/v1/foos/{fooId}:
  parameters:
    - $ref: '#/components/parameters/MembershipId'   # tenant operations only
    - { name: fooId, in: path, required: true, schema: { type: string, format: uuid } }
  patch:
    operationId: updateFoo
    x-<project>-milestone: m2
    x-<project>-status: draft
    security: [ { bearerAuth: [] } ]
    parameters:
      - $ref: '#/components/parameters/IdempotencyKey'  # writes a client may retry
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/FooUpdate' }
    responses:
      '200': { description: The updated foo, content: { application/json: { schema: { $ref: '#/components/schemas/Foo' } } } }
      '400': { $ref: '#/components/responses/Error' }
      '401': { $ref: '#/components/responses/Error' }
      '404': { $ref: '#/components/responses/Error' }
      '409': { $ref: '#/components/responses/Error' }  # also: same idempotency key still running, with Retry-After
      '422': { $ref: '#/components/responses/Error' }  # same idempotency key, different payload
      '429': { $ref: '#/components/responses/Error' }  # with a Retry-After header
      '501': { $ref: '#/components/responses/Error' }
```

Schema habits:

- `additionalProperties: false` on request bodies so unknown fields are refused; server-computed fields (status, tenant, timestamps, totals) never appear in request schemas.
- Every string has `maxLength`, every number `minimum` / `maximum`, every array `maxItems`; ids `format: uuid`; instants `format: date-time`; money as the shared `Money` object (`amountMinor` integer `int64`, `currency` pattern `^[A-Z]{3}$`).
- Enums list every known value; document that clients map unknown values to `unknown`.
- Lists: `cursor` and `limit` (default and maximum from `CLAUDE.md`) parameters, response `{ items: [...], nextCursor }` with `nextCursor` optional.
- Nullable vs optional is deliberate: optional = may be absent; nullable only when "explicitly none" differs from "not sent" (PATCH semantics).

## Compatibility check

Allowed inside `/v1` (additive): a new operation; a new optional request field (the server accepts its absence); a new response field (clients ignore unknown fields); a new enum value (clients map unknown); a new error code on a new situation; relaxing a limit.

Breaking (new version or a new operation beside the old one): removing or renaming anything; making an optional request field required; tightening a type, format, or limit; changing a field's meaning or units; changing a status code or error code for an existing situation; changing pagination or auth of an existing operation; removing an enum value a client may send.

A draft operation may still change shape, but once a client builds on it (`core:shipping-feature-branch` → Backend and client) every change is its own contract PR with updated fixtures, followed by a client PR; say so in the PR. Run the breaking-change diff tool when the project has one (`oasdiff breaking old.yaml new.yaml`).

## Review checklist

- Tenant operation has the membership header; identity operations do not.
- Retryable write has `Idempotency-Key`; the conventions page states its replay behavior.
- Every declared error has a test planned; `404` is used for forbidden and missing alike.
- No personal data beyond what the caller may see; no internal ids of other tenants; no signed URL that outlives its use.
- Response size bounded (page size, no nested unbounded arrays); the Load section of the PR covers the new request pattern (`planning-backend-load`).
