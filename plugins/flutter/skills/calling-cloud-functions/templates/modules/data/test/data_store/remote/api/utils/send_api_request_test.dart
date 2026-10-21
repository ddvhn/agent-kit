import 'dart:async';

import 'package:data/src/data_store/remote/api/utils/api_exception.dart';
import 'package:data/src/data_store/remote/api/utils/send_api_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';

Matcher _apiException(ApiErrorCode code) =>
    throwsA(isA<ApiException>().having((e) => e.code, 'code', code));

/// A wrong JSON type, as a generated model's cast would meet it.
int _decode(Object value) => value as int;

void main() {
  test('returns the result', () async {
    expect(await sendApiRequest(() async => 1), 1);
  });

  test('an ApiException passes through unchanged', () {
    const error = ApiException(.notFound, serverCode: 'foo.notFound');
    expect(sendApiRequest<void>(() => throw error), throwsA(same(error)));
  });

  test('timeouts, parse failures, and type errors are classified', () {
    expect(
      sendApiRequest<void>(() => throw TimeoutException('slow')),
      _apiException(.timeout),
    );
    expect(
      sendApiRequest<void>(
        () => throw CheckedFromJsonException({}, 'id', 'Foo', 'missing'),
      ),
      _apiException(.invalidResponse),
    );
    expect(
      sendApiRequest<void>(() => throw const FormatException('bad')),
      _apiException(.invalidResponse),
    );
    expect(
      sendApiRequest<int>(() async => _decode('not an int')),
      _apiException(.invalidResponse),
    );
  });

  test('classify builds the whole exception; null or none is unknown', () {
    const classified = ApiException(.unavailable, statusCode: 503);
    expect(
      sendApiRequest<void>(
        () => throw StateError('x'),
        classify: (_) => classified,
      ),
      throwsA(same(classified)),
    );
    expect(
      sendApiRequest<void>(() => throw StateError('x'), classify: (_) => null),
      _apiException(.unknown),
    );
    expect(
      sendApiRequest<void>(() => throw StateError('x')),
      _apiException(.unknown),
    );
  });
}
