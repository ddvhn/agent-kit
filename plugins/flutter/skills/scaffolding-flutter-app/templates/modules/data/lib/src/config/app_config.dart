import 'package:flutter/services.dart';

/// The one config object: environment and dart-defines, read once in `main`
/// and registered by `injectDataLayer` (di rule → Build configuration).
/// Switches join as features need them (configuring-flutter-flavors).
final class AppConfig {
  const AppConfig({required this.environment});

  factory AppConfig.fromEnvironment() =>
      const AppConfig(environment: _environment);

  /// `dev`, `staging`, or `prod`: the native flavor on mobile,
  /// `ENVIRONMENT` from the web config file (`config/web/{env}.json` passed
  /// with `--dart-define-from-file`). Neither set (`flutter test`, no
  /// flavor) means `dev`, never prod.
  final String environment;

  bool get isProd => environment == 'prod';
}

const String _environment =
    appFlavor ?? String.fromEnvironment('ENVIRONMENT', defaultValue: 'dev');
