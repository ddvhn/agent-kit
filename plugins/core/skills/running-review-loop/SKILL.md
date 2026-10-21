---
name: running-review-loop
description: The independent review loop for a pull request or a feature branch's final audit — up to 5 rounds (10 for critical zones), a fresh core:reviewer each round that reviews the whole diff and then verifies every open thread, findings posted as inline PR review threads marked blocking or non-blocking, the lead replying but never resolving on its own, a verifying round after every fix, no merge with an unresolved thread, a one-line round summary in the PR description, tech debt after round 3, and when and how to escalate to the user. Use after a PR's checks pass and before it is merged, or when the user asks for review round N.
---

# Running the review loop

The policy is in the `delivery` rule → Review loop; this is the procedure. The lead (main session) runs it and does all writing to the PR; the reviewer is read-only. Project values come from `CLAUDE.md`: Verification (checks), Project facts → Review zones, Tech-debt list, and Merge policy.

## 1. Before round 1

- The PR is open (or, with no PR under the default merge policy, the branch is finished and about to be handed off), the local checks pass, and the description (on the PR, or prepared for the handoff when there is no PR) has the sections from the `delivery` rule → Pull requests, with an empty «Review» section.
- Pick the mode: **task** (a task or standalone PR) or **feature audit** (the feature → `develop` PR; see section 6). For the audit, merge `develop` into the feature branch first.
- **Where the record lives:** with a PR and posting allowed (the Merge policy allows it or the user asked), findings are inline review threads on the PR. Otherwise the same threads, replies, and verdicts are kept as a list in the reply.

## 2. One round

1. **Brief a new `core:reviewer`** — never reuse a reviewer from an earlier round. The brief:
   - mode, round number `N` of the limit (5, or 10 when the diff touches a critical zone: `CLAUDE.md` → Project facts → Critical zones; default money, billing, and payments, paid-service spend, auth and security; decide it in round 1 from the whole diff, and raise it to 10 when a later fix enters a critical zone), PR link or number, base and head (`origin/develop...HEAD` or `<feature>...HEAD`);
   - requirement IDs and acceptance criteria, the review zones the diff touches, the commands from `CLAUDE.md` → Verification;
   - from round 2 on: every **open thread** — id, `file:line`, blocking or not, the finding, and the lead's reply (fixed in `<sha>`, or the answer); and every **resolved thread** — id, `file:line`, the finding in one line, resolved in round K — so the reviewer can flag a finding that came back;
   - not your conclusions, not "this is fine", not a summary of why the code is right.

   The reviewer first reviews the whole diff from scratch (new findings), then verifies each open thread against the current code: fixed, answer accepted, not fixed, or partly.
2. **Read the report.** Verify each new finding against the code; a finding that is wrong gets an answer in its thread, not silence.
3. **Classify** every new finding:

   | Class | Means |
   | --- | --- |
   | Blocking | A failing check, an unmet acceptance criterion, a security or data-loss risk, a rule violation, a missing or weak test for changed behavior, coverage below the gate, a returned finding |
   | Non-blocking | Should fix and Nit: clarity, naming, small refactors, extra tests beyond the gate |

   The reviewer's Must fix is blocking; its Should fix and Nit are non-blocking; its questions become threads too. The lead may raise a finding to blocking, never lower one without a reply in its thread (`lowered: <reason>`) the next reviewer can check.
4. **Post** one review with an inline thread per new finding and question (section 3), with personal data, secrets, and tokens removed.
5. **Resolve exactly the threads the reviewer verified as fixed, or whose answer it accepted.** A thread verified "not fixed" or "partly" stays open with a reply quoting the verdict. A finding that comes back after its thread was resolved is reopened (or re-posted with the old id) and escalated.
6. **Fix or answer every open thread.** Fixes go through the subtask cycle (`delivering-changes` → Per subtask): a failing test first where the finding is a bug, then the fix, as new commits — never rewrite reviewed history. Reply in the thread with the fixing commit or the answer; **never resolve a thread on your own judgment** — the only exception: from round 4 on, a non-blocking thread may get a tech-debt row (`CLAUDE.md` → Project facts → Tech-debt list; none named → a «Tech debt» section in the PR, or the handoff when there is no PR); reply with its link and resolve it.
7. **Rerun the local checks**, push (only when the Merge policy allows it or the user asked), and add the round's summary line to the «Review» section before the next round starts.
8. **Decide.** The loop ends at the first round with no new finding (from round 4, new non-blocking ones may go to tech debt) that verifies every thread fixed or its answer accepted since the previous round, so that no thread is left open. A fix is never merged unverified: a round that left only non-blocking fixes still gets a verifying round, because the next reviewer can find something serious. In rounds 1–3 a new non-blocking finding is fixed or answered and the next round verifies it; from round 4 on it may go to tech debt instead (step 6). Loop ended → merge per the Merge policy (section 5). Otherwise check the escalation triggers (section 4), then start round `N + 1`. In the last allowed round (5, or 10 for a critical zone), a blocking finding escalates; a non-blocking thread still open goes to tech debt.

## 3. Threads and the round summary

**On GitHub (or any forge with line reviews):**

- Post one pull request review per round with a review comment per finding on its `file:line` of the PR diff (the forge CLI or API, or a review tool: a pending review plus line comments, then submit). Submit with event `COMMENT`: GitHub refuses `APPROVE` and `REQUEST_CHANGES` on your own PR, so blocking is stated only in the comment body.
- Reply in a thread with a reply comment. Resolve and reopen with `gh api graphql` (`resolveReviewThread` / `unresolveReviewThread` with the thread's GraphQL node id `PRRT_…`, from the pull request's `reviewThreads`) or a GitHub MCP resolve tool.
- An outdated thread (its line changed) is verified against the current code by its finding and can still be resolved.
- A finding outside the diff is anchored on the changed line that causes it and names its real location in the body; never put a finding in the review body only.

**Labels.** Agent comments usually post under the user's own account (through an app or connector), so every comment says who speaks. A project may name a separate bot account in `CLAUDE.md`; the labels stay anyway.

Thread body:

```markdown
**Reviewer, round 2** · R2-1 · Blocking — retry creates a second Foo
`foo_repository.dart:42`: the retry path calls `create` without the idempotency key, so a timeout followed by a retry stores two Foos.
Fix: pass the key from the first attempt; add a test that retries after a timeout.
```

Author replies start with `**Author:**`: `**Author:** Fixed in a1b2c3d.` / `**Author:** Answer: <why it stays>.` / `**Author:** lowered: <reason>` / `**Author:** Tech debt: <row link>`. The reviewer's verdict on a later round, posted by the lead: `**Reviewer, round 3:** verified fixed in a1b2c3d` or `**Reviewer, round 3:** answer accepted` (then resolve), or `**Reviewer, round 3:** not fixed — <what is still wrong>` or `**Reviewer, round 3:** partly — <what is still wrong>` (stays open).

The «Review» section of the PR description holds one line per round, nothing more:

```markdown
## Review

- Round 1: 2 blocking / 3 non-blocking — retry duplicates Foo, missing empty-list test; naming — fixed in a1b2c3d, d4e5f6a; 1 answered
- Round 2: 0 blocking / 1 non-blocking — round-1 threads verified and resolved; formatter extraction — fixed in b7c8d9e
- Round 3: 0 blocking / 0 non-blocking — round-2 fix verified and resolved
- Loop ended after round 3: no new finding, every fix verified, no open thread.
```

Finding ids are `R<round>-<n>`; a returned finding names the original (`R3-1, returns R1-1`).

## 4. Escalation

| When | Escalate |
| --- | --- |
| A finding returns after its fix (a resolved thread reopened) | early, at once |
| The blocking count is above zero and did not drop between two rounds | early, at once |
| Reviewer and author disagree on a design question | early, at once |
| The last round (5, or 10 for a critical zone) still has a blocking finding | always; do not merge |

One message (or decision card) per escalation, nothing else in it:

```
PR <link>, review round N: <finding id and one-line problem>
Why it is stuck: <returned after fix in <sha> | blocking 3 → 3 | design disagreement: <both positions>>
Options:
1. <option> — <consequence>
2. <option> — <consequence>
Recommendation: <option number> — <one-line reason>
```

While it waits, keep working on other tasks; do not merge this PR.

## 5. Merging

- Never merge while any thread is unresolved, blocking or not: each one is resolved by a reviewer's verification or, from round 4 on for a non-blocking one, with a link to its tech-debt row.
- The loop ended and the checks pass: under the default policy, report and wait for the user; under a project Merge policy, merge yourself unless the PR is one of the project's critical changes. Release and hotfix merges into `main` need the Merge policy to name them explicitly; otherwise the user merges them.
- Task, standalone, and hotfix PRs: squash. Feature → `develop`, `develop` → `main` (a release), and `main` → `develop` after a hotfix: merge commit, never squash.
- Never skip hooks or bypass branch protection to merge.

## 6. Feature audit

The same rounds, threads, summary, and escalation, with a stricter brief: mode `feature audit`, the whole diff `origin/develop...<feature>` after `develop` was merged in, and this checklist in priority order:

1. **Security**: authentication, authorization and tenancy (every new endpoint, query, and screen checks the actor and scope), input validation at trust boundaries, secrets, personal data in logs, abuse and spend (rate limits, paid-provider calls, unbounded fan-out).
2. **Correctness and tests** on the merged result: the full checks and the coverage gate, every acceptance criterion of every task, integration points between the tasks, cross-repository compatibility (`reviewing-branch` → Cross-repo compatibility).
3. **Performance**: requests, queries, payloads, background work against the project's load expectations.
4. **Architecture**: the kit and repository rules across the whole feature, not per task.
5. **Legal and compliance**, when the project defines it in its rules.
6. **Demo**: screenshots or a recording of the user path, or the API scenario, attached to the PR, or in the reply when there is no PR; missing → blocking.

Task PRs already reviewed are not a reason to skip a file: the audit reads the whole diff.
