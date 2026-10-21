import 'package:domain/src/common/usecase/callable_use_case.dart';
import 'package:domain/src/foo/model/foo.dart';
import 'package:domain/src/foo/repository/foo_repository.dart';

abstract class FetchFooUseCase with CallableUseCaseWithoutParams<Foo> {}

final class FetchFooUseCaseImpl extends FetchFooUseCase {
  FetchFooUseCaseImpl(this._fooRepository);

  final FooRepository _fooRepository;

  @override
  Future<Foo> call() => _fooRepository.fetchFoo();
}
