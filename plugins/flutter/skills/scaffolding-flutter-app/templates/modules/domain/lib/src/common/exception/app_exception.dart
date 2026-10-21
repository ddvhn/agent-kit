/// Every failure a caller may branch on. Repositories throw only these, blocs
/// keep them in failure states, and the UI maps them to copy in one place
/// (handling-errors). Subtypes live in this file; a feature adds its own
/// sealed hierarchy under [FeatureException].
sealed class AppException implements Exception {
  const AppException();

  /// [error] itself when it is an [AppException], else [UnknownException].
  factory AppException.from(Object error) => switch (error) {
    final AppException exception => exception,
    _ => UnknownException(error),
  };

  @override
  String toString() => '$runtimeType';
}

/// No connection, a timeout, or the host is unreachable. Retrying may help.
final class NetworkUnavailableException extends AppException {
  const NetworkUnavailableException();
}

/// The entity does not exist, or nothing is cached for `CachePolicy.cache`.
final class NotFoundException extends AppException {
  const NotFoundException();
}

/// Signed out or the session expired: the user has to sign in.
final class UnauthorizedException extends AppException {
  const UnauthorizedException();
}

/// Too many requests, or a quota is used up. Retrying later may help.
final class QuotaExceededException extends AppException {
  const QuotaExceededException();
}

/// Signed in, but not allowed to do this.
final class PermissionDeniedException extends AppException {
  const PermissionDeniedException();
}

/// The backend rejected the input. Field-level checks are domain results of
/// the feature (`FooDraft.validate()`), not this exception.
final class ValidationException extends AppException {
  const ValidationException();
}

/// A failure nobody branches on: a bug or an unexpected response. Logged
/// with its stack trace where it is created.
final class UnknownException extends AppException {
  const UnknownException([this.cause]);

  final Object? cause;

  @override
  String toString() => 'UnknownException($cause)';
}

/// Base of a feature's own hierarchy:
/// `sealed class FooException extends FeatureException`.
abstract class FeatureException extends AppException {
  const FeatureException();
}
