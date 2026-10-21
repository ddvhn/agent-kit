#!/bin/bash
# SubagentStart hook for the built-in Plan agent: gives it the repository's own
# rules (.claude/rules/*.md, front matter stripped) as additionalContext. Claude
# Code loads those rules natively into the main session and into plugin
# subagents, but Plan starts without CLAUDE.md and project rules.
# Rules that would push the output past the 10,000-character hook cap are
# listed by path for Plan to read instead.
# Usage: print-project-rules.sh
command -v jq >/dev/null 2>&1 || exit 0
project=${CLAUDE_PROJECT_DIR:-$PWD}
dir="$project/.claude/rules"
[ -d "$dir" ] || exit 0
limit=9000
body=
skipped=
while IFS= read -r f; do
  text=$(awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm { if ($0 == "---") fm = 0; next }
    !started && /^[[:space:]]*$/ { next }
    { started = 1; print }
  ' "$f")
  if [ $(( ${#body} + ${#text} )) -lt "$limit" ]; then
    body+="$text"$'\n\n'
  else
    skipped+="- ${f#"$project"/}"$'\n'
  fi
done < <(find "$dir" -name '*.md' -type f | sort)
[ -n "$body$skipped" ] || exit 0
if [ -n "$skipped" ]; then
  body+="# More project rules"$'\n\n'"Read these before planning; they did not fit here:"$'\n'"$skipped"
fi
jq -n --arg context "$body" '{hookSpecificOutput: {hookEventName: "SubagentStart", additionalContext: $context}}'
