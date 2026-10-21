#!/bin/bash
# SessionStart hook: prints the working agreement, which Claude Code adds to the
# session context, and refreshes the git-ignored Cursor copies of the kit.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
status=$(bash "$root/scripts/sync-kit.sh" "${CLAUDE_PROJECT_DIR:-$PWD}" 2>&1 | tail -1)

cat "$root/working-agreement.md"
echo
case "$status" in
  changed|unchanged) ;;
  *) echo "Kit sync for Cursor failed ($status). Claude Code is not affected; tell the user if they use Cursor." ;;
esac
exit 0
