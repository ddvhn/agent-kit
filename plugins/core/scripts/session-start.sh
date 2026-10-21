#!/bin/bash
# SessionStart hook: prints the working agreement, which Claude Code adds to the
# session context.
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

cat "$root/working-agreement.md"
exit 0
