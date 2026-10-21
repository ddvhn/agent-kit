# Source

Vendored from [flutter/agent-plugins](https://github.com/flutter/agent-plugins) `skills/flutter-build-responsive-layout`,
commit `0ef3972f93e2baa4156ba1cbb1e515cd53079c68` (2026-09-30). BSD-3-Clause, Copyright the Flutter project authors (full text in `LICENSE`).

Local changes: the LayoutBuilder example builds both branches inline instead of `Widget _buildFoo()` helpers (the `dart` rule forbids widget-returning helper methods).
To update: diff against upstream and re-apply that change.
