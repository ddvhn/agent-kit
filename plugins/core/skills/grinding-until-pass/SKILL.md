---
name: grinding-until-pass
description: Loop fix → run → check until the project's analyzer, lint, typecheck, build, or tests pass. Use when making suites or analysis green after refactors, upgrades, or merge conflicts, or on an explicit "make it green" request.
---

# Grind until pass

Autonomous fix loop. The goal commands are the Verification section of the project's `CLAUDE.md`.

## Pick the goal

- The user named a command or suite: use it.
- Otherwise: the static check first (analyze / lint / typecheck), then only the failing test suite.
- Iterate on the narrowest command that reproduces the failure (one package, one test file); run the wider suite once at the end.

## Loop

1. Run the goal command; capture the exit code and errors.
2. Fail → find the root cause of the **first** actionable error; apply a minimal fix; do not refactor.
3. Re-run the same goal command.
4. Pass → stop; report iterations and what changed.

## Loop rules

- **Max 10 iterations** — then stop and report the blocker for human input.
- **One fix at a time** — re-run after each; later errors may vanish.
- **Do not delete or skip tests** — fix production code unless the test asserts obsolete intentional behavior; say so when you change a test.
- **Do not suppress** — no `// ignore`, `dynamic`, `@ts-ignore`, `@ts-nocheck`, `eslint-disable`, `any`, or lowered lint levels to silence failures.
- **Error count rises** — stop and reassess with `systematic-debugging`.
- **Generated files** — re-run the generator instead of hand-editing.
- **Never** point tests at production or staging backends to get green.

## Notes

- Slow suites (emulators, E2E) are for confirming, not for every tiny fix.
- Design-level failures need human input — do not invent architecture to force green.
