import 'package:domain/domain_model.dart';
import 'package:test/test.dart';

void main() {
  test('from() keeps an AppException', () {
    const error = NotFoundException();
    expect(AppException.from(error), same(error));
  });

  test('from() wraps anything else in UnknownException', () {
    final cause = StateError('bug');
    expect(
      AppException.from(cause),
      isA<UnknownException>().having((e) => e.cause, 'cause', same(cause)),
    );
  });

  // Tear-offs run the const constructors at runtime, so coverage sees them.
  test('every subtype is an AppException', () {
    final constructors = <AppException Function()>[
      NetworkUnavailableException.new,
      NotFoundException.new,
      UnauthorizedException.new,
      QuotaExceededException.new,
      PermissionDeniedException.new,
      ValidationException.new,
      UnknownException.new,
      _FooException.new,
    ];

    for (final create in constructors) {
      expect(create(), isA<AppException>());
    }
  });

  test('toString names the type, and the cause for UnknownException', () {
    expect(
      const NetworkUnavailableException().toString(),
      'NetworkUnavailableException',
    );
    expect(const UnknownException('x').toString(), 'UnknownException(x)');
  });
}

final class _FooException extends FeatureException {
  const _FooException();
}
