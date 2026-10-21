---
name: delivering-changes
description: The lead workflow from request to a reviewed feature branch — size the task (S / M / L), plan subtasks in plan mode, then per subtask tests first, delegate to core:developer, verify, review where required, and commit; finish with a live QA pass for UI, a review of the whole branch, the PR per the project's merge policy, and independent tasks in parallel while it is in review; ends with the definition of done. Size L continues as a feature branch with task PRs (shipping-feature-branch). Use at the start of any change that touches more than one file or a review zone, before writing code.
---

# Delivering changes

The main session is the **lead**: it plans, talks to the user, delegates, verifies, and commits. Project specifics — verification commands, review zones, integration branch, apps, test accounts, Merge policy — come from `CLAUDE.md`. Branches, slices, review rounds, and merging follow the `delivery` rule.

## 0. Size the task

State the size in the first line of the plan; the user may change it.

| Size | What | Who takes part |
| --- | --- | --- |
| **S** | One file, copy change, small fix, a question | Lead alone. A bug fix still starts with a test that reproduces it where a suite exists (TDD). Verify with the edit hook and the one relevant test. No plan, no commit unless asked; if the change becomes a PR, the review loop applies (`running-review-loop`). |
| **M** (default) | Several files, clear design, one PR within the slice size (`delivery` rule → Slices) | Lead + `core:developer`. Per-subtask `core:reviewer` only in a review zone; the PR always gets the review loop. One `qa` pass at the end if UI changed. One branch (`task/…` into a feature branch or `develop`, or `fix/…` / `docs/…` into `develop`), one PR. |
| **L** | New feature or area, several layers, a contract, more than one PR | As M, plus a planning exploration with the built-in `Plan` / `Explore` agents. A feature branch with one task PR per task and a final audit: `shipping-feature-branch`. |

## 1. Plan (M, L)

- Use plan mode. Read the code you will change yourself — you review against it later. Broad "where is X" searches go to `Explore`; for L, a `Plan` agent may map the area first. Both start without `CLAUDE.md` (`Plan` gets the kit and repository rules), so the brief carries the project facts they need.
- Split into **subtasks**, one commit each: one purpose, usually one layer or feature piece, typically under ~300 changed lines, ordered so every commit builds and passes (contract and data → repository → state and UI → polish). The one exception is the red-tests commit that opens a task PR: the only failing commit, and it never lands outside its PR.
- Per subtask: files and the neighbor to copy, **acceptance criteria** (observable behavior), **test cases** from the implementation's state machine, and whether it touches a review zone.
- UI: decide states, placement, copy, and errors in the plan, using the project's UI skill (`CLAUDE.md` → Project facts); without one, follow the neighboring screens and the stack's theming guidance. The user approves UX together with the plan.
- Docs: a subtask that changes documented behavior includes the spec update; a choice between real alternatives that is expensive to reverse includes an ADR (`recording-decisions`).
- Ask first about anything under "When to ask" in the working agreement or `CLAUDE.md`.
- Exit plan mode with the plan: size, branch name, subtasks, criteria, review zones, questions. **Approval authorizes creating the branch and committing each finished subtask to it.** Push, PR, and merge stay with the user unless `CLAUDE.md` → Project facts → Merge policy hands them to the agent (`delivery` rule → Merge policy).

## 2. Per subtask

1. **Tests first** where a suite exists: write or delegate them (adversarial cases before the happy path), run them, confirm they fail for the right reason. In the PR's first subtask the first commit holds only the failing tests; later subtasks still write tests first but commit them together with the code; in a typed stack add compiling stubs (bodies that throw not-implemented) so the analyzer and pre-commit hook pass and the tests fail at runtime. Keep the red run summary for the PR description.
2. **Delegate** to `core:developer` (Sonnet; pass `model: haiku` for purely mechanical subtasks). The brief: goal (one sentence); files with the neighbor to copy; **what you already read** — paths, line ranges, the key facts — so it does not re-explore; acceptance criteria; tests (given ones must not change) and the command that proves them; out of scope, including later subtasks. The developer already gets the kit rules at its start — do not paste them into the brief. Subtasks on disjoint files may run in parallel; verify and commit them one at a time.
3. **Verify yourself**: `git diff` of the subtask (not whole files), against criteria, plan, and rules; the narrowest commands from `CLAUDE.md` → Verification, failing lines only. A developer's "tests pass" is not evidence. Two failed rounds with the developer → fix it yourself.
4. **Review zone** → `core:reviewer` with the brief, criteria, and changed files — not your conclusions. Address every Must-fix.
5. **Commit**: only the subtask's files (check `git status`, leave the user's unrelated work alone); imperative subject saying what changed, body with why; follow the repository's message style and any required attribution. A failing subtask is never committed; the red-tests commit in step 1 is the only exception.
6. Continue with the next subtask. Stop only for a "When to ask" question, an unresolvable failure, or a plan that no longer matches reality — then show the updated plan.

## 3. Finish

1. **UI changed** → one live QA pass with the stack's QA subagent when it has one (Flutter: `flutter:qa`) over the changed flows and their neighbors. Fixes go through the subtask cycle as new commits; `qa` re-checks only the fixed scenarios. Scenarios that broke or easily could → E2E tests via `core:developer`.
2. **Own check**: the full checks from `CLAUDE.md` → Verification on the branch against the PR's base (`develop` or the feature branch), and a read of the whole diff. This is the lead's check, not a review; the independent review is the loop in step 3 (round 1 replaces a separate `reviewing-branch` pass). Fix findings as new commits; do not rewrite reviewed history unless asked.
3. **PR and review loop**: under a project Merge policy, push and open the PR; under the default policy, do that only when asked. The description follows `shipping-feature-branch` → PR description. The review loop with `running-review-loop` runs either way — on the PR, or on the finished branch with the record in the handoff when there is no PR. Merge per the Merge policy (task and standalone PRs squash). While the PR is in review, further tasks may run in parallel when independent of every task in flight; a dependent one waits until the PR it depends on is merged (`shipping-feature-branch` → Per task, step 9).
4. **Handoff**: commits (one line each), the PR and its review summary, specs and ADRs touched, what was verified and how, risks, anything not verified.

## Definition of done

A change is done when every line holds (the PR states each):

- Requirement IDs named (when the project uses them); every acceptance criterion covered by a test that failed first (the red run); every new screen state has its golden or snapshot where the stack uses them.
- Edge cases, boundaries, and odd combinations tested (`architecture-principles` → Test-Driven Development); coverage at the project gate and never lower than the base.
- Generated code in sync with its inputs (the contract, schemas, translations); every command in `CLAUDE.md` → Verification passed locally, stated with the command.
- Every section in `CLAUDE.md` → Project facts → Required PR sections filled (or "no change"); concerns there agreed with the user before implementation.
- The review loop ended (`running-review-loop`): no unresolved thread.
- The repository's rules, specs, and README updated in the same PR; docs outside the repository that need the same change listed.
- Within the slice size, or the reason it is larger stated.

## Token discipline

The working agreement's Token discipline applies. In this workflow: subagents get the brief, not the conversation, so the brief carries what you already read; full suites run once, at the end.
