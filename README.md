# Agent kit

Project-agnostic agent setup for Claude Code: the working agreement, the lead workflow, subagents, skills, stack rules, and hooks. The kit holds *how we work* and the stack conventions written with placeholders (`Foo`, `FooRepository`). Everything about a particular project — names, paths, libraries it chose, helpers, exceptions, facts, commands — lives in that project's repository.

## Plugins

| Plugin | Enable for | Contents |
| --- | --- | --- |
| `core` | every repository | `working-agreement.md`; rules `architecture-principles` (spec-driven, contract-first, Clean Architecture, DDD scaled to size, TDD, offline-first, load / security / compliance), `architecture-principles-code` (SOLID, DRY, KISS, YAGNI, and the other engineering principles with their limits and conflict rules), `same-level-dependencies` (units of one level never inject each other), `minimal-change`, `delivery` (feature branches and task PRs, tests first, local checks and paid services, review loop with a verifying round after every fix, required PR sections, merging, merge policy); subagents `developer` (Sonnet; Haiku for mechanical subtasks), `reviewer` (Opus; review rounds and feature audits, findings posted as PR review threads); skills `delivering-changes`, `shipping-feature-branch`, `running-review-loop`, `reviewing-branch`, `recording-decisions` (feature specs and ADRs), `adopting-agent-kit`, `systematic-debugging`, `grinding-until-pass`; hooks: session start (agreement, rules), subagent start (rule; repository rules for `Plan`), analyzer on edit |
| `flutter` | Flutter apps (mobile and web from one project) | rules `architecture` (layer packages, feature folders, use cases, platforms and assembly, offline and sync levels, errors), `blocs` (one bloc per action, load / observe / action blocs), `dart` (language, accessibility), `ui` (platform look, per-platform theme, adaptive widgets, skeletons, typed navigation, copy), `data` (contract-first clients, stores, DTOs, caching), `di` (get_it, environments), `testing` (suites, widget and golden tests, coverage gate, local checks); subagent `qa` (Marionette); skills for three scenarios — build an app from scratch (`scaffolding-flutter-app`: an empty layered project with templates, scripts, and hooks; `modeling-domain`, `handling-errors`, `theming-flutter-apps`), migrate an existing app (`refactoring-to-kit-architecture`), add features (`adding-flutter-features`) — and the building blocks (`writing-load-blocs`, `writing-action-blocs`, `observing-data`, `paging-lists`, `testing-flutter-apps`, `testing-use-cases`, `writing-widget-tests`, `creating-flutter-repositories`, `generating-api-clients`, `calling-cloud-functions`, `persisting-with-isar`, `queueing-offline-actions`, `syncing-server-changes`, `adding-flutter-auth`, `adding-flutter-routes`, `building-adaptive-widgets`, `bridging-native-code`, `tracking-analytics-events`, `configuring-flutter-flavors`, `releasing-flutter-apps`, `localizing-flutter-apps`, `setting-up-patrol`, `writing-patrol-tests`, `mocking-backend-for-tests`, `driving-flutter-app`, audits, `updating-pub-package`) plus the official Flutter/Dart skills |
| `backend` | every backend (comes with `go` and `firebase-functions`) | short stack-independent rules (procedures live in skills): `backend-architecture` (modular monolith, clean layers, one use case per action, ports and adapters, outbox, adopting a platform), `backend-api` (contract first, errors, pagination, idempotency, tenant header and delta sync when they apply), `backend-security` (baseline, authentication, authorization, Row-Level Security when multi-tenant, secrets, personal data), `backend-data` (schema, append-only, migrations, retention, time, jobs), `backend-operations` (stages 0–3 from pre-launch to scale, infrastructure, deploys, rollback, incidents, backups), `backend-testing`; skills `designing-api-contracts`, `designing-client-sync`, `isolating-tenants-in-postgres`, `auditing-backend-security`, `planning-backend-load`, `running-backend-operations`, `testing-backends` |
| `go` | Go backends | rules `go`, `go-architecture` (one binary, `internal/<module>/{domain,app,infra,api,jobs}`, strict server, use case structs, depguard, River), `go-data` (pgx, sqlc, goose), `go-testing`; skills `scaffolding-go-backend` (with templates), `adding-go-modules`, `adding-go-endpoints`, `writing-go-use-cases`, `writing-go-migrations`, `writing-go-jobs`, `testing-go-backends`, `updating-go-dependency` |
| `firebase-functions` | TypeScript Firebase Cloud Functions backends | rules `platform` (Firebase as an adopted platform: its overrides of the backend defaults), `architecture`, `data`, `testing`, `typescript`; skills `scaffolding-functions-backend` (with templates), `writing-cloud-functions`, `writing-background-functions`, `creating-firestore-repositories`, `working-with-firestore`, `securing-firebase-data`, `testing-cloud-functions`, `updating-npm-package` |

`flutter` and `backend` depend on `core`; `go` and `firebase-functions` depend on `backend`. Claude Code installs dependencies transitively (enabling `go` brings `backend` and `core`). Each stack plugin prints its rules only when its stack is present under the session folder (its `stack-markers` file: `pubspec.yaml` with the Flutter SDK, `go.mod`, a `package.json` that depends on `firebase-functions`; `backend` lists the markers of every backend stack), so enabling or installing a stack plugin where the stack is absent costs nothing. A new stack plugin ships its own `stack-markers`, and a new backend stack also adds its markers to `backend`. Components are namespaced: `core:developer`, `core:reviewer`, `flutter:qa`, `/core:delivering-changes`. The exact rule and skill list is the `rules/` and `skills/` folders of each plugin.

## Kit and repository

| Lives in the kit | Lives in the repository |
| --- | --- |
| Working agreement, workflow, subagents, hooks | `CLAUDE.md`: what the project is, Project facts, Verification, Project nuances, Specs, Related repositories |
| Stack rules and skills, written with placeholders | `.claude/rules/*.md`: project conventions on top of the kit rules — real names, paths, layout, chosen libraries and helpers, allowed exceptions |
| | `.claude/skills/<name>/`: skills that fit only that repository |
| | `.claude/settings.json`, `.mcp.json` |

Kit text never names a project, its repositories, paths, or identifiers. When a kit rule needs a project value it points to `CLAUDE.md` → Project facts or to the repository's rules. `tests/run.sh` checks for leaks against a per-maintainer, git-ignored list (`tests/forbidden.local`, one extended regex per line).

### `CLAUDE.md` sections the kit reads

- **Project facts** — platform and apps, integration and release branches (default `develop` for integration, `main` for releases), critical zones (up to 10 review rounds instead of 5), Merge policy (default: push, PRs, and merges only when the user asks; or what the agent merges itself and which critical changes wait), tech-debt list, required PR sections (for example Load, Compliance), test suites, E2E device, launch configs and Marionette URIs, test account and backend for live QA, UI skill, review zones, neighbors to copy.
- **Verification** — static checks, unit / integration / E2E commands, the coverage gate, git hooks (no CI is assumed).
- **Project nuances** — exceptions to the stack rules and project-only "ask first" items.
- **Specs** — where product and feature docs live.
- **Related repositories** — clients, backends, shared modules, and how to open them together.

### Repository rules

`.claude/rules/*.md` are loaded by Claude Code itself: rules without `paths:` at session start, rules with `paths:` when a matching file is read. They reach the main session and the kit's `core:developer` / `core:reviewer`. The built-in `Plan` agent starts without them, so `core` hands them to `Plan` through a SubagentStart hook (`print-project-rules.sh`). Use the same front matter as kit rules (`description:`, optional `paths:`) and keep each file under 9,000 characters.

A session that starts above the repositories (a folder holding several of them, as cloud sessions over several repositories do) loads each repository's `CLAUDE.md` but not its `.claude/rules` or `.claude/skills`. There `core` lists them per repository at session start, with the paths each rule covers (`print-nested-repositories.sh`), and the session reads the matching files itself. Nothing in the repository needs to change for that.

## How it reaches a session

- **Claude Code** installs the enabled plugins from this repository and keeps them updated (auto-update). Plugins cannot ship `CLAUDE.md` or `.claude/rules`, so kit rules travel through hooks (`scripts/print-rule.sh`, one hook per file, front matter stripped):
  1. **Session start** (`startup`, `clear`, `compact`): `core` prints `working-agreement.md` and its `rules/*.md` (`architecture-principles`, `architecture-principles-code`, `same-level-dependencies`, `minimal-change`, `delivery`); each stack plugin prints its `rules/*.md`. Not on `resume` — the resumed transcript already holds them.
  2. **Subagent start**: the same rules (without the agreement; `core:developer` also without `delivery`) go to `core:developer`, `core:reviewer`, and the built-in `Plan` as `additionalContext` JSON — plain stdout does not reach a subagent. `Plan` also gets the repository rules; `flutter:qa` gets only the `dart` and `ui` rules (accessibility thresholds and the platform look). Other subagents (`Explore`) do not need them.
- **Size limit**: Claude Code caps one hook's output at 10,000 characters and replaces anything longer with a 2,000-character preview, so every rule file and the working agreement stay under 9,000 characters (checked by `tests/run.sh`). A rule that outgrows it is split by topic or moves its procedure into a skill.
- **Edit feedback**: `check-edited-file.sh` runs after every edit, in subagents too, and reports analyzer / ESLint / gofmt and `go vet` errors in the edited file only.

## Enabling it in a repository

In Claude Code, ask to adopt agent-kit: the `adopting-agent-kit` skill inventories the repository's existing agent setup, sorts it into kit / `CLAUDE.md` / `.claude/rules/` / `.claude/skills/`, and writes the files below. Minimal manual setup, `.claude/settings.json`:

```json
{
  "env": { "FORCE_AUTOUPDATE_PLUGINS": "1" },
  "extraKnownMarketplaces": {
    "agent-kit": {
      "source": { "source": "git", "url": "https://github.com/ddvhn/agent-kit.git" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "core@agent-kit": true,
    "flutter@agent-kit": true
  }
}
```

A Go backend enables `core`, `backend`, and `go`; a Functions backend `core`, `backend`, and `firebase-functions`. Listing the dependencies explicitly keeps the settings readable, though Claude Code would add them. A repository with both an app and `functions/` enables both stacks. `autoUpdate` turns on auto-update for everyone who opens the repository; `FORCE_AUTOUPDATE_PLUGINS` keeps it on where the Claude desktop app sets `DISABLE_AUTOUPDATER=1` for its bundled CLI, which would otherwise skip plugin updates too.

Then write `CLAUDE.md` with the sections above and put project conventions in `.claude/rules/`.

## Cloud sessions

Cloud sessions (Claude Code on the web, the desktop app, and project threads on claude.ai) run in a container built from a **cloud environment**. When a session starts above the repositories, which is how cloud sessions over several repositories start, the container does not read `.claude/settings.json`. Install the kit in the environment's setup script instead.

1. Open the cloud environment's settings. In a claude.ai project: Project settings → Cloud environment → the gear beside the selected environment. For a standalone session: the environment picker → the gear beside the environment.
2. Paste into **Setup script**:

   ```bash
   exec >~/agent-kit-setup.log 2>&1
   set -x
   date
   claude plugin marketplace add ddvhn/agent-kit || true
   for p in $(python3 -c "import json,os;print(' '.join(p['name'] for p in json.load(open(os.path.expanduser('~/.claude/plugins/marketplaces/agent-kit/.claude-plugin/marketplace.json')))['plugins']))"); do claude plugin install "$p@agent-kit" || true; done
   ```

   The script installs every plugin listed in the marketplace, so a new plugin needs no change here. Stack plugins stay silent where their stack is absent. The log goes to `~/agent-kit-setup.log`.
3. Select that environment in every project or session that should get the kit. Environments belong to the account, not the project: one environment serves every project that selects it, and an edit to its script reaches all of them.
4. Start a new session and check that the working agreement is in its context.

If the kit is missing in a new session, check two things:

- Whether the project has the environment selected. Without one, sessions run on the default environment and the script never runs.
- Whether the script was skipped. A new session can resume from a cached container; `/tmp/env-manager.log` then says "Fast resume … Skipping initialization script", and `~/agent-kit-setup.log` is missing. Any edit to the setup script invalidates the cache, so the next session runs it.

## One-time setup per machine

1. `jq` installed (preinstalled on recent macOS), and `git`: Claude Code clones this public repository over HTTPS, so no key or sign-in is needed.
2. Open Claude Code in a repository that enables the kit and accept the trust prompt; it registers the marketplace and loads the enabled plugins.
3. Nothing else: Claude Code refreshes the kit within ten minutes after the first message of a session and applies the new version at the next start (or `/reload-plugins`). To pull a change right away: `/plugin marketplace update agent-kit`.

## Changing the kit

This is the kit repository's own process, not the branch model projects follow (`delivery` rule). Every push to `main` reaches every machine at its next session, and kit hooks run as shell scripts there. Keep `main` protected (GitHub → Settings → Branches) and the maintainer list short.

1. Enable the pre-commit check once per clone: `git config core.hooksPath .githooks`, and install `shellcheck` (`brew install shellcheck`). Optionally add `tests/forbidden.local` with the names of the projects you use the kit in. The check runs `tests/run.sh`:
   - plugin validation, JSON and script syntax, shellcheck;
   - skill / agent / rule front matter, unique skill names, description length, every rule under 9,000 characters;
   - every rule printed by a SessionStart and a SubagentStart hook, identical `print-rule.sh` copies, subagent matchers naming real agents;
   - agent tools: `developer` and `reviewer` can load skills, `reviewer` and `qa` cannot edit;
   - references: no removed paths or names (extend the list in the test when renaming), every referenced skill and `plugin:agent` exists; no project names from `tests/forbidden.local`;
   - the sync script and the hook outputs against sample repositories, including repository rules and plugin dependencies (a repository enabling only `go` gets `backend` and `core`).
2. Try changes before pushing, from a repository that uses the kit: `claude --plugin-dir ../agent-kit/plugins/core --plugin-dir ../agent-kit/plugins/flutter` (a Go backend: `core`, `backend`, `go`) (the sync then uses this local kit; or set `AGENT_KIT_DIR`).
3. Changed the agreement, a rule, a skill or agent description, or a hook? Run the behavior evals (real model calls, not part of pre-commit):
   ```
   claude plugin eval . --eval-dir evals --ablation none --runs 1 --model sonnet --no-publish --max-cost-usd 5
   ```
   Cases live in `evals/core/`, `evals/flutter/`, `evals/backend/`, and `evals/go/` (each names the plugins it loads), outside the plugins so they do not ship to installed copies. They check that the agreement and rules reach the main session and `developer`, that review and feature requests load `reviewing-branch` and `delivering-changes`, that the `delivery` rule reaches the session, and that a review round loads `running-review-loop`. A single failure is often model noise — re-run that case with `--case <name> --runs 3`. Results go to `evals/results/` (git-ignored).
4. Commit and push to `main`. There is no `version` field on purpose: every commit is a new version, and auto-update delivers it to every repository — the pre-commit check and the evals are the gate.
5. Vendored third-party skills keep a `SOURCE.md` (upstream, commit, local changes); re-apply local changes when updating from upstream.
6. Now and then: `claude plugin details core` (and the stack plugins) shows the always-on token cost; `/skill-doctor` lists skills that never run — drop or merge them.
