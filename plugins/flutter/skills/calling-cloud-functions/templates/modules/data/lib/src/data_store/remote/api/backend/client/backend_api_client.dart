/// The app backend, one method per callable, named exactly like the callable
/// (`getFoo`, `listFoos`, `updateFoo`). Speaks DTOs; throws `ApiException`.
abstract interface class BackendApiClient {
  // Future<FooDto> getFoo({required String fooId});
  // Future<FooPageDto> listFoos({required String? cursor, required int limit});
}
