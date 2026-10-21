/// A data object that owns streams, subscriptions, or native resources.
abstract interface class Disposable {
  Future<void> dispose();
}

/// The `dispose:` callback of a singleton registered by its contract:
/// `registerLazySingleton<FooRepository>(…, dispose: disposeIfDisposable)`.
/// A capability check, not a cast.
Future<void> disposeIfDisposable(Object instance) async {
  if (instance is Disposable) await instance.dispose();
}
