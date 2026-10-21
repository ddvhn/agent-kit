import 'package:domain/src/foo/usecase/fetch_foo_use_case.dart';
import 'package:get_it/get_it.dart';

void injectDomainLayer(GetIt getIt) {
  getIt.registerFactory<FetchFooUseCase>(() => FetchFooUseCaseImpl(getIt()));
}
