---
description: Delivery rule — branches and merge styles, slice size, visible tests-first, coverage, local checks, paid services, flaky tests, the review loop, required PR sections, merge policy, environments, docs, decisions, and scope
---

# Delivery

How work reaches `develop` and `main`. Project values come from `CLAUDE.md` → Project facts and Verification. Procedures: `delivering-changes`, `shipping-feature-branch` (task PRs, final audit, release, hotfix), `running-review-loop`.

## Branches

Default: `develop` is the integration branch everything is cut from and lands in; `main` holds releases only and production deploys from it (GitFlow without release branches). A project may rename both in `CLAUDE.md` → Project facts → Integration branch (older: "Main branch") and Release branch, or go trunk-based (one branch, no release merge, tags on it); the kit's `develop` and `main` then mean those.

| Branch | Cut from | Lands in | Merge |
| --- | --- | --- | --- |
| `feature/<verb>-<what>` — a large feature | `develop` | `develop`, after the final audit and a demo | merge commit, never squash |
| `task/<verb>-<what>` — one task of a feature, or a small standalone one | the feature branch, or `develop` | where it was cut from | squash |
| `fix/<verb>-<what>`, `docs/<verb>-<what>` — a standalone change | `develop` | `develop` | squash |
| `develop` (a release) | — | `main`, tagged `vX.Y.Z` | merge commit, never squash |
| `hotfix/<verb>-<what>` — an urgent production fix | `main` | `main` with a patch tag; then `main` → `develop` at once | squash; `main` → `develop` merge commit |

- Names are imperative, lowercase, kebab-case English naming the action (`task/show-foo-list`); no ids, dates, or personal names. A name assigned by the agent environment is used as given.
- A feature spanning two repositories uses one branch name in both; the contract and backend land first, the client follows.
- Keep a feature branch fresh: merge `develop` into it whenever `develop` moves and before the final audit (never rebase or force-push a shared branch). It lives 1–2 weeks; a longer feature is split.
- Never commit to `develop` or `main` directly.

## Slices

- One task = one PR: about 200–400 changed lines, not counting generated code, translations, fixtures, and golden files. It delivers one user-visible behavior end to end (contract to screen, or the backend equivalent).
- A larger task is split before coding (one layer, use case, or screen state per PR); a PR over the size states why.
- Unfinished behavior stays behind a feature flag (or a draft contract operation); `develop` and the feature branch always build and pass.
- New tasks may run in parallel only when independent of every task in flight; a dependent one waits until the PR it depends on is merged (`shipping-feature-branch` → Per task, step 9).

## Tests first

- Every change, not only domain logic, starts with tests, adversarial cases first (`architecture-principles` → Test-Driven Development); a test names the rule it protects. Where a suite exists the PR opens with a commit of only the failing tests (plus compiling stubs in a typed stack) — the only failing commit, never landing outside its PR — then the implementation (`shipping-feature-branch` → Per task, step 4).
- Coverage never drops in a PR. The gate (for example 100% of handwritten code with a closed exclusion list) is the project's, in `CLAUDE.md` → Verification.

## Checks

- No CI is assumed (none is added without the user's go-ahead): checks run locally with the commands in `CLAUDE.md` → Verification and through the git hooks (`adopting-agent-kit` → Git hooks). The PR states which commands ran and their results.
- Never skip hooks (`--no-verify`) to get a commit or push through.
- No test calls a paid or metered provider: every suite uses doubles. Real providers run only in the project's manual live smoke (`shipping-feature-branch` → Release), never from a hook or another target.
- A flaky test is a defect: fixed or deleted within the project's deadline (default 2 working days), never skipped or quarantined to get green.
- Silencing a check (an ignore comment, a skipped test, a loosened lint, an unreviewed golden update) needs a reason comment on the spot and a mention in the PR; never to get green.

## Review loop

- Every PR (without a PR, the default until the user asks for one: the finished branch, record in the reply) and feature audit get an independent review by `core:reviewer` in rounds (`running-review-loop`): a fresh reviewer each round reviews the whole diff, reruns the checks, then verifies every open thread. Up to 5 rounds; 10 when the diff touches a critical zone (`CLAUDE.md` → Project facts → Critical zones; default: money, billing, and payments, paid-service spend, auth and security).
- Each finding is one labeled inline review thread at `file:line`, blocking or non-blocking (in the reply when there is no PR or posting is not allowed). The author replies with the fixing commit or an answer and never resolves a thread on its own judgment; only threads the next reviewer verified fixed or whose answer it accepted are resolved (the one exception: tech debt below).
- Every fix gets a verifying round, even when only non-blocking threads were fixed. The loop ends at the first round with no new finding (from round 4, new non-blocking ones may go to tech debt) that verifies every thread fixed or its answer accepted since the previous round; never merge before, or with an unresolved thread. A thread moved to the tech-debt list is resolved with a link to its row.
- Escalate to the user early when a fixed finding returns (a resolved thread reopened), the blocking count is above zero and did not drop between two rounds, or reviewer and author disagree on a design question; always when the last allowed round (5, or 10 for a critical zone) still has a blocking finding. One question: the finding, the options, a recommendation; other work continues meanwhile.

## Pull requests

- The description has: requirement IDs (when the project uses them), what changed for the user, tests added with the red run and then the green run, checks run with their commands, decisions taken, docs to sync outside the repository, «Review» (one summary line per round), and every section `CLAUDE.md` → Project facts → Required PR sections names (for example Load and Compliance: `shipping-feature-branch` → PR description); a required section that does not apply is one line ("Load: no change").
- The final audit PR (feature → `develop`) adds a demo: screenshots or a recording of the user path, or the API scenario.

## Merge policy

- **Default:** commit per approved plan; push, open PRs, merge, and deploy only when the user asks (working agreement → Commits and remote).
- **Project override:** `CLAUDE.md` → Project facts → Merge policy may let the agent push, open PRs, and merge task, feature, and standalone PRs once the checks pass and the review loop has ended — except the critical changes the project lists (for example money, paid-service spend, "ask first" items, an unresolved finding), which wait for the user.
- Under an override, before each new feature branch send the user a short note: what in it will wait for them and what the agent merges.

## Environments

Declared in `CLAUDE.md` → Project facts → Environments. Default:

- **local**: any branch on the developer's or agent's machine, providers faked, demo seed; **preview** (optional): a task or feature branch before merge; **staging**: auto-deployed from `develop` after every merge, synthetic data only (never a copy of production), where the demo and staging tests run; **production**: `main` after a manual approval.
- Backend and web images are promoted staging → production without rebuilding; app builds are built per environment from the tagged release commit, each pointing to its backend (the stack plugin says how).
- A feature reaches staging only through `develop`; branches are verified locally or in preview; the audit demo runs on the merged result.
- Any production deploy or production access always waits for the user.

## Decisions and scope

- Docs change in the same PR as the behavior: the spec, the repository's rules, and the README (setup, configuration, run, test, build, deploy).
- No answer in the spec or from the user: pick the best option, record it (a lasting one as an ADR with `recording-decisions`, a local one in the PR description), and continue. "Ask first" items (working agreement, `CLAUDE.md` → Project nuances) are never decided alone.
- A question ("are we ready?", "what is missing?") gets an answer, not code; a new skeleton, feature, or screen starts only on an explicit go-ahead. Out-of-scope findings go into the PR or the reply as follow-ups, not into the diff.
