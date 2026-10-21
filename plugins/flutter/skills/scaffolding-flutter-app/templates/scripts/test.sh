#!/usr/bin/env bash
# One entry for every suite (testing rule → Rules). No CI needed: the
# git hooks run the fast suite, people and agents run the rest.
#   scripts/test.sh unit            analyze, layers, generated code, unit, widget, golden, coverage
#   scripts/test.sh e2e [args]      Patrol on an already booted device or Chrome
#   scripts/test.sh live [args]     manual live smoke with real providers; never from a hook
set -euo pipefail
cd "$(dirname "$0")/.."

dart_packages=(modules/domain modules/utils modules/logger)
flutter_packages=(modules/data modules/ui modules/localization)

generated_up_to_date() {
  (cd modules/localization && flutter gen-l10n)
  for package in modules/*/; do
    if grep -q '^  build_runner:' "$package/pubspec.yaml"; then
      (cd "$package" && dart run build_runner build --delete-conflicting-outputs >/dev/null)
    fi
  done
  if [ -n "$(git status --porcelain -- '*.g.dart' '*.freezed.dart' 'modules/localization/lib/generated')" ]; then
    echo "Generated code is stale: regenerate and commit it." >&2
    git status --short -- '*.g.dart' '*.freezed.dart' 'modules/localization/lib/generated' >&2
    exit 1
  fi
}

unit() {
  flutter pub get >/dev/null
  dart format --output=none --set-exit-if-changed .
  flutter analyze
  dart run tool/check_layers.dart
  generated_up_to_date
  # A package without test/ is not skipped: check_coverage fails on it.
  for package in "${dart_packages[@]}"; do
    if [ -d "$package/test" ]; then (cd "$package" && dart run coverage:test_with_coverage); fi
  done
  for package in "${flutter_packages[@]}"; do
    if [ -d "$package/test" ]; then (cd "$package" && flutter test --coverage); fi
  done
  dart run tool/check_coverage.dart "${dart_packages[@]}" "${flutter_packages[@]}"
}

e2e() {
  patrol test "$@"
}

live() {
  echo "Live smoke: real paid providers against staging, within the spend cap"
  echo "(testing-flutter-apps → Live smoke). Record the run in the release PR."
  read -r -p "Type 'live' to continue: " answer
  [ "$answer" = live ] || exit 1
  patrol test --target live_test --flavor staging "$@"
}

case "${1:-}" in
  unit) unit ;;
  e2e) shift; e2e "$@" ;;
  live) shift; live "$@" ;;
  *) echo "usage: scripts/test.sh unit | e2e [patrol args] | live [patrol args]" >&2; exit 2 ;;
esac
