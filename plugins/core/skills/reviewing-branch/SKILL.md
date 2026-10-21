---
name: reviewing-branch
description: Full production-readiness review of a branch, merge request, commit, or staged changes — runs the project's static checks and affected test suites, checks compatibility with the related repos (API exports, client usage, shared modules), delegates risky zones to the reviewer subagent, and reports a merge verdict. Use whenever the user asks for a review ("сделай ревью", "review the branch", "можно мержить?").
---

# Reviewing a branch

Report only. Do not edit, commit, or push until the user says to fix. The review standard is the kit rules in your context (core rules (`architecture-principles`, `architecture-principles-code`, `same-level-dependencies`, `minimal-change`, `delivery`) and the stack rules), the repository's `.claude/rules/`, and `CLAUDE.md` → Project nuances. Project specifics come from `CLAUDE.md`: Verification (commands), Project facts → Review zones, and Related repositories.

## 1. Scope

- Default: the current branch against the integration branch (`<develop>`: `CLAUDE.md` → Project facts → Integration branch, `develop` unless the project renames it; `delivery` rule → Branches) plus uncommitted work; a task branch of a feature is compared with its feature branch. Compare with the remote base so a stale local `<develop>` does not leak merged commits into the diff: `git fetch origin <develop>`, then `git diff origin/<develop>...HEAD` and `git diff HEAD`; new files are not in either — list them with `git ls-files --others --exclude-standard` and read them. List commits with `git log --oneline origin/<develop>..HEAD`. No remote: use the local `<develop>` and say so.
- A submodule pointer changed: also diff inside it (`git -C <submodule> diff <old>..<new>`, both SHAs from the parent diff) and review that code too.
- The user named something else (staged only, a commit, an MR, another base): use that.
- State the scope in the report's first line. An empty diff: say so and stop.

## 2. Classify

From `git diff --name-only`, mark every review zone from `CLAUDE.md` → Project facts → Review zones that the diff touches. Always also mark:

| Zone | Signal |
| --- | --- |
| Third-party integration | new or changed provider calls, and whether tests mock them (project testing rule) |
| Security | auth, roles, secrets, payments, logging of user data |

Each marked zone requires step 5.

## 3. Run checks yourself

Use the Verification section of `CLAUDE.md`; record each command and its result.

1. Static checks (analyze / lint / typecheck) — always.
2. Unit suites for every package or layer whose source or tests changed.
3. Integration / E2E suites whose boundary the diff crosses (emulator suites, E2E); the affected test files first, the full suite when shared wiring (routing, DI, test harness, middleware) changed.
4. Coverage of changed behavior: every new or changed transition has a test that fails if the logic breaks; no existing test was deleted, weakened, or skipped.
5. Generated files changed without their inputs (or the reverse): regenerate and compare.
6. Docs (`recording-decisions`): a spec in `docs/` (`CLAUDE.md` → Specs) that now contradicts the code is a **Must fix**; changed behavior without its spec, rule, or README update, or an expensive design choice without an ADR, is a **Should fix** (in a PR's review loop: **Must fix**, `delivery` rule → Decisions and scope).
7. Test doubles: a test that calls a paid or metered provider, or a skipped or quarantined test, is a **Must fix**.

A failing check is a **Must fix**; quote only the failing lines. Do not grind to green here.

## 4. Cross-repo compatibility

Use `CLAUDE.md` → Related repositories:

- **Backend changed an exported API contract** (function or endpoint name, region, request, response, error codes, removal): find usages by the exported name in each client repo and compare with their request params and response models. A breaking change without a `…V2` endpoint is **Must fix**.
- **Client changed how it calls the backend**: find the export in the backend (where: `CLAUDE.md` → Related repositories) and compare the request schema and response model. Calling a name or field the backend does not export is **Must fix**.
- **Shared module changed** (a submodule or package used by other repos): grep every other repo that uses it for each changed public symbol. A break there without a matching change is **Must fix**.
- A related repo missing locally: say the check was skipped.

## 5. Independent review

- Any zone marked in step 2: delegate to `core:reviewer`. Brief it with the scope, the zones, the changed file list, and the acceptance criteria if the user gave any — not your conclusions. Verify its findings against the code before reporting them.
- A PR in its review loop (`delivery` rule → Review loop): every round goes to a new `core:reviewer` with the round context; follow `running-review-loop`.
- Nothing marked: review the diff yourself against the kit rules (principles, layers and same-level dependencies, naming reuse, error classes, minimal change, language and state-management rules) and the matching stack skills.
- User-visible UI changes: do the live UI pass when the project describes one and a debug session is running; otherwise list it under Not verified.

## 6. Report

```
Scope: <branch> vs <develop>, N commits (+ uncommitted)
Verdict: ready to merge | not ready — <one-line reason>

Must fix
- file:line — problem — why it matters — fix
Should fix
- …
Nit
- …

Checks
- <command> — pass
- <command> — FAILED: <failing lines>
- cross-repo: <symbol> — <where used>, compatible
Not verified
- <anything skipped and why>
```

`ready to merge` only when there is no Must fix and every required check ran and passed. Never omit failures, skipped checks, or security findings.
