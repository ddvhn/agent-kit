import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:log/log.dart';

import 'helpers/database_test_utils.dart';

/// Runs before every test file in this package: code under test logs, the
/// Isar core is loaded, and no test reaches the network (testing rule →
/// Rules). The order matters:
/// 1. the Isar core first: the first run downloads it, before anything
///    replaces HttpOverrides;
/// 2. the test binding, which installs its own HttpOverrides once;
/// 3. the network block, last, so it is the one every test sees.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeLogger();
  await initializeTestIsarCore();
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
