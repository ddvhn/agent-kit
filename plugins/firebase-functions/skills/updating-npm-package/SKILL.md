---
name: updating-npm-package
description: Update one npm dependency safely — read the installed and published versions, classify the bump (0.x minors and any major are breaking), install within the current major for non-breaking bumps, and for breaking bumps read the upgrade guide, fix every affected usage, verify, and report. Use when the user asks to update, upgrade, or bump an npm package.
---

# Updating an npm package

Run every command from the package directory that owns the dependency (for a Firebase backend, usually `functions/`). Build, lint, and test commands: `CLAUDE.md` → Verification.

## 1. Versions

```bash
npm ls <pkg>                        # installed version
npm outdated <pkg>                  # Current / Wanted (within the package.json range) / Latest
npm view <pkg> dist-tags --json     # latest, next, …
```

## 2. Classify the bump

| From → to | Kind |
| --- | --- |
| `1.2.3 → 1.2.4`, `1.2.3 → 1.3.0` | non-breaking (same major) |
| `1.x → 2.x` | breaking |
| `0.3.1 → 0.3.2` | non-breaking (same 0.minor) |
| `0.3.x → 0.4.0` | **breaking** — in 0.x a minor bump may break the API |
| `0.0.3 → 0.0.4` | **breaking** — every 0.0.x release may break |

Pre-releases (`-beta`, `-rc`) only when the user asks. For `firebase-functions`, `firebase-admin`, and `firebase-tools`, also check the Node `engines` the new version needs and the Functions runtime the project deploys.

## 3. Non-breaking bump

Install the newest version **within the current major** (or the current 0.minor) — never `@latest`, which can cross a major:

```bash
npm install <pkg>@^<current-major>    # e.g. npm install zod@^3   (0.x: npm install <pkg>@~0.<minor>)
```

Then lint, typecheck, build, and the suites the package touches. If everything passes, report old → new. Do not commit unless asked.

## 4. Breaking bump

1. **Upgrade guide.** Read the package's `CHANGELOG.md`, `MIGRATION.md`, GitHub releases, or official upgrade guide for every version between current and target.
2. **Breaking changes.** List each one: removed or renamed APIs, changed signatures or return types, dropped Node versions, new peer dependencies, changed defaults, config format changes.
3. **Impact.** Find every usage and check it against the list:

   ```bash
   grep -rn "from [\"']<pkg>" src test
   grep -rn "require([\"']<pkg>" src test
   ```

4. **Install** the target major: `npm install <pkg>@^<target-major>` (0.x: `@~0.<target-minor>`). Run the package's codemod if it ships one.
5. **Fix** each affected usage file by file, following the guide. Peer packages that must move together (`@types/<pkg>`, plugins) move in the same change.
6. **Verify**: lint, typecheck, unit and integration suites, build (`CLAUDE.md` → Verification).
7. **Report**:

   ```markdown
   ## <pkg> <old> → <new> (breaking)

   ### Breaking changes applied
   - `oldFoo()` renamed to `newFoo()` — 3 files
   - Node 18 dropped — the project's `engines` is already 22

   ### Files changed
   - src/core/foo/acmeFooService.ts — new client constructor
   - package.json, package-lock.json

   ### Verification
   - lint, typecheck, build: pass
   - unit 120 / 120, integration 85 / 85
   ```

## Notes

- Check peer-dependency warnings from `npm install`; resolve them, do not `--force` or `--legacy-peer-deps` without asking.
- In a workspace monorepo, update every workspace that uses the package together.
- `package-lock.json` changes belong to the update.
