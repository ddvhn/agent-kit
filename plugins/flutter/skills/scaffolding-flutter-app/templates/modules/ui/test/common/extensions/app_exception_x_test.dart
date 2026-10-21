import 'package:domain/domain_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localization/localization.dart';
import 'package:ui/src/common/extensions/app_exception_x.dart';

void main() {
  final strings = lookupAppLocalizations(const Locale('en'));

  test('every exception has copy', () {
    const exceptions = <AppException>[
      NetworkUnavailableException(),
      NotFoundException(),
      UnauthorizedException(),
      PermissionDeniedException(),
      QuotaExceededException(),
      ValidationException(),
      UnknownException(),
      _FooException(),
    ];

    for (final exception in exceptions) {
      expect(exception.message(strings), isNotEmpty, reason: '$exception');
    }
  });

  test('only transient failures are retryable', () {
    expect(const NetworkUnavailableException().isRetryable, isTrue);
    expect(const QuotaExceededException().isRetryable, isTrue);
    expect(const UnknownException().isRetryable, isTrue);
    expect(const NotFoundException().isRetryable, isFalse);
    expect(const UnauthorizedException().isRetryable, isFalse);
    expect(const PermissionDeniedException().isRetryable, isFalse);
    expect(const ValidationException().isRetryable, isFalse);
    expect(const _FooException().isRetryable, isFalse);
  });

  test('logFailure logs expected failures and bugs without throwing', () {
    logFailure('expected', const NotFoundException(), StackTrace.current);
    logFailure('bug', StateError('bug'), StackTrace.current);
  });
}

final class _FooException extends FeatureException {
  const _FooException();
}
