---
name: handling-errors
description: Handle errors end to end in a Flutter app the kit way — transport and store failures classified in data (ApiException with an error code), repositories mapping them to the app's sealed domain exceptions (network unavailable, not found, unauthorized, permission denied, quota exceeded, validation, unknown, feature exceptions), use cases passing or raising them, blocs keeping the exception in failure states, one UI extension mapping them to localized copy and retry affordances, global crash handlers with Crashlytics, what to log and what never to log, and the tests for each mapping. Use when adding an API call or repository method, a new failure case, an error or retry UI, crash reporting, logging, or when an SDK exception or raw message reaches a bloc or widget.
---

# Handling errors

Policy: core `minimal-change` (typed errors, never branch on message text) and `architecture-principles` (domain errors are part of the model); the stack `architecture` rule (errors and logging, security). Every file below is a template: the empty app has `app_exception.dart`, `app_exception_x.dart`, and `error_view.dart` (`scaffolding-flutter-app`); the transport side — `api_exception.dart`, `send_api_request.dart`, the callable code table in `firebase_backend_api_client.dart`, and the repository guard `with_app_exceptions.dart` — arrives with the first endpoint (`calling-cloud-functions` templates). Feature exceptions: `modeling-domain`.

## The flow

```
SDK / HTTP / database error
  → API client: sendApiRequest → ApiException(code)              data, store
  → repository: withAppExceptions (+ feature mapping) → AppException   data
  → use case: passes it on, or throws a FeatureException for a rule    domain
  → bloc: catch (e) → AppException.from(e) → Failure / Error state      ui
  → widget: error.message(context.strings), error.isRetryable            ui
uncaught anywhere → FlutterError.onError / PlatformDispatcher.onError → log.e + Crashlytics
```

Each boundary converts once. Nothing above data sees an SDK, HTTP, or database type; nothing above ui's mapping sees copy.

## Data: classify transport failures once

```dart
/// Transport failure, classified once in the API client. Never leaves data.
enum ApiErrorCode {
  unavailable,
  timeout,
  unauthenticated,
  permissionDenied,
  notFound,
  invalidArgument,
  outOfRange,
  alreadyExists,
  failedPrecondition,
  resourceExhausted,
  aborted,
  cancelled,
  unimplemented,
  internal,
  dataLoss,
  invalidResponse,
  unknown,
}

final class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode, this.serverCode});

  final ApiErrorCode code;
  final int? statusCode;

  /// The backend's own machine code from the error body, when the contract
  /// has one (`foo.notFound`); repositories branch on it before [code].
  final String? serverCode;

  @override
  String toString() =>
      'ApiException(${code.name}, status: $statusCode, server: $serverCode)';
}
```

Every client method runs its call through one helper in `data_store/remote/api/utils/`:

```dart
Future<T> sendApiRequest<T>(
  Future<T> Function() request, {
  ApiException? Function(Object error)? classify, // the whole exception, or null
}) async {
  try {
    return await request();
  } on ApiException {
    rethrow;
  } on TimeoutException catch (_, stackTrace) {
    Error.throwWithStackTrace(const ApiException(.timeout), stackTrace);
  } on CheckedFromJsonException catch (_, stackTrace) {
    Error.throwWithStackTrace(const ApiException(.invalidResponse), stackTrace);
  } on FormatException catch (_, stackTrace) {
    Error.throwWithStackTrace(const ApiException(.invalidResponse), stackTrace);
  } on TypeError catch (_, stackTrace) {
    Error.throwWithStackTrace(const ApiException(.invalidResponse), stackTrace);
  } catch (e, stackTrace) {
    final exception = classify?.call(e) ?? const ApiException(.unknown);
    Error.throwWithStackTrace(exception, stackTrace);
  }
}
```

`classify` is the transport's own table, written once per client. It returns the whole `ApiException`, so the HTTP status and the server's own code from the error body survive (REST: `generating-api-clients` → The client); the table below gives its `code`:

| Transport signal | `ApiErrorCode` |
| --- | --- |
| no connection, DNS / socket failure; callable `unavailable`; HTTP 502 / 503 | `unavailable` |
| client timeout; callable `deadline-exceeded`; HTTP 408 / 504 | `timeout` |
| callable `unauthenticated`; HTTP 401 | `unauthenticated` |
| callable `permission-denied`; HTTP 403 | `permissionDenied` |
| callable `not-found`; HTTP 404 | `notFound` |
| callable `invalid-argument`; HTTP 400 / 422 | `invalidArgument` |
| callable `already-exists`; HTTP 409 | `alreadyExists` |
| callable `failed-precondition`; HTTP 412 | `failedPrecondition` |
| callable `resource-exhausted`; HTTP 429 | `resourceExhausted` |
| callable `out-of-range` | `outOfRange` |
| callable `aborted`, `cancelled`, `unimplemented` (HTTP 501), `internal` (HTTP 500), `data-loss` | the code of the same name |
| JSON that does not parse or match the model | `invalidResponse` |

The table covers every HttpsError code the backend emits (its domain errors map to them in one backend table); a new backend code is a new row here and, if callers branch on it, a new `AppException`. The backend's error **message** is never shown and never branched on; a code the client must act on is a code, agreed with the backend (`CLAUDE.md` → Related repositories). Callable specifics: `calling-cloud-functions`.

Database stores let engine errors through to the repository guard; a cache miss under `CachePolicy.cache` is `NotFoundException`, thrown by the repository.

## Repository: map to domain exceptions

```dart
extension ApiExceptionMapping on ApiException {
  AppException toAppException() => switch (code) {
    .unavailable || .timeout => const NetworkUnavailableException(),
    .unauthenticated => const UnauthorizedException(),
    .permissionDenied => const PermissionDeniedException(),
    .notFound => const NotFoundException(),
    .invalidArgument || .outOfRange => const ValidationException(),
    .resourceExhausted => const QuotaExceededException(),
    .alreadyExists ||
    .failedPrecondition ||
    .aborted ||
    .cancelled ||
    .unimplemented ||
    .internal ||
    .dataLoss ||
    .invalidResponse ||
    .unknown => UnknownException(this),
  };
}

/// Every repository method body runs inside this: only [AppException]s
/// leave the data layer.
Future<T> withAppExceptions<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on AppException {
    rethrow;
  } on ApiException catch (e, stackTrace) {
    final mapped = e.toAppException();
    if (mapped is UnknownException) {
      log.e('Unexpected API error: $e', error: e, stackTrace: stackTrace);
    }
    Error.throwWithStackTrace(mapped, stackTrace);
  } catch (e, stackTrace) {
    log.e('Unexpected data error: $e', error: e, stackTrace: stackTrace);
    Error.throwWithStackTrace(UnknownException(e), stackTrace);
  }
}
```

A code that means something specific for one call becomes that feature's exception inside the guard; everything else falls through to the generic mapping:

```dart
@override
Future<Foo> publishFoo({required String fooId}) => withAppExceptions(() async {
  try {
    final dto = await _apiClient.publishFoo(fooId: fooId);
    return dto.toDomain();
  } on ApiException catch (e) {
    if (e.code == .failedPrecondition) {
      throw const FooNotPublishableException();
    }
    rethrow;
  }
});
```

## Use case

- Lets `AppException`s through unchanged. Throws its own `FeatureException` when a domain rule fails (`FooNotPublishableException`).
- Catches only to change the meaning, explicitly: "not found means empty here" → `on NotFoundException { return const []; }`. Never a blanket `catch` that returns null.
- May log: `log` is pure Dart, so a use case logs what only it knows — a failure it deliberately swallows (`log.w('No foo cached, starting empty')`) or a rule that rejected the action (`log.w('Foo $fooId is not publishable: ${foo.status.name}')`) — and still throws or returns as above.

## Bloc

```dart
} catch (e, stackTrace) {
  logFailure('Failed to publish foo $fooId', e, stackTrace);
  _emit(PublishFooBlocStateFailure(error: AppException.from(e)));
}
```

- Failure, `Error`, `ReloadError`, and `LoadMoreError` states carry `final AppException error` (in `props`). `AppException.from` turns a stray non-domain error into `UnknownException`.
- A failed refresh keeps the payload (the stack `dart` rule, load blocs); one-shot error toasts are presentation events (`writing-action-blocs`).
- `UnauthorizedException` on any call does not sign out by itself: the session repository owns the session, its stream changes, and the router redirect reacts (`observing-data`, `adding-flutter-routes`).

## UI: one mapping

`ui/lib/src/common/extensions/app_exception_x.dart`:

```dart
extension AppExceptionX on AppException {
  String message(AppLocalizations strings) => switch (this) {
    NetworkUnavailableException() => strings.errorOffline,
    NotFoundException() => strings.errorNotFound,
    UnauthorizedException() => strings.errorSignedOut,
    PermissionDeniedException() => strings.errorNotAllowed,
    QuotaExceededException() => strings.errorTooManyRequests,
    ValidationException() => strings.errorInvalidInput,
    UnknownException() => strings.errorGeneric,
    final FooException e => e.message(strings),
    FeatureException() => strings.errorGeneric,
  };

  /// Whether a retry button makes sense; the rest needs another action.
  bool get isRetryable => switch (this) {
    NetworkUnavailableException() ||
    QuotaExceededException() ||
    UnknownException() => true,
    _ => false,
  };
}

/// Expected failures are warnings; unknown ones are errors with the trace.
void logFailure(String message, Object error, StackTrace stackTrace) {
  switch (AppException.from(error)) {
    case UnknownException():
      log.e('$message: $error', error: error, stackTrace: stackTrace);
    case final AppException expected:
      log.w('$message: $expected');
  }
}
```

- Each feature adds `extension FooExceptionX on FooException { String message(AppLocalizations strings) => switch (this) {…}; }` in its ui folder and one line in the central switch.
- Widgets never show `error.toString()`, a server message, or an exception type name. A screen that needs different copy for one case switches on the type itself (`FooDraftInvalidException(:final violations)` marks fields).
- One shared `ErrorView(error:, onRetry:)` in `ui/lib/src/common/widgets/` renders the message and shows retry only when `isRetryable`; `NetworkUnavailableException` with cached data is not an error view (core `architecture-principles`, offline-first).

## Global handlers

In `main` after `initializeLogger()` (template: `scaffolding-flutter-app`): `FlutterError.onError` and `PlatformDispatcher.instance.onError` log with `log.e(…, error:, stackTrace:)`; with crash reporting they also forward to Crashlytics when `AppConfig.useCrashlytics` is on (release builds pass `CRASHLYTICS=true`; debug runs do not; `configuring-flutter-flavors` → Firebase and crash reporting). Crashlytics receives uncaught errors only; expected domain exceptions are never reported. Non-fatal reporting of `UnknownException`s, if the project wants it, is a data service behind a repository contract, decided in an ADR (`recording-decisions`).

## Logging

| Level | For |
| --- | --- |
| `log.d` | lifecycle and flow (`Did connect`, `Initialized database`) — no payloads |
| `log.i` | rare milestones (startup flavor, sign-in completed) |
| `log.w` | expected failures (offline, not found, validation) with the operation and ids |
| `log.e` | unexpected failures and uncaught errors, always with `error:` and `stackTrace:` |

- Every layer may log; a failure is logged once, by whoever handles it (bloc, repository guard for unknowns, a use case that swallows it, `main`), with context: operation and ids, not the payload. A layer that only rethrows does not log.
- Never log passwords, auth or payment tokens, payment data, request or response bodies, personal data (email, name, location, free text), or notification copy. The file log is shared by users in "report an issue" — treat it as visible.
- A sensitive value needed for debugging (a push token, an external id) goes through `loggedSecret(value)` (redacted in release).
- `print` is never used (`avoid_print`).

## Tests

- [ ] Client: each transport signal in the table → its `ApiErrorCode` (table-driven unit test against the client with a mocked transport)
- [ ] Repository guard: each `ApiErrorCode` → its `AppException`; any other error → `UnknownException`
- [ ] Each feature-specific mapping in a repository method; cache miss under `CachePolicy.cache` → `NotFoundException`
- [ ] Use case: rule violation throws the feature exception; repository exceptions pass through unchanged (`testing-use-cases`)
- [ ] Bloc: failure state holds the exception; refresh failure keeps the payload
- [ ] UI mapping: every `AppException` subtype and each feature exception → its copy (`lookupAppLocalizations(const Locale('en'))` in a ui unit test); `isRetryable`
- [ ] One error flow per screen in the integration suite (`writing-patrol-tests`)

Table-driven guard test (data package):

```dart
final cases = <ApiErrorCode, Matcher>{
  .unavailable: isA<NetworkUnavailableException>(),
  .timeout: isA<NetworkUnavailableException>(),
  .unauthenticated: isA<UnauthorizedException>(),
  .permissionDenied: isA<PermissionDeniedException>(),
  .notFound: isA<NotFoundException>(),
  .invalidArgument: isA<ValidationException>(),
  .unknown: isA<UnknownException>(),
};
for (final MapEntry(key: code, value: matcher) in cases.entries) {
  test('maps ${code.name}', () async {
    await expectLater(
      withAppExceptions<void>(() => Future.error(ApiException(code))),
      throwsA(matcher),
    );
  });
}
```

## Checks

- [ ] Every client call goes through `sendApiRequest`; every repository method through `withAppExceptions`
- [ ] No SDK, HTTP, database, or `ApiException` type above data
- [ ] New failure a catcher branches on → a new `AppException` / `FooException` subtype, mapped in the UI extension
- [ ] Bloc failure states carry `AppException error`; logged once via `logFailure`
- [ ] Copy only from the UI extension; retry only when `isRetryable`
- [ ] Nothing sensitive logged; secrets through `loggedSecret`
