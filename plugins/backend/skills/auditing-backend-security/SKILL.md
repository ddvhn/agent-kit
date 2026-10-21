---
name: auditing-backend-security
description: Audit a backend change, branch, or whole service against the kit security rules mapped to OWASP ASVS chapters and the OWASP API Security Top 10 — authentication and tokens, sessions, authorization and tenant isolation, route and cross-tenant census, input and output, secrets and supply chain, personal data in logs, media and signed URLs, rate limits and abuse cases, infrastructure — and report findings by severity. Use when reviewing a security-sensitive change, before a release or pentest, when adding sign-in, roles, tenants, uploads, exports, or a provider, or when asked whether a backend is secure.
---

# Auditing backend security

Policy: the `backend-security` rule. The project's ASVS level, review zones, sensitive actions, abuse-case list, and markets: `CLAUDE.md` and the repository's rules; read them first. Report findings, do not fix them in the audit unless asked.

## Workflow

1. Scope: a diff (`git diff <base>...HEAD`), a module, or the whole service. List the routes, jobs, tables, providers, and data classes in scope.
2. Walk the checklist below; for each item record pass, finding, or not applicable with the file and line.
3. Verify claims by running the tests that should prove them (census, cross-tenant, idempotency, log scan); a missing test is a finding.
4. Report: findings ordered P1 (exploitable: cross-tenant read or write, auth bypass, secret or personal data exposure, money manipulation) → P2 (defense layer missing, exploitable only with another bug) → P3 (hardening); each with impact, evidence, the fix, and the regression test to add.

## Authentication defaults

- Prefer passwordless sign-in (one-time codes, a verified external identity) or the platform's identity service. Codes: short, valid minutes, few attempts per challenge, stored as HMAC with a server pepper like the identifier they went to; identical responses for known and unknown accounts; limits per identifier, IP, installation, and a daily ceiling on paid sends.
- Access token minutes long from a standard JWT library with the algorithm pinned and a key id; refresh token opaque random (≥ 128 bits), stored as a hash, single use, rotated, one family per session; plaintext never stored or replayed; strict rotation: any reuse of a used token revokes the whole family and records a security event (OAuth 2.0 security BCP, RFC 9700); logout and logout-all revoke the family (every refresh checks a family or session row); the family has an absolute lifetime; access tokens stay valid until their short expiry, and step-up and sensitive actions check the family is not revoked. Clients, not the server, handle lost responses: one refresh in flight at a time, the new pair persisted before use, and a 401 on refresh treated as sign-out. A grace window is a project decision only through an ADR that covers: the child unused and not revoked, parent and family not revoked, proof-of-possession binding (device key or DPoP), one retry recorded, inherited expiry, and logout-all tests. Token endpoints are excluded from the idempotency replay store.
- Sessions listable and revocable per device, "log out everywhere", an administrator ends a member's sessions in their tenant only. Browser sessions in `HttpOnly; Secure; SameSite` cookies with CSRF or `Origin` checks; tokens never in `localStorage`.
- Step-up (fresh re-verification within minutes) for money, personal-data exports, role grants, security settings, and deletion.
- Device keys when the product signs client data: non-exportable, registered with platform attestation, signatures and a per-device sequence verified on the server, revocation sets a cut-off.

## Checklist (ASVS chapter → what to check)

**V2 / V3 Authentication and sessions**
- One-time codes: length, lifetime, attempts per challenge, stored as keyed hashes; identical response for known and unknown identifiers; limits per identifier, IP, installation, and country; a daily ceiling on paid sends.
- Access token minutes long, algorithm pinned, key id for rotation, standard library; refresh token opaque, hash only, single use, rotated; tests: reuse of a used token → family revoked; concurrent double refresh → one wins, the other revokes the family; after logout-all every token of the family is refused; a refresh past the absolute lifetime is refused; token endpoints not in the replay store.
- Fakes fail closed: they are compiled only into non-release builds and a check proves the release build has none; configuration refuses any environment other than local / test without live providers, and live providers without every key; fake constructors refuse outside local / test; a config test covers it (a fake code sender in production is a sign-in bypass). Staging uses real adapters with sandbox credentials.
- Logout and logout-all revoke server-side; dismissal or revoked permissions apply on the next request; browser cookies `HttpOnly; Secure; SameSite`, CSRF or `Origin` check.
- Step-up required for every action on the project's sensitive list, checked in the use case, with a short validity.

**V4 Access control (API1, API3, API5 of the Top 10)**
- Every handler resolves the acting membership; every use case checks role + membership of the specific resource and action; the tenant comes from the membership, never the request.
- Forbidden and missing both `404`; no existence oracle in errors, timing, counts, or list totals.
- Lists, aggregates, exports, notifications, delta, and signed links use the same filters as `GET`.
- No mass assignment: server-computed fields absent from request schemas, unknown fields refused.
- Route census test exists and covers the new routes; cross-tenant census covers new reads.

**Tenant isolation (database)**
- New tenant tables: `tenant_id`, `ENABLE` + `FORCE` RLS with a fail-closed policy, `UNIQUE (tenant_id, id)`, composite foreign keys, indexes led by `tenant_id` (`isolating-tenants-in-postgres`).
- The runtime role has no `BYPASSRLS` and owns nothing; system-role code is isolated and justified.
- Append-only tables refuse `UPDATE` / `DELETE` in the database.

**V5 Validation, sanitization, encoding**
- Contract validation before handlers; string lengths, numeric ranges, array sizes bounded; Unicode normalized.
- Output encoding for HTML, chat-bot markup, PDF; spreadsheet formula escaping in exports.
- No SQL built from strings; no user-controlled URL fetched by the server (SSRF); no user-controlled path on disk.

**V6 / V9 Cryptography and communication**
- TLS everywhere including internal hops that cross hosts; HSTS; no custom crypto; keys from the secret store with rotation and key ids; random tokens from a CSPRNG with ≥ 128 bits.

**V7 Errors and logging**
- One error shape, no stack traces, SQL, or paths; `500` carries the request id.
- Logs, traces, metrics labels, and error reports carry ids only; the log-scan test covers new identifiers; security events (refresh reuse, step-up failures, permission changes, exports) are logged and audited.

**V8 Data protection and V12 files**
- Personal data only in identity tables; retention per class enforced by a job; deletion anonymizes.
- Private buckets, signed URLs short-lived and never stored or logged, upload size and type limits in the signed request, object keys with ids only.

**V10 / V14 Malicious code, configuration, supply chain**
- Secrets not in the repository, image, logs, or test fixtures; `gitleaks` clean; dependency and image scan clean or triaged.
- New dependencies reviewed; CI actions pinned; least-privilege tokens; agents without production access.
- CORS only for the project's origins; security headers; debug and admin endpoints not reachable publicly.

**API4 Resource consumption and abuse**
- Rate limits per user, tenant, IP with `429` and `Retry-After`; page sizes capped; heavy work only as rate-limited jobs; upload and export quotas.
- Each abuse case in the project's list has a regression test named with its id; new abuse paths found in this audit are added to the list.

**Providers and compliance**
- A new provider receiving personal data: the user's go-ahead, the subprocessor list, region, retention at the provider.
- The PR's Compliance section is present and complete (Compliance section below).

## Before a release or pentest

Also run: the full test suite with census and log scan, a dependency vulnerability scan, a dynamic scan (OWASP ZAP baseline) against staging, and a check that staging holds no production data and no production keys.

## Compliance section

When `CLAUDE.md` names markets, a PR touching personal data, a data flow, a provider, retention, logging, or an automated decision states per market: data residency, legal basis and consent shown before collection, retention and deletion, subprocessors (a new provider receiving personal data needs the user's go-ahead), cross-border transfers, employee-monitoring or notice duties, automated decisions visible to people (GDPR art. 22, the AI Act), and data subject requests. A case the project's legal analysis does not answer goes to the user, not decided by the agent.
