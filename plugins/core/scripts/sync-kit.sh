#!/bin/bash
# Writes Cursor copies of the kit into a repository, for the plugins
# that repository enables in .claude/settings.json (Claude Code itself gets the
# rules and skills straight from the plugins and the repository and needs none of this):
#   rules  -> .cursor/rules/kit/<plugin>/*.mdc  (paths -> globs)
#   the repository's .claude/rules/**/*.md -> .cursor/rules/kit/project/*.mdc
#   working-agreement.md -> .cursor/rules/kit/working-agreement.mdc
#   skills -> .cursor/skills/<name>/
# All targets are generated and git-ignored. Claude Code runs this from the
# core plugin's SessionStart hook; run it by hand when Cursor needs fresh copies.
#
# Usage: sync-kit.sh [project-dir]
# Prints "changed" when the generated files differ from before, "unchanged"
# otherwise, and "error: <reason>" when it could not sync. Always exits 0 so a
# session never fails to start because of it.
set -uo pipefail

marketplace=agent-kit
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project=${1:-${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}}

fail() { echo "error: $1"; exit 0; }

command -v jq >/dev/null 2>&1 || fail "jq is not installed"

# Kit checkout: explicit override, a local kit this script lives in, or the
# marketplace checkout Claude Code keeps up to date.
kit=${AGENT_KIT_DIR:-}
if [ -z "$kit" ] && [ -f "$script_dir/../../../.claude-plugin/marketplace.json" ]; then
  kit=$(cd "$script_dir/../../.." && pwd)
fi
if [ -z "$kit" ]; then
  known="$HOME/.claude/plugins/known_marketplaces.json"
  [ -f "$known" ] && kit=$(jq -r --arg m "$marketplace" '.[$m].installLocation // empty' "$known")
  kit=${kit:-"$HOME/.claude/plugins/marketplaces/$marketplace"}
fi
[ -d "$kit/plugins" ] || fail "no $marketplace checkout at $kit"

# Plugins this repository enables from the kit (project + local settings).
plugins=$(for f in "$project/.claude/settings.json" "$project/.claude/settings.local.json"; do
  [ -f "$f" ] && jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$f"
done | sed -n "s/@$marketplace\$//p" | sort -u)
# Only plugins this kit's marketplace lists: a settings key is repository data,
# and a name like "../x" must not become a path.
known_plugins=$(jq -r '.plugins[].name' "$kit/.claude-plugin/marketplace.json" 2>/dev/null)
plugins=$(echo "$plugins" | grep -xF -f <(echo "$known_plugins") || true)
[ -n "$plugins" ] || fail "no $marketplace plugins enabled in $project/.claude/settings.json"

# Add what they depend on (plugin.json `dependencies`, transitively), as Claude
# Code does: a repository that enables only `go` still gets `backend` and `core`.
resolved=
queue=$plugins
while [ -n "$queue" ]; do
  next=
  for p in $queue; do
    grep -qxF "$p" <<< "$resolved" && continue
    resolved+="$p"$'\n'
    next+=$(jq -r '.dependencies[]? | if type == "string" then . else .name end' \
      "$kit/plugins/$p/.claude-plugin/plugin.json" 2>/dev/null | sed 's/@.*//')$'\n'
  done
  queue=$(grep -xF -f <(echo "$known_plugins") <<< "$next" | sort -u || true)
done
plugins=$(printf '%s' "$resolved" | sort -u)

cursor_rules="$project/.cursor/rules/kit"
cursor_skills="$project/.cursor/skills"
manifest="$cursor_skills/.agent-kit"

# Never write or delete through a symlink planted in the repository.
for d in "$project/.cursor" "$project/.cursor/rules" "$cursor_rules" "$cursor_skills" "$manifest"; do
  [ -L "$d" ] && fail "refusing to sync: ${d#"$project"/} is a symlink"
done

# Skill folder names only: lowercase kebab case, no slashes or dots.
safe_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]; }

fingerprint() {
  { find "$cursor_rules" -type f 2>/dev/null
    [ -f "$manifest" ] && sed "s#^#$cursor_skills/#" "$manifest" | while read -r d; do find "$d" -type f 2>/dev/null; done
  } | sort | while read -r f; do echo "$f"; cat "$f"; done | shasum | cut -d' ' -f1
}

# Markdown rule with `paths:` front matter -> Cursor .mdc with `globs:`.
# Accepts a block list, a flow list (`paths: ["a", "b"]`), or one scalar.
to_mdc() {
  awk '
    function add(g) {
      gsub(/^[ \t]+|[ \t]+$/, "", g); gsub(/["\047]/, "", g)
      if (g != "") globs = globs (globs == "" ? "" : ", ") g
    }
    NR == 1 && $0 == "---" { fm = 1; print; next }
    fm && $0 == "---" {
      if (globs != "") { print "globs: " globs; print "alwaysApply: false" } else { print "alwaysApply: true" }
      fm = 0; print; next
    }
    fm && /^paths:/ {
      v = $0; sub(/^paths:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v == "") { inpaths = 1; next }
      inpaths = 0; gsub(/^\[|\]$/, "", v)
      # Split on commas outside braces, so `*.{ts,tsx}` stays one glob.
      depth = 0; g = ""
      for (i = 1; i <= length(v); i++) {
        c = substr(v, i, 1)
        if (c == "{") depth++; else if (c == "}") depth--
        if (c == "," && depth == 0) { add(g); g = "" } else g = g c
      }
      add(g); next
    }
    fm && inpaths && /^ *- / { g = $0; sub(/^ *- */, "", g); add(g); next }
    fm { inpaths = 0; print; next }
    { print }
  ' "$1"
}

before=$(fingerprint)

rm -rf "$cursor_rules"
if [ -f "$manifest" ]; then
  # The manifest lives in the repository, so trust only plain skill names.
  while read -r name; do safe_name "$name" && rm -rf "${cursor_skills:?}/$name"; done < "$manifest"
  rm -f "$manifest"
fi
mkdir -p "$cursor_rules" "$cursor_skills"

for plugin in $plugins; do
  src="$kit/plugins/$plugin"
  [ -d "$src" ] || continue
  if [ -d "$src/rules" ]; then
    mkdir -p "$cursor_rules/$plugin"
    for rule in "$src"/rules/*.md; do
      [ -f "$rule" ] || continue
      to_mdc "$rule" > "$cursor_rules/$plugin/$(basename "${rule%.md}").mdc"
    done
  fi
  if [ -f "$src/working-agreement.md" ]; then
    { printf -- '---\ndescription: Working agreement (from agent-kit)\nalwaysApply: true\n---\n\n'; cat "$src/working-agreement.md"; } \
      > "$cursor_rules/working-agreement.mdc"
  fi
  for skill in "$src"/skills/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    safe_name "$name" || continue
    # The kit owns this name: drop whatever the repository has there (a
    # symlink, or a folder with symlinks inside) so cp never writes through it.
    rm -rf -- "${cursor_skills:?}/$name"
    cp -R "${skill%/}" "$cursor_skills/$name"
    echo "$name" >> "$manifest"
  done
done

# The repository's own rules (.claude/rules/, read natively by Claude Code).
rules_dir="$project/.claude/rules"
if [ -d "$rules_dir" ]; then
  mkdir -p "$cursor_rules/project"
  while IFS= read -r rule; do
    rel=${rule#"$rules_dir"/}
    to_mdc "$rule" > "$cursor_rules/project/$(echo "${rel%.md}" | tr '/' '-').mdc"
  done < <(find "$rules_dir" -name '*.md' -type f | sort)
fi

after=$(fingerprint)
[ "$before" = "$after" ] && echo unchanged || echo changed
