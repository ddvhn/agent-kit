import 'package:data/src/data_store/remote/api/utils/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every documented HTTP status has its code; others are unknown', () {
    const table = {
      400: ApiErrorCode.invalidArgument,
      422: ApiErrorCode.invalidArgument,
      401: ApiErrorCode.unauthenticated,
      403: ApiErrorCode.permissionDenied,
      404: ApiErrorCode.notFound,
      408: ApiErrorCode.timeout,
      504: ApiErrorCode.timeout,
      409: ApiErrorCode.alreadyExists,
      412: ApiErrorCode.failedPrecondition,
      429: ApiErrorCode.resourceExhausted,
      500: ApiErrorCode.internal,
      501: ApiErrorCode.unimplemented,
      502: ApiErrorCode.unavailable,
      503: ApiErrorCode.unavailable,
      418: ApiErrorCode.unknown,
    };
    table.forEach((status, code) {
      expect(apiErrorCodeForStatus(status), code, reason: '$status');
    });
  });

  test('toString names the code, the status, and the server code', () {
    expect(
      const ApiException(
        .notFound,
        statusCode: 404,
        serverCode: 'foo.notFound',
      ).toString(),
      'ApiException(notFound, status: 404, server: foo.notFound)',
    );
  });
}
