---
name: auditing-flutter-security
description: Perform a systematic security audit of a Flutter app (web or mobile) — secrets, auth, storage, payments, and insecure patterns.
---

# Security Audit

Use this skill when the user asks to audit security, check for vulnerabilities, review code for security issues, or harden the app. The policy it checks against: the stack `architecture` rule → Security (and → Logging and crash reporting for what may be logged); this skill is the procedure.

## Steps

1. **Scan for hardcoded secrets** — API keys, tokens, passwords, dart-defines committed in source, signing material.
   - Patterns: `password=`, `secret=`, `apiKey`, `AKIA`, `sk_live_`, `ghp_`
   - Files: `.env` in git, service-account JSON, payment-provider keys, keystores / signing configs, Firebase config files (`google-services.json` / `GoogleService-Info.plist`) from the wrong flavor

2. **Authentication & authorization**
   - Authorization only in a widget, hardcoded user-id allowlists (policy: `architecture` rule → Security).
   - Token / session handling: don't log ID tokens; secrets that need protection go to Keychain / Keystore (`flutter_secure_storage`), not `SharedPreferences` or the database. Access tokens refresh through one rotating client (`fresh_dio`) that retries once and signs out on a refused refresh (`generating-api-clients` → The client).
   - Device signing keys non-exportable in the Keystore / Secure Enclave; queued actions scoped to the user who made them and never sent by another (`queueing-offline-actions`).
   - Deep links and URL-scheme handlers: validate targets; don't execute privileged actions from an untrusted URL without auth.

3. **Injection / unsafe surfaces**
   - `eval`-like / `Process` with user input (rare on Flutter — still grep).
   - WebView / HTML: untrusted HTML, JavaScript mode.
   - Path traversal on file uploads and downloads (media clients, local DB / file paths built from server data).

4. **Dependencies**
   - `flutter pub outdated` / advisory sources. Flag known CVEs. Respect root `dependency_overrides`.

5. **Data exposure**
   - Logs and crash reports: anything the logging policy forbids, identifiers not passed through the redaction helper, precise location if not required.
   - Signed media URLs persisted or logged; image bytes of other users cached beyond the session.
   - Analytics properties other than ids and enums (`tracking-analytics-events`).
   - Error UI: domain exceptions mapped to copy in one place, not raw SDK exceptions or stack traces (`architecture` rule → Errors).
   - Payments: checkout secrets stay server-side; store purchases are verified by the backend, not trusted from the client.

6. **Platform** (apply the part for the project's platforms, `CLAUDE.md` → Project facts)
   - Web: `--disable-web-security` is a local debug flag only — never ship it.
   - Mobile: no secrets in `AndroidManifest.xml` / `Info.plist` / bundled assets; release builds are not debuggable; deep-link and URL-scheme handlers validate input.
   - Mobile: permissions (location, notifications, photos, camera) requested only when the feature needs them, with purpose strings only for used APIs; sensitive screens hidden from screenshots / recents where required; the local database and queued files encrypted with a key from secure storage and excluded from OS cloud backup (Android `dataExtractionRules`, iOS `isExcludedFromBackup`); release fastlane credentials only in the environment, `fastlane/keys/` and `.env` git-ignored (`releasing-flutter-apps`).
   - CORS / emulator hosts must not leak into production builds.

7. **Report** — Critical / High / Medium / Low, file:line, fix.

## Notes

- This is a code review, not a pentest.
- Confirm `.gitignore` excludes service accounts, `.env` files (including test env files), keystores and signing files.
- Flag "security only in the widget" as High.
