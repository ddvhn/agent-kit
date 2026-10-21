---
name: adopting-agent-kit
description: Set up a repository to use agent-kit, or migrate a repository's own agent setup (CLAUDE.md, AGENTS.md, .claude rules / skills / agents / hooks, .cursor rules and skills, .agents skills) onto the kit — inventory, classify what the kit already covers, write CLAUDE.md, .claude/rules, settings, and verify. Use when the user wants the kit in a new or existing repository, or asks to clean up or move agent instructions.
---

# Adopting agent-kit in a repository

Goal: the repository keeps only what is specific to it; everything generic comes from the kit. The split is in the working agreement → Where configuration lives, and in the kit README → Kit and repository.

## 1. Inventory

List every agent-facing file and folder that exists:

- `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, `README.md` (AI agents section)
- `.claude/` — `settings.json`, `rules/`, `skills/`, `agents/`, `hooks/`, `commands/`
- `.cursor/` — `rules/`, `skills/`, `commands/`, `mcp.json`, `settings.json`
- `.agents/skills/`, `skills-lock.json`, `.mcp.json`
- `docs/` (feature specs, `decisions/`)

## 2. Classify every piece

Read each rule and skill and put every paragraph in exactly one bucket:

| Bucket | Goes to |
| --- | --- |
| The kit already says it (working agreement, `minimal-change`, a stack rule or skill) | delete |
| A fact: platform, apps, entry points, branches, suites, commands, ports, accounts, review zones, neighbors to copy | `CLAUDE.md` |
| A project convention on top of a kit rule: real names, paths, helpers, chosen libraries, allowed exceptions | `.claude/rules/<topic>.md` (topics mirror the kit rules: `architecture`, `dart`, `testing`, `data`, …) |
| A procedure only this repository needs (a pipeline, a release, a design system) | `.claude/skills/<gerund-name>/SKILL.md` |
| Generic and missing from the kit | propose a kit change to the user; until it lands, keep it in `.claude/rules/` |
| A vendored upstream skill the kit does not ship | `.claude/skills/` with its `LICENSE` and `SOURCE.md` |
| Feature behavior or a past decision | `docs/` (`recording-decisions`) |
| Contradicts the kit | ask the user: repository exception (in `.claude/rules/`, stated as an exception) or drop |

Show the user the classification (what is deleted, moved, kept, proposed for the kit) before deleting anything.

## 3. Settings

`.claude/settings.json` — merge into what exists:

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
  },
  "permissions": {
    "deny": [
      "Read(**/.env)", "Read(**/.env.*)", "Read(**/*.secret.local)",
      "Read(**/service-account*.json)", "Read(**/*-firebase-adminsdk-*.json)",
      "Read(**/*.jks)", "Read(**/*.keystore)", "Read(**/key.properties)",
      "Bash(git push --force*)", "Bash(git push -f*)", "Bash(firebase deploy*)"
    ],
    "allow": ["Bash(git diff*)", "Bash(git status*)", "Bash(git log*)", "Bash(git show*)"]
  }
}
```

- Stack plugins: `flutter@agent-kit` for Flutter apps; for a backend `backend@agent-kit` plus its stack, `go@agent-kit` for Go or `firebase-functions@agent-kit` for Firebase Functions (they depend on `backend`; list it anyway). A repository holding both (an app plus `functions/`) enables both; the default is separate repositories, linked in Related repositories on both sides.
- Deny reading every secret file the repository has (check its `.gitignore`); deny deploys and force-pushes. Exclude committed example files from the deny patterns only if the agent needs them.
- Allow the read-only and verification commands listed in `CLAUDE.md` → Verification so they run without prompts.
- MCP servers the stack uses go to `.mcp.json`, and their names to `enabledMcpjsonServers` in `.claude/settings.json` (Flutter: `["dart", "marionette"]`) so nobody is asked to approve them. Flutter example:

```json
{
  "mcpServers": {
    "dart": {
      "command": "dart",
      "args": ["mcp-server", "--disable", "create_project", "--disable", "flutter_driver"]
    },
    "marionette": { "command": "dart", "args": ["run", "marionette_mcp"] }
  }
}
```

  `marionette_mcp` is a dev dependency of the app (`dart run` resolves it there); add `patrol` only when the project configures the MCP runner (`setting-up-patrol`).

`.gitignore`:

```
# Claude Code personal overrides
.claude/settings.local.json
CLAUDE.local.md
```

Delete old generated or copied rule and skill folders the kit now replaces (`.cursor/` rules, skills, and `mcp.json`, `AGENTS.md` that only points to them, `.agents/skills/*` duplicates, `skills-lock.json` entries for skills the kit now replaces; a repository-only upstream skill stays in `.claude/skills/` with its `LICENSE` and `SOURCE.md`). A `.cursor/skills/` that held hand-written skills: move those to `.claude/skills/` first.

## 4. `CLAUDE.md`

```markdown
# <Project>

<One paragraph: what it is, stack, packages / layers, entry points.>

How we work — the working agreement, workflow, subagents, skills, and stack rules — comes from the `agent-kit` plugins `core`, `backend` for a backend, and `<stack>` (`.claude/settings.json`). Project conventions on top of the kit rules are in `.claude/rules/`; this file holds the project facts. If the working agreement is not in your context, the kit is not installed: tell the user (README → AI agents).

## Project facts
- **Platform / apps:** … (entry points, e.g. `lib/main.dart` or `apps/<name>/lib/main.dart`)
- **Packages:** … (e.g. `modules/{domain,data,ui,utils,logger,localization}`)
- **Integration branch:** `develop` (everything is cut from and lands in it; an existing "Main branch" field means the same); **Release branch:** `main` (releases only; production deploys from it). Name others only when the project differs — `delivery` rule → Branches
- **Merge policy:** "default" (push, PRs, and merges only when the user asks), or what the agent may push, open, and merge itself once the checks pass and the review loop has ended, and the critical changes that still wait for the user (for example money, paid-service spend, "ask first" items, production access) — `delivery` rule → Merge policy
- **Environments:** which branch deploys where (default as in the rule: local on any branch with fakes and the demo seed; optional preview for task / feature branches, or "preview: off"; staging auto-deployed from `develop`; production from `main` with a `vX.Y.Z` tag after a manual approval), backend and web images promoted staging → production without rebuilding (app builds per environment from the tagged commit), staging data synthetic only, per-environment app builds and the backend each points to (the stack plugin says how), the hotfix flow, and the deploy windows (peak hours with no production deploy) — `delivery` rule → Environments
- **Critical zones:** areas whose mistakes cause financial or security damage and get up to 10 review rounds instead of 5 (default: money, billing, and payments; paid-service spend; auth and security); separate from the critical changes in the Merge policy, though a project may list the same areas in both — `delivery` rule → Review loop
- **Parallel tasks:** how many tasks may be in flight at once (in progress or in review), each independent of every other task in flight; default 3 — `shipping-feature-branch` → Per task, step 9
- **Tech-debt list:** where non-blocking review findings go after round 3 (a file, an issue label, or "a section in the PR"); a thread moved there is resolved with a link to its row
- **Required PR sections:** extra sections every PR carries, or "none"; for Load, the load profile and performance targets it is measured against; for Compliance, the markets it is checked for (`shipping-feature-branch` → PR description)
- **Flavors and defines:** … (names, define files, which config is production)
- **Test suites:** … (unit per package, integration / E2E folder, device)
- **Live app:** launch configs (the agent config with the fixed VM-service port), Marionette URI, backend it talks to (stage or local emulators — never production), test account to use
- **UI skill:** … (the repository's design skill in `.claude/skills/`, or "none: follow neighbors and the theme")
- **Stack levels:** the levels the stack rules read, with their defaults (for Flutter: "Web", "Offline writes", "Sync", "Device signatures", "Analytics" — `scaffolding-flutter-app` step 4; a backend names multi-tenancy and its platform)
- **Markets:** where the product runs, for the Compliance section and the security rules
- **Neighbors to copy:** …
- **Review zones** (independent review): …

## Verification
Narrowest first: static check, unit, integration / E2E, codegen commands. The coverage gate and its exclusion list (coverage never drops in a PR), and the git hooks that run the checks locally (no CI is assumed). How paid providers are faked in tests, and the manual live smoke command with its spend cap, if the project has paid providers.

## Project nuances
Exceptions to the kit rules and project-only "ask first" items.

## Specs
Feature docs in `docs/` (one line each).

## Related repositories
Backends, clients, shared modules; how to open them together (`claude --add-dir …`).
```

Keep it facts only; no workflow or style rules (those are kit or `.claude/rules/`).

### Git hooks

No CI is assumed, so the hooks are the gate: a setup script or make target sets `core.hooksPath` to a committed hooks folder. Default: **pre-commit** runs the formatter, the static check, and a secret scanner (for example `gitleaks`) on staged files; **pre-push** runs the full local check from Verification (static check, codegen up to date, tests, coverage gate). The live smoke is never in a hook. Nobody skips them with `--no-verify`.

## 5. README

- `README.md` is the newcomer's guide and changes in the same PR as what it describes: prerequisites and tool versions, configuration, running locally, tests and checks, code generation, builds, and deploy once environments exist.
- `README.md` → "AI agents": where the setup comes from, one-time setup per machine (install Claude Code, `jq`, read access to the kit repository (none needed when it is public), stack tools such as the Patrol CLI, run `claude` and accept the trust prompt), how updates arrive, personal overrides.

## 6. Verify

1. Every `.claude/rules/*.md` has front matter (`description:`, optional `paths:`) and stays under 9,000 characters.
2. Grep the repository for references to deleted files, old skill names, and old marketplaces; fix them.
3. Ask the user to start a new Claude Code session and check: the working agreement is in context, `core:developer` gets the rules, the commands in `CLAUDE.md` → Verification run.

Commit as one change ("Move agent setup to agent-kit") only when the user asks; stage only these files, never unrelated work in the tree.
