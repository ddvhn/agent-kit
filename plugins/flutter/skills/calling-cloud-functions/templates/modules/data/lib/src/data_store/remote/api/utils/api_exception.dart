/// Transport failure, classified once in the API client. Never leaves data.
/// Covers every HttpsError code the backend can emit, plus parse failures.
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

/// For REST sources; callables use the code table in their client.
ApiErrorCode apiErrorCodeForStatus(int statusCode) => switch (statusCode) {
  400 || 422 => .invalidArgument,
  401 => .unauthenticated,
  403 => .permissionDenied,
  404 => .notFound,
  408 || 504 => .timeout,
  409 => .alreadyExists,
  412 => .failedPrecondition,
  429 => .resourceExhausted,
  501 => .unimplemented,
  502 || 503 => .unavailable,
  500 => .internal,
  _ => .unknown,
};
