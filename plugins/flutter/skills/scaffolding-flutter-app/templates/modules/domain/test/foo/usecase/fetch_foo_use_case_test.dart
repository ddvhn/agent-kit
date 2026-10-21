import 'package:domain/domain_model.dart';
import 'package:domain/domain_repository.dart';
import 'package:domain/src/foo/usecase/fetch_foo_use_case.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockFooRepository extends Mock implements FooRepository {}

void main() {
  late _MockFooRepository repository;
  late FetchFooUseCase useCase;

  setUp(() {
    repository = _MockFooRepository();
    useCase = FetchFooUseCaseImpl(repository);
  });

  test('returns the repository foo', () async {
    when(repository.fetchFoo).thenAnswer((_) async => const Foo(id: 'foo-1'));

    expect(await useCase(), const Foo(id: 'foo-1'));
  });

  test('passes repository failures through', () async {
    when(
      repository.fetchFoo,
    ).thenAnswer((_) => Future.error(const NetworkUnavailableException()));

    await expectLater(useCase(), throwsA(isA<NetworkUnavailableException>()));
  });
}
