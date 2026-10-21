import 'package:data/data.dart';
import 'package:domain/domain_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

void main() {
  final getIt = GetIt.asNewInstance();

  tearDown(getIt.reset);

  test('registers the config and the repositories by contract', () async {
    const config = AppConfig(environment: 'dev');

    await injectDataLayer(getIt, config: config);

    expect(getIt<AppConfig>(), same(config));
    expect(getIt<FooRepository>(), isA<FooRepository>());
  });
}
