---
name: updating-go-dependency
description: Update one Go module dependency or tool safely — read the current and latest versions, classify the bump (v0 minors and any new major path are breaking), read the changelog, update with go get and go mod tidy, fix usages, regenerate code when a generator changed, run govulncheck and make check, and report. Use when the user asks to update, upgrade, or bump a Go module, a pinned code generator or linter, or the Go toolchain.
---

# Updating a Go dependency

Run from the module root. Checks: `CLAUDE.md` → Verification.

1. **Current and latest**: `go list -m <module>` and `go list -m -u <module>`; for a tool pinned in the Makefile, read its line and the releases page.
2. **Classify**: a patch or minor of a `v1+` module is non-breaking by Go's import compatibility rule; a minor of a `v0` module and any new major (a new import path `…/v2`) are breaking. Toolchain bumps (`go` and `toolchain` lines in `go.mod`) are breaking for the build image and CI too.
3. **Read the changelog** between the two versions for breaking changes, deprecations, security fixes, and new minimum Go versions. For code generators (oapi-codegen, sqlc) and linters, expect generated or reported diffs.
4. **Update**:
   - module: `go get <module>@<version>` (new major: change the import paths), then `go mod tidy`;
   - pinned tool: change the version in the Makefile, then `make generate` and review the generated diff (it should be mechanical);
   - toolchain: the `go` line in `go.mod`, the build image in the `Dockerfile`, and the README prerequisites together.
5. **Fix usages** of every changed API (grep the old symbols); do not suppress new lint findings, fix them or explain each `//nolint` with a reason.
6. **Verify**: `go build ./...`, `make check-generated lint test` (and `cover`), `govulncheck ./...`.
7. **Report**: old → new version, breaking or not and why, what changed in code and generated output, checks run and their results, anything deferred.

One dependency per change unless they must move together (a library and its driver, a generator and its runtime).
