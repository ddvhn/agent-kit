---
name: recording-decisions
description: Keep the repository's written knowledge current — write an Architecture Decision Record (ADR) for a hard-to-reverse choice, and create or update the feature spec in docs/ when behavior changes. Use when a plan picks between real alternatives, when a change alters documented behavior, contracts, or flows, when adding a feature that needs a spec, or when the user asks to document a decision or a feature.
---

# Recording decisions and specs

Two kinds of documents, both in the repository and both listed in `CLAUDE.md` → Specs:

| | Feature spec | ADR |
| --- | --- | --- |
| Answers | What the feature does now and how | Why we chose X over Y |
| Where | `docs/<feature>.md` (the project's existing layout wins) | `docs/decisions/NNN-short-title.md` |
| Changes | Edited in place whenever behavior changes | Immutable once accepted; a later ADR supersedes it |

## Feature specs

Specs are the source of truth for behavior. Code and spec change in the same commit.

- **Update** the spec when a change alters user-visible behavior, an API contract (names, fields, errors), a state machine, a data shape, a background flow, or a limit. Grep `docs/` for the feature before changing it; a spec that disagrees with the code you just wrote is a bug in the commit.
- **Create** one for a new feature that spans layers or repositories, has a non-obvious flow, or that the next person would otherwise reverse-engineer. Add it to `CLAUDE.md` → Specs in the same commit.
- **Shape** — follow neighbors in `docs/`; by default: one paragraph of what and why, then numbered sections: flow (numbered steps), API / contract (names, request, response, errors), data (documents, fields, versions), states and edge cases, limits and costs, testing notes. Real identifiers are fine here — specs are project text.
- **Style** — present tense, describes the current system (no "we changed…", no history; history is git and ADRs). Short sentences, tables for contracts, links to code paths instead of pasted code.
- Several repositories (backend, clients): the spec lives where the behavior is owned (usually the backend); others link to it (`CLAUDE.md` → Related repositories).

## ADRs

Write one when a decision:

- is expensive to reverse (data model, persistence, navigation or state architecture, a third-party provider, contract versioning, a cross-repo pattern);
- had at least two reasonable options and the choice will be questioned later;
- changes a convention that existing code follows (old code migrates "when next touched").

Do not write one for choices a rule already dictates, or for local implementation details.

Template (`docs/decisions/NNN-short-title.md`, next free number, three digits):

```markdown
# ADR-NNN: <Decision in a few words>

## Status

Proposed | Accepted | Superseded by ADR-MMM

## Date

YYYY-MM-DD

## Context

The problem, constraints, and forces. What made this come up now.

## Options Considered

### Option A: <name>

- Pros: …
- Cons: …

### Option B: <name>

- Pros: …
- Cons: …

## Decision

We choose **Option X** because … State what is now required and what is no longer allowed.

## Consequences

- What changes in code and conventions (states, names, wiring).
- Existing code that does not follow it yet, and when it migrates.
- Follow-ups.
```

Rules:

- One decision per ADR, one to two pages. Present tense ("We choose").
- `Proposed` while the user has not approved it; the user's approval makes it `Accepted` (part of plan approval in `delivering-changes`).
- Never edit an accepted ADR's decision; write a new one and mark the old one `Superseded by ADR-MMM`.
- A decision that becomes a standing convention also becomes a rule: project-specific → the repository's `.claude/rules/`; generic → propose a kit change (working agreement → Where configuration lives). The rule links the ADR for the why.
- Writing one after the fact is fine; date it when written.

## In the workflow

- **Plan** (`delivering-changes`): a plan that picks between real alternatives names the ADR to write; a plan that changes documented behavior names the spec to update. Both are files in a subtask, not an afterthought.
- **Review** (`reviewing-branch`): behavior changed without its spec, or an expensive choice without an ADR → **Should fix**; a spec that now contradicts the code → **Must fix**.
- **Handoff**: list specs and ADRs touched.
