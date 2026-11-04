---
name: scoping-project-rules
description: Split a repository's own agent rules (CLAUDE.md and .claude/rules) by path, so each session loads only the rules for the files it touches — measure what loads, move screen, feature, later-feature, and tooling sections word for word into path-scoped files, leave pointers, check that no line is lost and every glob matches the real code and tests, review, and measure again. Use when a repository's loaded rules grow past the budget, when a session over several repositories carries the neighbor's rules, or when the user asks to slim, split, or scope project rules.
---

# Scoping project rules

Loaded rules are re-sent with every agent step, not once per session: the cost grows with steps × context (cheaper when cached, but the rules always fill the context window and dilute attention). Rules a task does not need are paid for on every step of every task. Goal: each session loads the general rules of its own repository plus the file of the screen or feature it works on, with no rule lost and none moved where it will not load.

Content does not change in this procedure: nothing is deleted or reworded, only moved. Changing a rule, the enabled plugins, or the kit is a separate decision of the user.

## Budget

What a typical session loads from a repository stays around 25–30 KB: `CLAUDE.md`, the rules without `paths:`, and the general rules that the first files of a task match. A screen or feature file comes on top of that.

## 1. Measure before

- List `CLAUDE.md` and every `.claude/rules/*.md` in each repository with its size in bytes, and whether it loads at session start (no `paths:`) or by path.
- Find the five largest `## …` sections and their sizes.
- A session started above several repositories loads each repository's `CLAUDE.md` and its rules without `paths:` (kit README → Repository rules): count a neighbor's general rules in the cost of working on the other repository.

## 2. Classify

Put every section, and every large bullet, into one group:

| Group | Goes to | `paths:` |
| --- | --- | --- |
| **Always**: process, PR sections, compliance, TDD, layers and architecture, security and personal data, glossary, who decides statuses and permissions | stays in its file | none by default. Where sessions over several repositories are the norm, the large general files may get globs on the repository's own files; process rules (PR sections, compliance) stay without `paths:` |
| **One built screen or feature**: what a screen, component, or flow does | `screen-<name>.md` or `feature-<name>.md` | the feature's folders: code, tests, end-to-end tests, mocks and fixtures |
| **A later feature with no code yet** | `<topic>-later.md` (or `<rule>-later.md` when it is the later part of one rule) | the future folders and file names (`**/foo/**`, `**/*foo*`) |
| **Tooling**: end-to-end harness, mock server, generators | `<tool>.md` | the tool's folders and the API files that require it |

One file per subject; a file stays under 9,000 characters (split by topic if not). A rule for one subfolder may instead go to a nested `CLAUDE.md` there, which loads when that folder is used.

## 3. Move

- Move text word for word.
- At each moved heading leave the heading and one line: "Moved to `<file>` (loaded with …); read it before starting work there", so references like "rule X → section Y" still resolve.
- Add an index at the top of the general file: which files exist and with which paths they load.
- In `CLAUDE.md`, one sentence: parts of the rules load by path, and the new files.
- Update each touched file's `description:` so it no longer lists what moved out.

## 4. Check

- A script compares the old and new files: every non-blank old line is found verbatim in the new set (for example `grep -Fxvf <new lines> <old lines>` prints the lost ones). Expected differences are only the rewritten `description:` lines, the index, the pointer lines, and the `CLAUDE.md` sentence; for a bullet split across files, compare character counts.
- For each path-scoped file, check its `paths:` against `git ls-files`: every file the rule describes matches, tests, fixtures, and end-to-end tests included. A general file with globs matches every tracked file type a task can start in (scripts, SQL, the API contract, `docs/`, config).
- Take extra care with review zones (security, personal data, money, server time, idempotency): when the rule governs code in shared folders (platform, server, common), add those paths or keep the section in the general file.
- Globs are valid picomatch, relative to the repository root (above several repositories the kit hook lists them per repository).
- The built-in `Plan` gets `.claude/rules/*.md` through a hook that ignores `paths:` and joins files alphabetically up to 9,000 characters, listing the rest by path: after a split, check that the general rules still reach it or are listed.

## 5. Review

The PR's review loop (`running-review-loop`) gives the reviewer the old and new files and the folder tree, with one question besides its usual ones: is any text lost, and does every rule load where it is needed? Rounds continue until one has no new finding.

## 6. Measure after

Compute the kilobytes loaded in a typical task (general files + one screen file) and in a task on the neighbor repository, before and after. Put the numbers in the PR.

## 7. Deliver

One documentation PR per repository, following the project's branch and merge rules (`delivery` rule); where the project lets the agent merge documentation, merge it.

## Keeping it scoped

A new screen or feature description goes into its own path-scoped file from the start, never into an always-loaded rule; a later feature's rules load with its folders and file names. `adopting-agent-kit` sets a new repository up this way.
