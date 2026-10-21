import 'package:flutter/widgets.dart';

/// Widget keys for integration tests (writing-patrol-tests), imported by the
/// app and by patrol_test as `package:ui/keys.dart`. One class per screen or
/// shared widget; values unique.
final keys = Keys();

final class Keys {
  final home = HomeKeys();
  final widgets = WidgetKeys();
}

/// A key named after its screen, so finders and Patrol logs read clearly.
final class AppKey extends ValueKey<String> {
  const AppKey(String screen, String value) : super('${screen}_$value');
}

final class HomeKeys {
  AppKey foo(String fooId) => AppKey('home', 'foo_$fooId');
  final page = const AppKey('home', 'page');
  final skeleton = const AppKey('home', 'skeleton');
}

final class WidgetKeys {
  final errorViewRetry = const AppKey('widgets', 'errorViewRetry');
}
