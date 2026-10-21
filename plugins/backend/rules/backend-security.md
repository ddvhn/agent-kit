---
description: Backend security — ASVS level, standard token handling, step-up, per-action authorization with 404 for forbidden, multi-tenant isolation with forced Row-Level Security and composite keys, census tests, secrets, input limits, personal data never in logs, private media, compliance section
---

# Backend security

Checklists, authentication details, and the Compliance section: `auditing-backend-security`; tenant isolation templates: `isolating-tenants-in-postgres`. The project's ASVS level, sensitive actions, abuse cases, and markets: `CLAUDE.md`.

## Baseline

- Target OWASP ASVS level 2 for API and web unless `CLAUDE.md` says otherwise; the OWASP API Top 10 is the threat list.
- Deny by default: a route without a declared policy fails the route census.

## Authentication

- Use a standard library or the platform's identity service; never hand-roll token signing or parsing. Short-lived access tokens; refresh tokens single use, rotated, stored only as a hash, in a family with an absolute lifetime; any reuse of a used token revokes the whole family (no grace window unless an ADR adds one, `auditing-backend-security`); logout and logout-all revoke the family; access tokens live until their short expiry, and step-up actions also check the family is not revoked. Token endpoints never go through the idempotency replay store. Clients refresh one at a time: two concurrent refreshes with one token revoke the family and sign the user out.
- Secrets sent to users (one-time codes, invitation tokens) are stored as keyed hashes, rate-limited, and answer the same for known and unknown accounts.
- Fake providers are not compiled into release builds and never run outside local and test; configuration validation fails closed (any other environment without live providers and their keys refuses to start).
- Permissions and membership status are checked on every request; sensitive actions listed in `CLAUDE.md` require step-up.

## Authorization

- The use case checks role + membership of the specific resource for the specific action; the tenant comes from the acting membership, never from request parameters.
- Repositories always filter by tenant and allowed scopes; lists, counts, exports, notifications, and deltas apply the same filters as `GET`.
- Forbidden and missing are the same `404`; ids are not secrets.

## Multi-tenancy

When the product is multi-tenant:

- One shared database; `tenant_id` on every tenant row; a separate installation only per legal region.
- Postgres Row-Level Security on every tenant table, `ENABLE` and `FORCE`, fail-closed: `tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid` (wrapped in a `platform.current_tenant_id()` function), set per transaction with `set_config(…, true)`.
- Composite foreign keys `(tenant_id, x_id) REFERENCES … (tenant_id, id)`; the application role owns nothing and has no `BYPASSRLS`; cross-tenant jobs use a separate role in their own package (review zone); global data is read-only for the application.

## Secrets and input

- Secrets from the environment or a secret store, never in the repository, image, or logs; `gitleaks` before commit; dependency scanning before release.
- Input bounded and validated at the edge; output encoded for its medium; spreadsheet cells escaped; the server never fetches user-supplied URLs; CORS only for own origins.
- Every closed abuse case gets a regression test.

## Personal data

- Logs, traces, metrics, and error reports carry ids only: never phone numbers, emails, names, codes, tokens, signed URLs, bodies, or message text; a test scans the run's logs.
- Personal data lives in identity tables; deletion anonymizes.
- Media in private buckets behind short-lived signed URLs that are never stored or logged.
- When `CLAUDE.md` names markets, a change touching personal data, providers, retention, or automated decisions carries a Compliance section (`auditing-backend-security` → Compliance section).
