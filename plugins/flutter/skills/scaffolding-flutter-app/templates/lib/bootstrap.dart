import 'dart:async';

import 'package:data/data.dart';
import 'package:domain/domain_usecase.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:log/log.dart';
import 'package:ui/ui.dart';

/// Startup shared by every entry point (`main.dart`, `main_web.dart`), after
/// the entry set up its binding: logger → config → error handlers → DI per
/// layer → [app] (di rule → Wiring). [overrides] runs after the data layer
/// and replaces its I/O with doubles (`test/main_mock.dart`,
/// mocking-backend-for-tests); production entries never pass it.
Future<void> bootstrap({
  required Widget app,
  String? logsDirectoryPath,
  FutureOr<void> Function(GetIt getIt)? overrides,
}) async {
  await initializeLogger(logsDirectoryPath: logsDirectoryPath);
  final config = AppConfig.fromEnvironment();
  log.i('Starting, environment: ${config.environment}');
  _installErrorHandlers();

  final getIt = GetIt.instance;
  // Once injectDataLayer sets up an SDK (Firebase), it takes skipSdkInit:
  // pass `skipSdkInit: overrides != null` so the mock app never starts it.
  await injectDataLayer(getIt, config: config);
  await overrides?.call(getIt);
  injectDomainLayer(getIt);
  injectUiLayer(getIt);

  runApp(app);
}

/// Every uncaught error is logged; a crash reporter forwards from here
/// (configuring-flutter-flavors → Firebase and crash reporting).
void _installErrorHandlers() {
  FlutterError.onError = (details) {
    log.e(
      'Uncaught Flutter error: ${details.exceptionAsString()}',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    log.e('Uncaught error: $error', error: error, stackTrace: stackTrace);
    return true;
  };
}
