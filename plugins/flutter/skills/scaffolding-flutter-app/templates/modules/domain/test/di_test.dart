import 'package:domain/domain_repository.dart';
import 'package:domain/domain_usecase.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockFooRepository extends Mock implements FooRepository {}

void main() {
  test('injectDomainLayer registers a new use case per lookup', () {
    final getIt = GetIt.asNewInstance()
      ..registerSingleton<FooRepository>(_MockFooRepository());

    injectDomainLayer(getIt);

    expect(getIt<FetchFooUseCase>(), isNot(same(getIt<FetchFooUseCase>())));
  });
}
