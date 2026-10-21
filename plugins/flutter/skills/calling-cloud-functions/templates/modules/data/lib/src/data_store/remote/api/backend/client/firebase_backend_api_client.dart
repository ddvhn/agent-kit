import 'package:cloud_functions/cloud_functions.dart';
import 'package:data/src/data_store/remote/api/backend/client/backend_api_client.dart';
import 'package:data/src/data_store/remote/api/utils/api_exception.dart';
import 'package:data/src/data_store/remote/api/utils/json.dart';
import 'package:data/src/data_store/remote/api/utils/send_api_request.dart';

/// [BackendApiClient] over Firebase callables (calling-cloud-functions).
final class FirebaseBackendApiClient implements BackendApiClient {
  FirebaseBackendApiClient(this.functions);

  /// From DI, already pointed at the region and, when configured, the
  /// emulator (`injectDataLayer`).
  final FirebaseFunctions functions;

  // @override
  // Future<FooDto> getFoo({required String fooId}) => functions.callJson(
  //   'getFoo',
  //   {'fooId': fooId},
  //   (json) => FooApiModel.fromJson(json).toDto(),
  // );
}

extension CallableJson on FirebaseFunctions {
  /// Longer than the backend's default `timeoutSeconds` (60): a client that
  /// gives up first lets a retry duplicate a write that still commits.
  static const timeout = Duration(seconds: 70);

  /// Calls [name] with [data] and parses the result with [fromJson]; every
  /// failure leaves as an `ApiException`.
  Future<T> callJson<T>(
    String name,
    Map<String, Object?> data,
    T Function(Map<String, Object?> json) fromJson,
  ) => sendApiRequest(() async {
    final callable = httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: timeout),
    );
    final result = await callable.call<Object?>(data);
    return fromJson(jsonObject(result.data));
  }, classify: _classify);
}

ApiException? _classify(Object error) => switch (error) {
  FirebaseFunctionsException(:final code) => ApiException(
    apiErrorCodeForCallable(code),
  ),
  _ => null,
};

/// HttpsError codes (`functions/<code>` prefixes stripped by the SDK).
ApiErrorCode apiErrorCodeForCallable(String code) => switch (code) {
  'unavailable' => .unavailable,
  'deadline-exceeded' => .timeout,
  'unauthenticated' => .unauthenticated,
  'permission-denied' => .permissionDenied,
  'not-found' => .notFound,
  'invalid-argument' => .invalidArgument,
  'out-of-range' => .outOfRange,
  'already-exists' => .alreadyExists,
  'failed-precondition' => .failedPrecondition,
  'resource-exhausted' => .resourceExhausted,
  'aborted' => .aborted,
  'cancelled' => .cancelled,
  'unimplemented' => .unimplemented,
  'internal' => .internal,
  'data-loss' => .dataLoss,
  _ => .unknown,
};
