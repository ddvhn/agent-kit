import 'package:data/src/config/app_config.dart';
import 'package:data/src/core/disposable.dart';
import 'package:data/src/repository/foo_repository_impl.dart';
import 'package:domain/domain_repository.dart';
import 'package:get_it/get_it.dart';

/// Order inside: stores, then services, then repositories keyed by their
/// domain contract (`di` rule). Test harnesses register doubles with
/// `replaceSingleton` after it.
Future<void> injectDataLayer(GetIt getIt, {required AppConfig config}) async {
  getIt
    ..registerSingleton(config)
    // Repositories, keyed by the domain contract
    ..registerLazySingleton<FooRepository>(
      FooRepositoryImpl.new,
      dispose: disposeIfDisposable,
    );
}
