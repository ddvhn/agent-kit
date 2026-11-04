---
name: scoping-project-rules
description: Split a repository's own agent rules (CLAUDE.md and .claude/rules) by path, so each session loads only the rules for the files it touches — measure what loads on every step, move screen, feature, later-feature, and tooling sections word for word into path-scoped files, leave pointers, check that no line is lost and every glob matches the real code and tests, review, and measure again. Use when the always-loaded rules of a repository grow past the budget, when a session over several repositories carries the neighbor's rules, or when the user asks to slim, split, or scope project rules.
---

# Scoping project rules

Every loaded rule is read again on every agent step, not once per session: tokens ≈ steps × context. A kilobyte of rules that a task does not need is paid for thousands of times per feature. Goal: each session loads the general rules of its own repository plus the file of the screen or feature it works on, with no rule lost and none moved where it will not load.

**Budget:** rules without `paths:` (plus `CLAUDE.md`) stay around 25–30 KB per repository. Content does not change in this procedure: nothing is deleted or reworded, only moved. Changing a rule, the enabled plugins, or the kit is a separate decision of the user.

## 1. Measure before

- List `CLAUDE.md` and every `.claude/rules/*.md` in each repository with its size in bytes, and whether it loads always (no `paths:`) or by path.
- Find the five largest `## …` sections and their sizes.
- In a session over several repositories, a neighbor's rules without `paths:` load too: count them in the cost of working on the other repository.

## 2. Classify

Put every section, and every large bullet, into one group:

| Group | Goes to | `paths:` |
| --- | --- | --- |
| **Always**: process, TDD, layers and architecture, security and personal data, glossary, who decides statuses and permissions | stays in its file | the repository's own files (`**/*.foo`, its config files), so it does not load while working on a neighbor repository |
| **One built screen or feature**: what a screen, component, or flow does | `screen-<name>.md` or `feature-<name>.md` | the feature's folders: code, tests, end-to-end tests, mocks and fixtures |
| **A later feature with no code yet** | `domain-<topic>.md` or `<rule>-later.md` | the future folders and file names (`**/foo/**`, `**/*foo*`) |
| **Tooling**: end-to-end harness, mock server, generators | its own file | the tool's folders and the API files that require it |

One file per subject; a file stays under 9,000 characters (split by topic if not).

## 3. Move

- Move text word for word.
- At each moved heading leave the heading and one line: "Moved to `<file>` (loaded with …); read it before starting work there", so references like "rule X → section Y" still resolve.
- Add an index at the top of the general file: which files exist and with which paths they load.
- In `CLAUDE.md`, one sentence: parts of the rules load by path, and the new files.
- Update each touched file's `description:` so it no longer lists what moved out.

## 4. Check

- A script compares the old and new files: every old line (except the new pointer lines) is found in the new set; for a bullet split across files, compare character counts.
- For each new file, check its `paths:` against the real folder tree: every file the rule describes matches, tests included. Take extra care with review zones (security, personal data, money, server time, idempotency): when the rule governs code in shared folders (platform, server, common), add those paths or keep the section in the general file.
- Globs are valid picomatch, relative to the repository root.

## 5. Review

Start a `core:reviewer` with the old and new files and the folder tree, on one question: is any text lost, and does every rule load where it is needed? Fix the findings and run one verifying round.

## 6. Measure after

Compute the kilobytes of rules loaded in a typical task (general files + one screen file) and in a task on the neighbor repository, before and after. Put the numbers in the PR.

## 7. Deliver

One documentation PR per repository, following the project's branch and merge rules (`delivery` rule); where the project lets the agent merge documentation, merge it.

## Keeping it scoped

A new screen or feature description goes into its own path-scoped file from the start, never into an always-loaded rule; a later feature's rules load with its folders and file names. `adopting-agent-kit` sets a new repository up this way.
