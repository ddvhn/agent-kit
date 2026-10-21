#!/bin/bash
# Prints one of this plugin's rules/<name>.md without its front matter: plain
# text for a SessionStart hook, or with --subagent the SubagentStart JSON
# (plain stdout does not reach a subagent). Every kit plugin with rules keeps an
# identical copy (checked by tests/run.sh).
# A stack plugin prints nothing when its stack is absent: its stack-markers
# file lists "<file name> <extended regex>" pairs, and the stack is present
# when a file of that name under the project folder (the repository, or the
# folder that holds several) matches the regex. Plugins without the file
# always print.
# Usage: print-rule.sh <rule-name> [--subagent]
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [ -f "$root/stack-markers" ]; then
  project=${CLAUDE_PROJECT_DIR:-$PWD}
  present=
  while read -r file pattern; do
    case "$file" in ''|'#'*) continue ;; esac
    find "$project" -maxdepth 4 \( -name .git -o -name node_modules -o -name .dart_tool -o -name build \) -prune \
      -o -type f -name "$file" -print0 2>/dev/null | xargs -0 -r grep -lE -- "$pattern" 2>/dev/null | grep -q . && { present=1; break; }
  done < "$root/stack-markers"
  [ -n "$present" ] || exit 0
fi
body=$(awk '
  NR == 1 && $0 == "---" { fm = 1; next }
  fm { if ($0 == "---") fm = 0; next }
  !started && /^[[:space:]]*$/ { next }
  { started = 1; print }
' "$root/rules/$1.md") || exit 0
if [ "${2:-}" = --subagent ]; then
  command -v jq >/dev/null 2>&1 || exit 0
  jq -n --arg context "$body" '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $context}}'
else
  printf '%s\n' "$body"
fi
