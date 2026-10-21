import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:ui/src/application/router/router.dart';
import 'package:ui/src/common/theme/ui_platform.dart';
import 'package:ui/src/foo/blocs/load_foo_bloc.dart';

/// The only container lookup in ui: `BlocProvider(create: (_) => inject())`.
T inject<T extends Object>() => GetIt.instance<T>();

void injectUiLayer(GetIt getIt) {
  getIt
    // The one platform check of the UI package (architecture rule →
    // Platforms and assembly); widgets read it from the theme.
    ..registerSingleton(UiPlatform.current())
    ..registerLazySingleton<GoRouter>(
      createRouter,
      dispose: (router) => router.dispose(),
    )
    ..registerFactory(() => LoadFooBloc(getIt()));
}
