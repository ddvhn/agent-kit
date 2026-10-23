---
name: shipping-feature-branch
description: Ship a large feature (size L) on a feature branch — the note to the user before it starts, one small task PR per task into the feature branch (tests-first commit with the red run, implementation, local checks, review loop, PR description with the project's required sections such as Load and Compliance, merge per the project's merge policy), independent tasks in parallel worktrees while others are in review (up to the project's cap), a feature spanning backend and client (the contract PR first with fixtures, then both sides in parallel on mocks, an integration pass before the audit), keeping the branch fresh, then the final audit, demo, and merge commit into develop; also the release (develop → main, tag, live smoke, deploy, rollback) and hotfix steps. Use when delivering-changes sizes a request L, or the user asks for a feature branch.
---

# Shipping a feature branch

The `delivery` rule sets the policy (branches, slices, tests first, merge styles, Merge policy); this is the procedure for a size-L change from `delivering-changes`. Project values come from `CLAUDE.md`: the integration branch (`develop` by default, `delivery` rule → Branches), Verification, Review zones, Merge policy, Tech-debt list, required PR sections, Related repositories.

## 1. Plan the feature

- Plan as `delivering-changes` → Plan, with these additions:
  - the feature branch name `feature/<verb>-<what>`, and for two repositories the same name in both, with the contract task first and then backend and client tasks in parallel (Backend and client below);
  - **tasks**, one PR each, within the slice size (`delivery` rule → Slices); each task lists its subtasks (commits), acceptance criteria, test cases, review zones, and its branch `task/<verb>-<what>`;
  - flags for behavior that stays unfinished between tasks.
- A plan longer than 1–2 weeks of tasks is split into several features.
- Under a project Merge policy: with the plan, send the user the **feature note** — which tasks or PRs wait for them (the project's critical changes) and what the agent merges itself. Under the default policy the note is the plan itself: every push, PR, and merge waits.

## 2. Start

- `git fetch origin develop`; cut `feature/<verb>-<what>` from `origin/develop`. Push it when the Merge policy allows or the user asked.

## 3. Per task

1. **Branch**: cut `task/<verb>-<what>` from the current feature branch.
2. **Read** the task, its requirement IDs and acceptance criteria, the related rules, and the neighbor to copy.
3. **Contract**: regenerate from the current contract; anything missing → a small contract PR comes first (Backend and client below), never a guessed shape.
4. **Tests first, visibly**: write the tests (adversarial cases before the happy path), run them, confirm they fail for the right reason, and **commit them alone** (`Add failing tests for <behavior>`). In a typed stack the commit includes compiling stubs (bodies that throw not-implemented) so the analyzer and the pre-commit hook pass and the tests fail at runtime; never `--no-verify`. This is the only failing commit, and it never lands outside its PR. Save the red run summary: command, counts, the first failing lines.
5. **Implement** through the subtask cycle (`delivering-changes` → Per subtask): delegate, verify, commit per subtask; refactor with the tests green.
6. **Local checks**: every command in `CLAUDE.md` → Verification, including coverage (never lower than on the feature branch, and at the project gate). Save the green run summary.
7. **Open the PR** into the feature branch with the description below when the Merge policy allows it or the user asked; otherwise prepare the description for the handoff.
8. **Review loop** with `running-review-loop` (task mode).
9. **Parallel tasks while others are in review.** With the plan split into small tasks, start further tasks while earlier ones are in review, several at once, as long as each is independent of every task in flight. **Independent** means no shared files, module, API contract operation, or migration; a dependent task waits until the PR it depends on is merged — never stack it on an unreviewed branch. Each parallel task gets its own `task/…` branch and its own worktree (`git worktree add`), cut from the current feature branch, and its own review loop. At most `CLAUDE.md` → Project facts → Parallel tasks are in flight (in progress or in review; default 3). Review-round fixes on a PR in review come first whenever a round finishes.
10. **Merge** (squash into the feature branch) per the Merge policy once the review loop has ended. A task merging after another one first merges the fresh feature branch into its task branch and reruns the checks (a conflict or a red check means it was not independent: fix it on the task branch; the fix reopens the review loop, so one more verifying round runs before the merge); delete the task branch when the Merge policy allows it or the user asked. Default policy: report the PR and wait.
11. When `develop` moves: merge `origin/develop` into the feature branch (a merge commit), rerun the checks, fix conflicts as a task of their own.

## Backend and client

A feature that spans a backend and a client does not wait for the backend: the contract is the line between them.

1. **Contract task first.** The first task PR (in the repository that owns the contract, usually the backend) adds every operation, schema, and error code the feature needs, additive only, each operation `draft` (answering `501` until implemented; `designing-api-contracts`). It ships **contract fixtures**: example responses validated against the contract for each scenario the client shows (success, empty, maximum, each declared error). It goes through the review loop like any task and is reviewed for both sides: can the backend build it, does it carry everything the screens need.
2. **Then in parallel.** Once it merges, backend tasks implement the operations (`draft` → `stable`), and client tasks regenerate the client from the merged contract and build against a mock backend made from the fixtures (the stack skill, for example `flutter:mocking-backend-for-tests`). Client unit, widget, and end-to-end tests run on the mocks. A client task and the backend task for the same operation are independent once the contract merged (step 9); the parallel-task cap counts per repository.
3. **Contract changes found later.** The backend work finds a missing field or a wrong shape: a small contract PR (additive, fixtures updated) first, then a small client follow-up PR that regenerates and updates the mocks. Never edit generated code or fixtures toward a guess, and never let the two sides drift: the fixtures are the only source the mocks use.
4. **Integration pass before the audit.** When every operation the feature uses is `stable` on the backend feature branch, run the client against the real backend locally (or on a preview): the same end-to-end scenarios the mocks covered, then a capture of real responses compared with the fixtures. A mismatch is a defect: fix the side that breaks the contract, with a regression test, and correct the fixture through a contract PR if the contract was wrong. Only then the final audits (Finish the feature); the backend feature lands in `develop` first.

## 4. PR description

```markdown
## Summary
<Requirement IDs, if the project uses them.> <What changed for the user, in one to three lines.>

## Tests
- Added: <test files or cases, adversarial ones first>
- Red run (commit <sha>): `<command>` — <N failed>, <first failing lines>
- Green run (commit <sha>): `<command>` — <N passed>, coverage <x>% (gate <y>%)

## Checks
- `<command>` — pass

## Decisions
- <choice> — <why> (ADR: <link>, when lasting)

## Docs to sync
- <spec, mockup, or document outside the repository> — <what changes> (or "none")

<Every section the project's CLAUDE.md or rules require, for example Load or Compliance.>

## Review
<One summary line per round (`running-review-loop` → Threads and the round summary); the findings live in the PR's review threads.>
```

Silenced checks (`delivery` rule → Checks) are listed under Checks with their reason.

### Required sections: Load and Compliance

A project turns these on in `CLAUDE.md` → Project facts → Required PR sections (with its load profile, performance targets, and markets). When on, every PR has the section; a PR that does not touch its subject writes one line (`Load: no change`, `Compliance: no change`).

- **Load** — for a change to requests, polling, queries, endpoints, jobs, payloads, images, local storage, or background work: what it costs on the project's load profile and where it breaks first. Check the usual bottlenecks: requests per screen or per call (no N+1), polling intervals and jitter, payload and page sizes (no unbounded lists), hot queries and their indexes (`EXPLAIN` on realistic data), locks and long transactions, fan-out (one event → many sends or rows), queue backlog and job duration, calls to external providers, work on the UI thread, memory and battery in the background, bundle size and first load. A performance concern or trade-off (a slower query accepted, a new hot path, a raised limit, a new cache) is agreed with the user before it is implemented.
- **Compliance** — for a change to personal data, stored or cached data, logging, retention, a data flow, a third-party SDK or provider, device permissions, consent or notices, user-visible copy, or an automated decision visible to a person: for each market the project runs in, what data is collected and why (minimization), consent and notices before collection, where it goes and which provider receives it, where it is stored and for how long, monitoring rules, automated decisions, and the mandatory interface language. A new provider or SDK that receives personal data needs the user's go-ahead. A case the project's legal analysis does not answer is not decided by the agent: it goes to the user (and their list of questions for lawyers), and the change waits or ships behind a flag that stays off in the affected markets.

## 5. Finish the feature

1. All tasks merged; merge `origin/develop` into the feature branch; full checks and the coverage gate on the merged result.
2. **Demo**: screenshots or a recording of the user path (the stack's QA subagent or the project's E2E run can produce them), or the API scenario with requests and responses for backend-only work, run on the merged result locally or on staging (`delivery` rule → Environments).
3. Open the feature → `develop` PR: the summary of all tasks (one line each with its PR link), the demo, the checks, and an empty «Review» section.
4. **Final audit** with `running-review-loop` (feature audit mode). Fixes land as task PRs into the feature branch or as new commits on it; the audit reads the whole diff again each round.
5. **Merge** with a merge commit, never squash, per the Merge policy; for two repositories the integration pass (Backend and client) has run and the backend feature lands first. Default policy: hand off and wait.
6. **Handoff**: the PRs (one line each), what was verified and how, the review record, tech debt added, risks, anything not verified.

## 6. Release and hotfix

Branch names, environments, and whether preview exists come from `CLAUDE.md` → Project facts (`delivery` rule → Environments). Every step here that pushes, tags, or deploys waits for the user unless the Merge policy says otherwise; a production deploy always does.

- **Release**: `develop` is green on staging (staging tests and the feature demos passed there). Open `develop` → `main`, merge with a merge commit, tag `vX.Y.Z` on `main`. After the user's manual approval, promote the backend and web images that passed staging without rebuilding; app builds are built per environment from the tagged commit and go out as a staged rollout where the store supports it, stopped when crash or error rates rise.
- **Live smoke** (when `CLAUDE.md` → Verification has one): a small manual suite against staging that proves the real paid providers are configured and wired (one cheap call each: an OTP to a team test number, one push to a test device, a storage put / signed get / delete, one AI call on a tiny input). Run it by hand before each production release, after a provider, key, region, or bundle id change, and once per new environment; never from a hook, a schedule, or another target. It counts its calls and stops at the project's spend cap; staging keys have provider-side limits. The result goes into the release PR.
- **Deploy** (backend): migrations run as their own step before the code and abort the deploy on error; they are forward-only and expand / contract, so the previous code works with the new schema and a rollback never needs a down migration. A new feature ships behind a flag, turned on for one pilot first. Deploy outside the project's peak windows (`CLAUDE.md` → Project facts → Environments) and never with an open critical incident. After the deploy: the smoke scenario, then a watch of errors, latency, and job lag; the project's thresholds roll it back.
- **Rollback**: redeploy the previous image, or turn the feature's flag off. Broken data: stop the writing feature with its flag, then a fixing migration forward; never hand-edit production rows or rewrite append-only records (corrections are new entries). A mobile release cannot be rolled back: stop the staged rollout, turn the feature off, ship a fix, and raise the minimum supported version only once the fix is live in every store.
- **Hotfix**: cut `hotfix/<verb>-<what>` from `main`; tests first as for any task; one PR into `main` with the review loop; squash it (so the red-tests commit never lands on `main`) and tag the next patch (for example `v1.4.2` → `v1.4.3`); deploy after approval. Then merge `main` into `develop` at once (a merge commit) so the fix is not lost by the next release.
