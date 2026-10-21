#!/bin/bash
# SessionStart hook: when the session starts above the repositories (a folder
# that holds several of them, as cloud sessions over several repositories do),
# Claude Code loads each repository's CLAUDE.md but not its .claude/rules or
# .claude/skills. This lists them per repository, with the paths each rule
# covers, so the session reads the matching file before working there. Prints
# nothing when the session starts inside a repository.
# Usage: print-nested-repositories.sh
project=${CLAUDE_PROJECT_DIR:-$PWD}
[ -e "$project/.git" ] && exit 0
limit=9000
out=
while IFS= read -r repo; do
  rel=${repo#"$project"/}
  section=
  while IFS= read -r f; do
    paths=$(awk '
      NR == 1 && $0 == "---" { fm = 1; next }
      fm && $0 == "---" { exit }
      fm && /^paths:/ { inpaths = 1; next }
      fm && inpaths && /^[[:space:]]*-/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/"/, ""); printf "%s`%s`", sep, $0; sep = ", "; next }
      fm && inpaths { inpaths = 0 }
    ' "$f")
    section+="- \`$rel/${f#"$repo"/}\`: ${paths:-every file}"$'\n'
  done < <(find "$repo/.claude/rules" -name '*.md' -type f 2>/dev/null | sort)
  while IFS= read -r f; do
    section+="- skill \`$rel/${f#"$repo"/}\`"$'\n'
  done < <(find "$repo/.claude/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f 2>/dev/null | sort)
  [ -n "$section" ] || continue
  entry="## $rel"$'\n\n'"$section"$'\n'
  [ $(( ${#out} + ${#entry} )) -lt "$limit" ] || break
  out+="$entry"
done < <(find "$project" -mindepth 2 -maxdepth 3 -name .git -not -path '*/node_modules/*' 2>/dev/null | xargs -r -n1 dirname | sort)
[ -n "$out" ] || exit 0
printf '# Repository rules and skills\n\nThis session started above these repositories, so their .claude/rules and .claude/skills are not loaded. Before reading or editing files in a repository, read its rules whose paths (relative to that repository) match; use a listed skill by reading its SKILL.md when the task fits.\n\n%s' "$out"
exit 0
