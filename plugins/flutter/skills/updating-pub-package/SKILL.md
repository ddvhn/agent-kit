---
name: updating-pub-package
description: Safely update a Dart/Flutter pub package by checking pub.dev for the latest version, reading release notes, and handling minor vs major upgrades differently. For minor updates, just do it. For major updates, find the upgrade guide, validate breaking changes, and produce a detailed migration report.
---

# Updating a pub package

Use this skill when the user asks to update, upgrade, or bump a specific pub dependency.

## Steps

1. **Check the current version** — read the relevant `pubspec.yaml` (root workspace and/or package `pubspec.yaml`):

   ```bash
   flutter pub deps | grep <package-name>
   ```

2. **Find the latest version on pub.dev** — fetch package info / changelog:

   ```
   Search: "pub.dev <package-name>"
   ```

3. **Determine the update type** — compare current version to latest:
   - **Patch** (1.2.3 → 1.2.4): bug fixes only
   - **Minor** (1.2.3 → 1.3.0): new features, backwards compatible
   - **Major** (1.2.3 → 2.0.0): breaking changes
   - **0.x packages**: the minor is the breaking position (0.3.1 → 0.4.0 is a major update; 0.3.1 → 0.3.2 is a minor one), as the caret constraint `^0.3.1` also treats it

4. **For patch or minor updates** — just do it:

   ```bash
   flutter pub upgrade <package-name>
   ```

   This stays within the `pubspec.yaml` constraint; if the target is outside it but still non-breaking, raise the lower bound (`^1.3.0`) and run `flutter pub get`.

   Then analyze and test:

   ```bash
   flutter analyze && flutter test   # or the commands in CLAUDE.md → Verification
   ```

   If everything passes, report what changed. Commit only if the user asked.

5. **For major updates** — investigate first:

   a. Fetch changelog / migration guide (`CHANGELOG.md`, pub.dev, GitHub releases).
   b. Identify every breaking change between current and target (removed APIs, signature changes, Flutter/Dart SDK mins, peers).
   c. Scan usages:

   ```bash
   rg "package:<package-name>" --glob "*.dart"
   ```

   d. Apply the version bump in the owning `pubspec.yaml` (respect workspace `resolution` and root `dependency_overrides`).
   e. `flutter pub get`, then fix call sites.
   f. Verify: the analyze and unit commands from `CLAUDE.md` → Verification.
   g. Produce a migration report (breaking changes applied, files, validation).

## Notes

- In a **pub workspace** (or a repo with several packages), a dependency may be declared in several `pubspec.yaml` files — update them together.
- `dependency_overrides` exist for a reason (see the comment beside each and `CLAUDE.md` → Project nuances). Do not silently unpin or add overrides.
- Prefer `flutter pub upgrade <name>` over `--major-versions` unless the user asked for majors.
- Lockfile (`pubspec.lock`) changes are expected — commit them with the update when asked.
