#!/usr/bin/env bash
# One-time setup per clone: checks the pinned Flutter version and installs
# the git hooks (testing rule → Rules).
set -euo pipefail
cd "$(dirname "$0")/.."

want=$(tr -d '[:space:]' < .flutter-version)
have=$(flutter --version --machine | sed -n 's/.*"frameworkVersion": *"\([^"]*\)".*/\1/p')
if [ "$want" != "$have" ]; then
  echo "Flutter $have is installed; this project pins $want (.flutter-version)." >&2
  echo "Switch to it (for example: fvm use $want) and run this again." >&2
  exit 1
fi
command -v gitleaks >/dev/null || { echo "Install gitleaks: the pre-commit hook needs it." >&2; exit 1; }

git config core.hooksPath scripts/hooks
flutter pub get
echo "Ready: Flutter $have, hooks from scripts/hooks."
