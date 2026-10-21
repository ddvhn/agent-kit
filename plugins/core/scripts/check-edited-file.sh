#!/bin/bash
# PostToolUse hook: after Claude edits a file, report analyzer/lint ERRORS in
# that file only (warnings/infos are ignored so legacy files do not trigger
# drive-by fixes). Exit 2 feeds the errors back to Claude; anything else is silent.
command -v jq >/dev/null 2>&1 || exit 0
f=$(jq -r '.tool_input.file_path // empty')
[ -n "$f" ] && [ -f "$f" ] || exit 0

case "$f" in
  *.g.dart|*.freezed.dart|*.mocks.dart|*/generated/*|*/build/*|*/.dart_tool/*|*/node_modules/*) exit 0 ;;
  *.dart)
    command -v dart >/dev/null 2>&1 || exit 0
    out=$(dart analyze --no-fatal-warnings "$f" 2>&1) || {
      echo "dart analyze found errors in $f:" >&2
      echo "$out" | grep -E '^\s*error' >&2 || echo "$out" | tail -20 >&2
      exit 2
    } ;;
  *.ts)
    # Lint with the nearest package that has ESLint installed.
    dir=$(dirname "$f")
    while [ "$dir" != "/" ] && [ ! -x "$dir/node_modules/.bin/eslint" ]; do
      dir=$(dirname "$dir")
    done
    [ -x "$dir/node_modules/.bin/eslint" ] || exit 0
    out=$(cd "$dir" && ./node_modules/.bin/eslint --quiet "$f" 2>&1) || {
      echo "eslint found errors in $f:" >&2
      echo "$out" | tail -30 >&2
      exit 2
    } ;;
  */vendor/*.go) ;;
  *.go)
    command -v gofmt >/dev/null 2>&1 || exit 0
    head -5 "$f" | grep -q '^// Code generated .* DO NOT EDIT\.$' && exit 0
    out=$(gofmt -e -l "$f" 2>&1 >/dev/null)
    [ -z "$out" ] || { echo "gofmt found syntax errors in $f:" >&2; echo "$out" | head -20 >&2; exit 2; }
    # Type errors of the package (go vet prints them as "vet: ./file.go:…"), reported only for the
    # edited file; vet's analyzer findings are warnings and ignored like the other analyzers'.
    # No module downloads (GOPROXY=off) and no go.mod rewrites (-mod=readonly, which also ignores vendor/).
    command -v go >/dev/null 2>&1 || exit 0
    out=$(cd "$(dirname "$f")" && GOFLAGS=-mod=readonly GOPROXY=off go vet . 2>&1 | grep -E "^vet: .*/$(basename "$f" | sed 's/[.]/[.]/g'):")
    [ -z "$out" ] || { echo "go found type errors in $f:" >&2; echo "$out" | head -30 >&2; exit 2; } ;;
esac
exit 0
