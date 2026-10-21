---
name: generating-api-clients
description: Generate the Flutter data layer's REST client from the backend's OpenAPI contract — openapi-generator dart-dio writing its own workspace package (modules/generated_api) that only data depends on, excluded from analysis and coverage; one abstract client per remote source wrapping it, with the API store's extensions converting generated models to and from DTOs; headers (auth through a rotating token interceptor, Idempotency-Key, an acting-account header), error bodies mapped by code to typed ApiException, unknown enum values parsed to the generator's sentinel and mapped to `unknown`, the contract freshness check, and stub HTTP session tests against captured fixtures. Use when adding the API layer, regenerating after a contract change, adding an endpoint call, or mapping a new error code.
---

# Generating API clients

Policy: the `data` rule (contract-first client, DTOs, error mapping) and the `architecture` rule → Client API compatibility. Never hand-write request or response types or parse JSON by hand for a contract-backed API. Firebase callables instead: `calling-cloud-functions`.

**Ask first:** picking or switching the generator, and calling an operation the contract marks `draft` without a feature flag.

## Layout

openapi-generator's `dart-dio` emits a whole Dart package, so it lives in its own workspace package that only `data` depends on:

```
contract/openapi.yaml                        # copied by the sync script, never edited here
modules/generated_api/                       # generator output: pubspec, lib/, build_runner inside; never edited
modules/data/lib/src/data_store/remote/api/backend/
  client/backend_api_client.dart             # abstract BackendApiClient (the boundary the repository mocks)
  client/backend_api_client_impl.dart        # wraps the generated APIs, converts, maps errors
  models/{feature}/foo_api_mappers.dart      # extensions: generated Foo → FooDto, FooDto → generated request
  http/dio_factory.dart                      # one Dio with interceptors
  # ApiException and sendApiRequest: handling-errors (data_store/remote/api/utils/)
scripts/sync_contract.sh                     # the contract and shared fixtures from the backend release
scripts/generate_api.sh                      # generator + build_runner in modules/generated_api
```

- The root `pubspec.yaml` lists `modules/generated_api` in `workspace:`; `data` depends on it by path; `tool/check_layers.dart` denies `package:generated_api/` outside `data` (the template's `ui` deny list has it). It is not in `scripts/test.sh`'s package lists, so it has no tests of its own and no coverage gate; its behavior is tested through the client (Tests below).
- The generator's own `pubspec.yaml` is not a workspace member, its `analysis_options.yaml` would analyze generated code, and its `build.yaml` sets `disallow_unrecognized_keys: true` (a field the server adds would break released apps), so all three are **hand-written and committed**, and the generator is told not to touch them (`.openapi-generator-ignore` below).
- One client per remote source, as the `data` rule says (`BackendApiClient` wrapping every generated `FooApi`); a large contract may split the wrapper by tag (`FooApiClient`, `BarApiClient`). Generated types never leave the API store.
- The generated models are this store's Api models: **the store converts them** (extensions in `models/`); the DTO imports nothing from the generated package (`data` rule → Stores and models).

## Generate

```
# modules/generated_api/.openapi-generator-ignore (committed)
pubspec.yaml
analysis_options.yaml
build.yaml
test/**
```

```yaml
# modules/generated_api/pubspec.yaml (hand-written; versions: what the generator's template asks for, current stable)
name: generated_api
publish_to: none
resolution: workspace

environment:
  sdk: ^3.10.0

dependencies:
  copy_with_extension: ^18.0.0
  dio: ^5.9.0
  json_annotation: ^4.9.0

dev_dependencies:
  build_runner: ^2.5.0
  copy_with_extension_gen: ^18.0.0
  json_serializable: ^6.11.0
```

```yaml
# modules/generated_api/build.yaml (hand-written): tolerant of additive changes
targets:
  $default:
    builders:
      json_serializable:
        options:
          checked: true
          create_factory: true
          create_to_json: true
          disallow_unrecognized_keys: false
          explicit_to_json: true
          include_if_null: false
```

```yaml
# modules/generated_api/analysis_options.yaml (hand-written): generated code is not analyzed
analyzer:
  exclude:
    - "**"
```

The root `analysis_options.yaml` of the scaffold already lists `"modules/generated_api/**"` in `analyzer: exclude:`, so `flutter analyze` at the root skips it from either context.

```bash
# scripts/generate_api.sh
set -euo pipefail
openapi-generator-cli generate -i contract/openapi.yaml -g dart-dio \
  -o modules/generated_api \
  --additional-properties=pubName=generated_api,serializationLibrary=json_serializable,enumUnknownDefaultCase=true
flutter pub get
(cd modules/generated_api && dart run build_runner build --delete-conflicting-outputs)
dart format modules/generated_api   # the root format check covers every package
```

Checked with openapi-generator 7.17 and Flutter 3.47: after these steps `scripts/test.sh unit` stays green (the format check, the analyzer, and build_runner freshness cover the package). A newer generator may import more packages: add them to the hand-written pubspec. Add `scripts/generate_api.sh` to `generated_up_to_date` in `scripts/test.sh`, followed by `git diff --exit-code modules/generated_api`, so a stale generated tree fails the unit suite. `enumUnknownDefaultCase` parses a new server enum value as `unknownDefaultOpenApi` instead of throwing; the raw value is lost there. The mapper stores the known wire value (`status.value`) on the DTO and the sentinel as `'unknown'`, and `toDomain()` parses it with the domain `unknown` case. A screen that must show an unknown value as sent needs the field typed as a plain string in the contract.

## The client

```dart
// models/foo/foo_api_mappers.dart
extension FooApiX on Foo {                              // generated model
  // The wire value (`value`, not the Dart `name`); the generator's sentinel for
  // a value this build does not know becomes 'unknown'.
  FooDto toDto() => FooDto(
    id: id,
    title: title,
    status: status == FooStatusEnum.unknownDefaultOpenApi ? 'unknown' : status.value,
  );
}

extension SaveFooRequestFromDto on FooDto {
  SaveFooRequest toSaveFooRequest() => SaveFooRequest(title: title);
}

// client/backend_api_client_impl.dart
final class BackendApiClientImpl implements BackendApiClient {
  BackendApiClientImpl(this._foos);

  final FooApi _foos; // generated

  @override
  Future<FooDto> getFoo({required String fooId}) => _call(() async {
    final response = await _foos.getFoo(fooId: fooId);
    return response.data!.toDto();
  });

  @override
  Future<FooDto> saveFoo({required FooDto foo, required String idempotencyKey}) =>
      _call(() async {
        final response = await _foos.saveFoo(
          idempotencyKey: idempotencyKey,
          saveFooRequest: foo.toSaveFooRequest(),
        );
        return response.data!.toDto();
      });
}
```

The request extension lives in the API store next to the response one, so the DTO stays free of store imports.

`_call` is `sendApiRequest` with the Dio `classify` below. `ApiException`, `apiErrorCodeForStatus`, and `sendApiRequest` are the same files as for callables: copy `data_store/remote/api/utils/` and its tests (`test/data_store/remote/api/utils/`) from `calling-cloud-functions`' templates (`handling-errors` explains them). `classifyDioError` gets its own test: each status, a body with and without the contract's error shape, a missing status, each timeout type, a connection error, and a non-Dio error.

```dart
// client/backend_api_client_impl.dart (continued)
Future<T> _call<T>(Future<T> Function() request) =>
    sendApiRequest(request, classify: classifyDioError);

/// The whole exception from a Dio failure: transport code, HTTP status, and
/// the contract's own code from `{ "error": { "code": … } }`.
ApiException? classifyDioError(Object error) {
  if (error is! DioException) return null;
  final response = error.response;
  if (response == null) {
    return ApiException(switch (error.type) {
      .connectionTimeout || .sendTimeout || .receiveTimeout => .timeout,
      _ => .unavailable,
    });
  }
  final status = response.statusCode;
  return ApiException(
    status == null ? .unknown : apiErrorCodeForStatus(status),
    statusCode: status,
    serverCode: switch (response.data) {
      {'error': {'code': final String code}} => code,
      _ => null,
    },
  );
}
```

- Branch on codes, never on `message`. The client throws only `ApiException`.
- The repository maps `serverCode` first (`foo.notFound` → `FooNotFoundException`), then the transport code with `toAppException()` (`unavailable` / `timeout` → `NetworkUnavailableException`, so a failing server reads as "retry later"); an unknown code → `UnknownException`. No other exception types: the client throws only `ApiException`, the repository only `AppException`s.
- DTOs keep wire enum values and nullable fields as the contract says; parsing to domain types happens in `toDomain()`.

## Headers and interceptors

One `Dio` from `dio_factory.dart`, registered in `injectDataLayer`:

- **Auth:** a rotating token interceptor (`fresh_dio`) reading tokens from secure storage, refreshing once on 401 and retrying the request; a refused refresh signs the user out through the session repository.
- **Idempotency-Key:** passed by the caller (the action queue owns the key), never generated inside the client.
- **Acting account / tenant** (`Foo-Account-Id` or the project's header): declared in the contract as a header **parameter**, dart-dio makes it a required argument of every generated method, and an interceptor cannot fill it. Either the contract declares it as an `apiKey` security scheme in the header (`securitySchemes`, applied per operation), so the generated client leaves it out and an interceptor sets it from the session store, or the `BackendApiClientImpl` passes it on each call from the session store. Operations the contract marks without it skip it either way.
- **Server time:** an interceptor records `Server-Time` (and its signature) with the monotonic time received, when the project uses a time anchor (`queueing-offline-actions`).
- Timeouts per class (connect 10 s, receive 30 s, uploads longer); logs carry method, path template, status, and duration, never bodies, tokens, or signed URLs.

## Tests

In `modules/data/test/api/`, against a stub HTTP session (`http_mock_adapter` or a custom `HttpClientAdapter`) that records requests:

- Request shape: method, path, query, body, headers (`Idempotency-Key`, the account header, auth) per operation.
- Responses from captured JSON fixtures in `test/fixtures/` that validate against the contract; every field, null, missing, and unknown enum values mapped.
- Errors: each code the operation declares → `ApiException` with that `serverCode`; 5xx, timeout, no connection → `unavailable` / `internal` / `timeout`, and through the repository `NetworkUnavailableException` or `UnknownException`; 401 → one refresh and a retry; refused refresh → signed out.
- Every new client method gets the same method on every double (unit helpers, Patrol mocks, playback clients — `mocking-backend-for-tests`) in the same change.

## After a contract change

1. `scripts/sync_contract.sh` (the backend's released contract and shared fixtures).
2. `scripts/generate_api.sh`; build; fix the mapper extensions the compiler flags.
3. Tests first for the new fields or codes; then the DTO, mapper, repository.
4. A removed or renamed field is a breaking change: the backend owns versioning; the client never patches the generated code.
