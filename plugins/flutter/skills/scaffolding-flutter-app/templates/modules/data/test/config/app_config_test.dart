import 'package:data/src/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('without a flavor or define the environment is dev, never prod', () {
    final config = AppConfig.fromEnvironment();

    expect(config.environment, 'dev');
    expect(config.isProd, isFalse);
  });

  test('only prod is prod', () {
    expect(const AppConfig(environment: 'prod').isProd, isTrue);
    expect(const AppConfig(environment: 'staging').isProd, isFalse);
  });
}
