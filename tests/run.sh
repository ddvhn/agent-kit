#!/bin/bash
# Kit self-check. Run by the pre-commit hook (.githooks/pre-commit).
# Usage: tests/run.sh   (from anywhere)
set -uo pipefail
kit=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0
ok()   { echo "  ok    $1"; }
bad()  { echo "  FAIL  $1"; failures=$((failures + 1)); }
skip() { echo "  skip  $1"; }

echo "Manifests"
if command -v claude >/dev/null 2>&1; then
  for target in "$kit" "$kit"/plugins/*/; do
    out=$(claude plugin validate "$target" 2>&1)
    echo "$out" | grep -q "Validation passed" && ok "validate ${target#$kit/}" || { bad "validate ${target#$kit/}"; echo "$out" | tail -15; }
  done
else
  skip "claude plugin validate (claude CLI not installed)"
fi
while IFS= read -r json; do
  jq empty "$json" 2>/dev/null && ok "json ${json#"$kit"/}" || bad "json ${json#"$kit"/}"
done < <(find "$kit" -name '*.json' -not -path '*/.git/*' -not -path '*/evals/results/*')

echo "Scripts"
while IFS= read -r script; do
  bash -n "$script" && ok "syntax ${script#"$kit"/}" || bad "syntax ${script#"$kit"/}"
done < <(find "$kit" -name '*.sh' -not -path '*/.git/*'; echo "$kit/.githooks/pre-commit")
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning "$kit"/plugins/*/scripts/*.sh "$kit"/tests/run.sh >/dev/null && ok "shellcheck" || bad "shellcheck"
else
  skip "shellcheck (not installed)"
fi

echo "Skills, agents, rules"
names=
for f in "$kit"/plugins/*/skills/*/SKILL.md; do
  dir=$(basename "$(dirname "$f")")
  name=$(sed -n '2s/^name: //p' "$f")
  [ "$name" = "$dir" ] || bad "skill name '$name' != folder '$dir'"
  desc=$(sed -n 's/^description: //p' "$f")
  [ -n "$desc" ] || bad "skill $dir has no description"
  [ ${#desc} -le 1024 ] || bad "skill $dir description is ${#desc} chars; keep it under 1024"
  names+="$name"$'\n'
done
dupes=$(printf '%s' "$names" | sort | uniq -d)
[ -z "$dupes" ] && ok "skill names unique across plugins" || bad "duplicate skill names: $dupes"
for f in "$kit"/plugins/*/agents/*.md; do
  grep -q '^name: ' "$f" && grep -q '^description: ' "$f" && ok "agent $(basename "$f")" || bad "agent $(basename "$f") front matter"
done
for f in "$kit"/plugins/*/rules/*.md; do
  [ "$(head -1 "$f")" = "---" ] && grep -q '^description: ' "$f" && ok "rule ${f#$kit/plugins/}" || bad "rule ${f#$kit/plugins/} front matter"
done
for f in "$kit/plugins/core/working-agreement.md" "$kit"/plugins/*/rules/*.md; do
  size=$(wc -c < "$f")
  [ "$size" -lt 9000 ] && ok "fits the 10k hook cap: ${f#$kit/plugins/} ($size chars)" || bad "${f#$kit/plugins/} is $size chars; keep it under 9000 (split it or move procedure into a skill)"
done
for dir in "$kit"/plugins/*/rules; do
  plugin=$(basename "$(dirname "$dir")")
  hooks="$kit/plugins/$plugin/hooks/hooks.json"
  cmp -s "$kit/plugins/core/scripts/print-rule.sh" "$kit/plugins/$plugin/scripts/print-rule.sh" \
    && ok "$plugin: print-rule.sh matches core's" || bad "$plugin: scripts/print-rule.sh missing or differs from core's"
  for f in "$dir"/*.md; do
    name=$(basename "$f" .md)
    for event in SessionStart SubagentStart; do
      suffix=$([ $event = SubagentStart ] && echo " --subagent")
      jq -e --arg c "print-rule.sh\" $name$suffix" "[.hooks.${event}[]?.hooks[].command | endswith(\$c)] | any" "$hooks" >/dev/null 2>&1 \
        && ok "$plugin: $event hook prints $name" || bad "$plugin: no $event hook prints $name"
    done
  done
done
for f in "$kit"/plugins/*/hooks/hooks.json; do
  for agent in $(jq -r '.hooks.SubagentStart[]?.matcher' "$f" | tr '|' '\n' | grep ':'); do
    [ -f "$kit/plugins/${agent%%:*}/agents/${agent#*:}.md" ] && ok "SubagentStart matcher agent $agent exists" || bad "SubagentStart matcher names missing agent $agent ($f)"
  done
done
tools() { sed -n "s/^$2: //p" "$kit/plugins/$1.md" | tr -d ' ' | tr ',' '\n'; }
for agent in core/agents/developer core/agents/reviewer; do
  tools "$agent" tools | grep -qx Skill && ok "$(basename $agent) can load skills" || bad "$(basename $agent) has no Skill tool"
done
tools core/agents/reviewer tools | grep -qxE 'Edit|Write' && bad "reviewer can edit" || ok "reviewer has no Edit/Write"
[ "$(tools flutter/agents/qa disallowedTools | grep -cxE 'Edit|Write')" = 2 ] && ok "qa cannot edit" || bad "qa must disallow Edit and Write"

echo "References"
text=$(find "$kit/plugins" "$kit/README.md" -name '*.md' -not -path '*/evals/*')
# Paths and names that no longer exist; grow this list when something is renamed.
end='([^a-z-]|$)'
removed="setup-cursor-skills|(^|[^a-z-])(creating-repositories|running-localization-pipeline|patrol-testing|localization-flutter|localization-functions|testing-flutter|testing-functions|auditing-security|auditing-performance|firestore-operations|architect|junior)$end"
stale=$(echo "$text" | xargs grep -nE "$removed")
[ -z "$stale" ] && ok "no references to removed paths or names" || { bad "references to removed paths or names:"; echo "$stale" | sed 's/^/        /'; }
skills=$(find "$kit"/plugins/*/skills -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)
missing=$(echo "$text" | xargs grep -ohE '`[a-z]+ing-[a-z-]+`' | tr -d '`' | sort -u | while read -r ref; do echo "$skills" | grep -qx "$ref" || echo "$ref"; done)
[ -z "$missing" ] && ok "every referenced skill exists" || bad "referenced skills that do not exist: $(echo $missing)"
missing=$(echo "$text" | xargs grep -ohE '`(core|flutter|firebase-functions|backend|go):[a-z-]+`' | tr -d '`' | sort -u | while read -r ref; do
  p=${ref%%:*}; n=${ref#*:}
  [ -f "$kit/plugins/$p/agents/$n.md" ] || [ -d "$kit/plugins/$p/skills/$n" ] || echo "$ref"
done)
[ -z "$missing" ] && ok "every namespaced agent or skill exists" || bad "namespaced references that do not exist: $(echo $missing)"

# Project names must not leak into the kit. The list is per maintainer and
# git-ignored: one extended regex per line in tests/forbidden.local.
forbidden="$kit/tests/forbidden.local"
if [ -f "$forbidden" ]; then
  pattern=$(grep -v '^[[:space:]]*\(#\|$\)' "$forbidden" | paste -sd'|' -)
  leaks=$([ -n "$pattern" ] && grep -rniE "$pattern" "$kit/plugins" "$kit/evals" "$kit/README.md" "$kit/.claude-plugin" --exclude-dir=results)
  [ -z "$leaks" ] && ok "no project names from tests/forbidden.local" || { bad "project names in the kit:"; echo "$leaks" | cut -c1-200 | sed 's/^/        /'; }
else
  skip "project-name leak check (no tests/forbidden.local)"
fi

# "`name` rule → Section" must name a real "## Section" heading in that rule.
if command -v python3 >/dev/null 2>&1; then
  dangling=$(python3 -I - "$kit" <<'PY'
import glob, os, re, sys
kit = sys.argv[1]
rules = {}
for f in glob.glob(os.path.join(kit, 'plugins/*/rules/*.md')):
    heads = [re.sub(r'\s*\(.*\)$', '', l[3:].strip()) for l in open(f) if l.startswith('## ')]
    rules.setdefault(os.path.basename(f)[:-3], []).extend(heads)
pat = re.compile(r'`([a-z-]+)` rule → ([A-Z][A-Za-z-]*(?: [A-Za-z-]+)*)')
for f in glob.glob(os.path.join(kit, 'plugins/**/*.md'), recursive=True):
    for n, line in enumerate(open(f), 1):
        for name, section in pat.findall(line):
            if name not in rules:
                continue
            if not any(h == section or h.startswith(section + ' ') for h in rules[name]):
                print(f"{os.path.relpath(f, kit)}:{n}: `{name}` rule → {section}")
PY
)
  [ -z "$dangling" ] && ok "section references name real rule headings" || { bad "section references to missing headings:"; echo "$dangling" | sed 's/^/        /'; }
else
  skip "section references (python3 not installed)"
fi

echo "Hooks"
check="$kit/plugins/core/scripts/check-edited-file.sh"
if command -v dart >/dev/null 2>&1; then
  echo "{\"tool_input\":{\"file_path\":\"$kit/tests/fixtures/good.dart\"}}" | bash "$check" 2>/dev/null && ok "edit hook passes a clean Dart file" || bad "edit hook flagged a clean Dart file"
  echo "{\"tool_input\":{\"file_path\":\"$kit/tests/fixtures/bad.dart\"}}" | bash "$check" 2>/dev/null; [ $? -eq 2 ] && ok "edit hook reports a Dart error" || bad "edit hook missed a Dart error"
else
  skip "edit hook Dart checks (dart not installed)"
fi
if command -v gofmt >/dev/null 2>&1; then
  echo "{\"tool_input\":{\"file_path\":\"$kit/tests/fixtures/good.go\"}}" | bash "$check" 2>/dev/null && ok "edit hook passes a clean Go file" || bad "edit hook flagged a clean Go file"
  echo "{\"tool_input\":{\"file_path\":\"$kit/tests/fixtures/bad.go\"}}" | bash "$check" 2>/dev/null; [ $? -eq 2 ] && ok "edit hook reports a Go error" || bad "edit hook missed a Go error"
else
  skip "edit hook Go checks (go not installed)"
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/flutter/.claude/rules/ui" "$tmp/firebase-functions/.claude"
printf -- '---\ndescription: Sample project rule\npaths:\n  - "lib/**"\n---\n\n# Sample project rule\n\n- Use FooWidget.\n' > "$tmp/flutter/.claude/rules/ui/widgets.md"
out=$(CLAUDE_PROJECT_DIR="$tmp/flutter" bash "$kit/plugins/core/scripts/session-start.sh")
echo "$out" | grep -q '^# Working agreement' && ok "session hook prints the working agreement" || bad "session hook output"
out=$(CLAUDE_PROJECT_DIR="$tmp/flutter" bash "$kit/plugins/core/scripts/print-project-rules.sh")
echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart" and (.hookSpecificOutput.additionalContext | startswith("# Sample project rule"))' >/dev/null 2>&1 \
  && ok "Plan gets the repository rules as JSON" || bad "print-project-rules.sh output"
[ -z "$(CLAUDE_PROJECT_DIR="$tmp/firebase-functions" bash "$kit/plugins/core/scripts/print-project-rules.sh")" ] && ok "no Plan context without repository rules" || bad "print-project-rules.sh printed without rules"
upd="$kit/plugins/core/scripts/update-kit.sh"
fake="$tmp/fakebin"; home="$tmp/home"
mkdir -p "$fake" "$home/plugins/marketplaces/agent-kit/.claude-plugin"
printf '#!/bin/bash\necho "$*" >> "%s/calls"\n' "$tmp" > "$fake/claude"; chmod +x "$fake/claude"
cp "$kit/.claude-plugin/marketplace.json" "$home/plugins/marketplaces/agent-kit/.claude-plugin/"
echo '{"version":2,"plugins":{"core@agent-kit":[]}}' > "$home/plugins/installed_plugins.json"
PATH="$fake:$PATH" CLAUDE_CONFIG_DIR="$home" CLAUDE_CODE_REMOTE= bash "$upd"
[ ! -e "$tmp/calls" ] && ok "kit update does nothing outside cloud sessions" || bad "kit update ran outside a cloud session"
out=$(PATH="$fake:$PATH" CLAUDE_CONFIG_DIR="$home" CLAUDE_CODE_REMOTE=true AGENT_KIT_UPDATE_FOREGROUND=1 bash "$upd")
{ [ -z "$out" ] && grep -qx 'plugin marketplace update agent-kit' "$tmp/calls" && grep -qx 'plugin update core@agent-kit' "$tmp/calls" && grep -qx 'plugin install flutter@agent-kit' "$tmp/calls"; } \
  && ok "kit update in cloud: refreshes the marketplace, updates installed plugins, installs new ones" || bad "kit update calls: $(tr '\n' ';' < "$tmp/calls" 2>/dev/null)"
rm -f "$tmp/calls"
PATH="$fake:$PATH" CLAUDE_CONFIG_DIR="$home" CLAUDE_CODE_REMOTE=true AGENT_KIT_UPDATE_FOREGROUND=1 bash "$upd"
[ ! -e "$tmp/calls" ] && ok "kit update runs once per container start" || bad "kit update ran twice within the stamp window"
stacks="$tmp/stacks"
mkdir -p "$stacks/app" "$stacks/backend/functions"
printf 'dependencies:\n  flutter:\n    sdk: flutter\n' > "$stacks/app/pubspec.yaml"
printf '{"dependencies": {"firebase-functions": "^6.0.0"}}\n' > "$stacks/backend/functions/package.json"
mkdir -p "$stacks/server"
printf 'module example.com/server\n\ngo 1.26\n' > "$stacks/server/go.mod"
mkdir -p "$tmp/empty"
for dir in "$kit"/plugins/*/; do
  plugin=$(basename "$dir")
  [ "$plugin" = core ] && continue
  [ -f "$kit/plugins/$plugin/stack-markers" ] && ok "$plugin: has stack-markers" || bad "$plugin: no stack-markers"
  rule=$(basename "$(ls "$kit/plugins/$plugin/rules/"*.md | head -1)" .md)
  [ -n "$(CLAUDE_PROJECT_DIR="$stacks" bash "$kit/plugins/$plugin/scripts/print-rule.sh" "$rule")" ] \
    && ok "$plugin: prints with its stack" || bad "$plugin: silent with its stack"
  [ -z "$(CLAUDE_PROJECT_DIR="$tmp/empty" bash "$kit/plugins/$plugin/scripts/print-rule.sh" "$rule")" ] \
    && ok "$plugin: silent without its stack" || bad "$plugin: printed rules without its stack"
done
only() { # only <folder> <plugins that print>: every stack plugin with markers prints there exactly when listed
  for dir in "$kit"/plugins/*/; do
    plugin=$(basename "$dir"); [ -f "$dir/stack-markers" ] || continue
    rule=$(basename "$(ls "$dir/rules/"*.md | head -1)" .md)
    out=$(CLAUDE_PROJECT_DIR="$1" bash "$dir/scripts/print-rule.sh" "$rule")
    case " $2 " in *" $plugin "*) [ -n "$out" ] ;; *) [ -z "$out" ] ;; esac \
      && ok "$plugin: right with only ${1##*/}" || bad "$plugin: wrong with only ${1##*/}"
  done
}
only "$stacks/app" "flutter"
only "$stacks/server" "backend go"
only "$stacks/backend" "backend firebase-functions"
[ -n "$(CLAUDE_PROJECT_DIR="$tmp/empty" bash "$kit/plugins/core/scripts/print-rule.sh" minimal-change)" ] && ok "core: prints in any folder" || bad "core: silent without a stack"
mkdir -p "$stacks/app/.git" "$stacks/app/.claude/rules" "$stacks/app/.claude/skills/doing-foo"
printf -- '---\ndescription: Sample\npaths:\n  - "lib/**"\n---\n\n# Sample\n' > "$stacks/app/.claude/rules/sample.md"
printf -- '---\nname: doing-foo\ndescription: Sample\n---\n' > "$stacks/app/.claude/skills/doing-foo/SKILL.md"
out=$(CLAUDE_PROJECT_DIR="$stacks" bash "$kit/plugins/core/scripts/print-nested-repositories.sh")
{ echo "$out" | grep -qF '`app/.claude/rules/sample.md`: `lib/**`' && echo "$out" | grep -qF 'app/.claude/skills/doing-foo/SKILL.md'; } \
  && ok "session above repositories lists their rules and skills" || bad "print-nested-repositories.sh output"
[ -z "$(CLAUDE_PROJECT_DIR="$stacks/app" bash "$kit/plugins/core/scripts/print-nested-repositories.sh")" ] \
  && ok "session inside a repository lists nothing" || bad "print-nested-repositories.sh printed inside a repository"
for dir in "$kit"/plugins/*/; do
  plugin=$(basename "$dir")
  hooks="$kit/plugins/$plugin/hooks/hooks.json"
  while IFS= read -r cmd; do
    out=$(CLAUDE_PROJECT_DIR="$stacks" CLAUDE_PLUGIN_ROOT="$kit/plugins/$plugin" bash -c "$cmd")
    { echo "$out" | head -1 | grep -q '^# ' && ! echo "$out" | grep -qE '^(paths|description):'; } \
      && ok "$plugin: rule ${cmd##*.sh\" } prints the rule without front matter" || bad "$plugin: rule ${cmd##*.sh\" } output"
  done < <(jq -r '.hooks.SessionStart[].hooks[].command | select(contains("print-rule.sh"))' "$hooks")
  while IFS= read -r cmd; do
    out=$(CLAUDE_PROJECT_DIR="$stacks" CLAUDE_PLUGIN_ROOT="$kit/plugins/$plugin" bash -c "$cmd")
    echo "$out" | jq -e '.hookSpecificOutput.hookEventName == "SubagentStart" and (.hookSpecificOutput.additionalContext | startswith("# "))' >/dev/null 2>&1 \
      && ok "$plugin: rule ${cmd##*.sh\" } gives subagents the rule as JSON" || bad "$plugin: rule ${cmd##*.sh\" } subagent output"
  done < <(jq -r '.hooks.SubagentStart[]?.hooks[].command | select(contains("print-rule.sh"))' "$hooks")
done

echo
if [ "$failures" -eq 0 ]; then echo "All checks passed."; else echo "$failures check(s) failed."; exit 1; fi
