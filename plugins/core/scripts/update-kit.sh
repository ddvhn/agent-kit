#!/bin/bash
# SessionStart hook, cloud sessions only: brings the kit up to date and installs
# plugins added to the marketplace since the container was built. A cloud
# session can resume from a cached container that skips the environment's
# setup script, so the kit would otherwise stay at the cached version. Runs in
# the background and prints nothing; changes apply at the next session.
# Local Claude Code keeps the kit current through marketplace auto-update and
# installs only the plugins a repository enables, so this does nothing there.
# Usage: update-kit.sh   (AGENT_KIT_UPDATE_FOREGROUND=1 runs it inline, for tests)
[ "${CLAUDE_CODE_REMOTE:-}" = true ] || exit 0
command -v claude >/dev/null 2>&1 || exit 0
plugins_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins
stamp="$plugins_dir/agent-kit-update.stamp"
log="$plugins_dir/agent-kit-update.log"
mkdir -p "$plugins_dir"
# One run per container start, not on every /clear or compaction.
[ -n "$(find "$stamp" -mmin -30 2>/dev/null)" ] && exit 0
touch "$stamp"

update() {
  date
  claude plugin marketplace update agent-kit || return 0
  installed=$(jq -r '.plugins | keys[]' "$plugins_dir/installed_plugins.json" 2>/dev/null)
  for p in $(jq -r '.plugins[].name' "$plugins_dir/marketplaces/agent-kit/.claude-plugin/marketplace.json"); do
    if printf '%s\n' "$installed" | grep -qxF "$p@agent-kit"; then
      claude plugin update "$p@agent-kit"
    else
      claude plugin install "$p@agent-kit"
    fi
  done
}

if [ "${AGENT_KIT_UPDATE_FOREGROUND:-}" = 1 ]; then
  update >"$log" 2>&1
else
  nohup bash -c "$(declare -p plugins_dir); $(declare -f update); update" >"$log" 2>&1 </dev/null &
  disown
fi
exit 0
