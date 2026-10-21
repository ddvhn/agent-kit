import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:log/log.dart';

/// Runs before every test file in this package: code under test logs, and
/// no test reaches the network (testing rule → Rules).
/// A database replaces this file with persisting-with-isar's, which loads the
/// Isar core first (it downloads it on the first run).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeLogger();
  // The binding installs its own HttpOverrides once, when it is created; create
  // it first so the block below is the one every test sees.
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _NoNetwork();
  await testMain();
}

/// Any real HTTP request fails the test: use a double of the client.
final class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('Tests must not use the network; use a double.');
}
