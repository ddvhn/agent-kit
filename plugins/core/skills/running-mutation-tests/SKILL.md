---
name: running-mutation-tests
description: Check that tests really guard the code they cover — after the changed code reaches full line coverage, run mutation testing on the changed files only, triage surviving mutants (equivalent, logging and UI-widget noise, real gaps), add tests for the real ones, record accepted survivors, and state the score in the PR; per-area configs because every mutant reruns the tests; tools per stack (Dart mutation_test, Stryker for TypeScript, mutmut for Python, Gremlins for Go, PIT for JVM). Use before pushing a change to logic that has tests, when adding mutation testing to a repository, or when asked how good a suite really is.
---

# Running mutation tests

Coverage says a line ran; it does not say a test would notice if the line were wrong. A mutation tool makes small mechanical edits to the code — a flipped comparison (`<` → `<=`), a negated condition, a removed statement or call, `+` → `-`, `true` → `false`, an emptied return — and reruns the tests against each one. A mutant the tests kill is guarded code; a mutant that **survives** is behavior no test checks.

Policy: core `architecture-principles` → Test-Driven Development. The project's tool, configs, and command: `CLAUDE.md` → Verification and the repository's rules.

## When

- **Order**: tests first (red, then green), then full line coverage of the changed code, then mutation testing on top. Mutating uncovered code only reports what coverage already showed.
- **Locally, before the PR is pushed**, on the files the change touched — never the whole codebase. Rerun after adding tests until every survivor is either killed or recorded.
- **Where it pays**: domain logic, state machines and their transitions, calculators, money, time and deadlines, parsers and mappers, repositories with rules in their queries, controllers that decide. Skip generated code, thin SDK adapters, DI wiring, and pure layout widgets.
- **Only suites fast enough to run per mutant**: unit tests and fast widget or emulator tests. E2E and device tests (Patrol, browser flows) are too slow; behavior they alone guard needs a unit test first.
- **CI**, when the project has one, at most checks that the score of a configured area did not drop below the recorded one. It never runs the full mutation suite on every push.

## Cost and scope

Every mutant reruns the selected tests, so a run costs `mutants × test time`. Keep it small:

- **One config per area** (a feature, a state machine, a group of related files), each listing its source files and only the tests that guard them. A change runs its area's tests but mutates only the changed files (Stryker `--mutate <files>`, Gremlins `--diff <base>`, PIT `targetClasses`, a temporary `mutation_test` config listing those files); the whole area runs only when its recorded score is refreshed.
- Fast tests first, slower ones after, so a killed mutant stops early (staged test commands).
- A **per-test timeout** (about 10 s, well above the slowest test's normal run): a mutant that makes a loop hang must fail fast instead of waiting for the runner's default.
- Exclude noise in the config, not in triage: logging calls, debug-only branches, `assert`s, string literals (copy), generated files.
- Some tools (Dart `mutation_test`, Cosmic Ray, mutmut 2, go-mutesting) edit source files in place while they run: start from a clean tree for the mutated paths, restore them on exit (also on Ctrl+C), and run two configs in parallel only in separate checkouts or worktrees. The others work on a copy or in memory.
- Tests that share external state (an emulator, a database) run with one worker per state: concurrency 1, or one project or database per worker.

## Triage

Open the report and sort every survivor into exactly one bucket:

| Survivor | Action |
| --- | --- |
| **Real gap** — the mutant changes behavior a user, caller, or stored record could see | A test that fails on the mutant and passes on the original; adversarial first, named after the rule it protects. A real bug the mutant exposes follows the bug rule (failing test committed alone, then the fix). |
| **Equivalent** — the mutant computes the same result for every reachable input (`>= length` where only `-1` reaches the guard; `% n` where the value is never negative; whitespace or formatting) | Record it with the reason. If the original is misleading, simplify the code so the mutant disappears; never add a test that only pins an implementation detail. |
| **Noise** — logging, debug output, analytics labels, purely visual widget properties (padding, color, an icon) | Exclude the pattern in the config; a visual change belongs to golden or snapshot tests, not to mutants. |
| **Timing** — killed in some runs and surviving in others | Either a race in the code (a real gap: a test with provider hooks or a steppable clock) or a flaky test: fixed or deleted, never recorded as accepted (`delivery` rule → Checks). Never rerun until green. |

A survivor is never "accepted" because a test would be hard to write: a hard-to-reach branch is a design smell (extract the decision into a pure function and test that). A test added for a survivor still respects the owning-suite rule and asserts behavior, not internals.

## Record

- **In the repository**: the run script, one config per area, and a short README beside them with the command, each config's files and score (killed / total, with the date), and a table of accepted survivors (`file:line` at the time of the run, the mutant, why it is not a gap).
- **Score** = killed ÷ (total − recorded equivalents), as a percentage. A run on the changed files only has no base: its gate is every survivor killed, excluded, or recorded. "Not lower than the base" compares whole-area runs only (a score refresh, a CI check); a new area has "base: none".
- **In the PR**, under Tests: `Mutation: <files or config> <killed>/<total>, <score>%`, the tests added for survivors, and the survivors accepted with their reason; for a whole-area run also `(base <score>% or none)`. A whole-area score never drops without a recorded reason.

## Tools by stack

Pick the stack's established tool; install it as a dev tool, not a runtime dependency, pinned to a version.

| Stack | Tool | Scope to changed files |
| --- | --- | --- |
| Dart / Flutter | `mutation_test` (pub.dev, global activate) | XML config per area: `<files>`, `<exclude>` regexes for logging and asserts, `<commands>` with the staged `flutter test --timeout` call; `--exclude-strings`, `--format html` |
| TypeScript / JavaScript | Stryker (`@stryker-mutator/core` with the Vitest or Jest runner) | `--mutate` globs or `mutate` in the config, `--incremental` to reuse earlier results, `thresholds.break` for a CI floor, `ignoreStatic` for module-level code |
| Python | mutmut or Cosmic Ray | `paths_to_mutate` per area, the pytest command narrowed to the area's tests |
| Go | Gremlins (`gremlins unleash`) or go-mutesting | packages whose tests need no database (domain, app), or database tests split off by a build tag (`--tags`); `--diff <base>` to mutate only changed code |
| JVM (Kotlin, Java) | PIT (`pitest`) with the Gradle or Maven plugin | `targetClasses` / `targetTests` per area, `withHistory` for incremental runs |
| Swift | Muter | `muter.conf.yml` `exclude` and the test command per scheme |

Flutter example layout: `scripts/mutation/run.sh [config]` (installs the pinned tool, refuses a dirty `lib`, restores it on exit, runs one or every config), `scripts/mutation/<area>.xml` per area, `scripts/mutation/flutter_test_stages.sh` (runs `flutter test --no-pub --timeout 10s` in stages split by `--`), and `scripts/mutation/README.md` with scores and accepted survivors. The same shape fits any stack: a run script, a config per area, a README with the scores.

## Done when

- Every changed file in a logic area ran through its config after its tests reached full line coverage.
- Every survivor is killed by a new test, excluded as noise in the config, or recorded as equivalent with its reason.
- The score is in the PR; when the whole area ran, also in the README and not lower than the base.
