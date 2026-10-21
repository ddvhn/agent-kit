import 'package:domain/domain_model.dart';
import 'package:localization/localization.dart';
import 'package:log/log.dart';

/// The one place a domain failure becomes copy (handling-errors).
extension AppExceptionX on AppException {
  String message(AppLocalizations strings) => switch (this) {
    NetworkUnavailableException() => strings.errorOffline,
    NotFoundException() => strings.errorNotFound,
    UnauthorizedException() => strings.errorSignedOut,
    PermissionDeniedException() => strings.errorNotAllowed,
    QuotaExceededException() => strings.errorTooManyRequests,
    ValidationException() => strings.errorInvalidInput,
    UnknownException() => strings.errorGeneric,
    // One line per feature: final FooException e => e.message(strings),
    FeatureException() => strings.errorGeneric,
  };

  /// Whether a retry button makes sense; the rest needs another action.
  /// Exhaustive, so a new subtype has to decide.
  bool get isRetryable => switch (this) {
    NetworkUnavailableException() ||
    QuotaExceededException() ||
    UnknownException() => true,
    NotFoundException() ||
    UnauthorizedException() ||
    PermissionDeniedException() ||
    ValidationException() ||
    FeatureException() => false,
  };
}

/// Logs a bloc failure once. An [AppException] is expected, or (an
/// [UnknownException]) already logged with its trace where it was created;
/// anything else is a bug in this layer and is logged with the trace.
void logFailure(String message, Object error, StackTrace stackTrace) {
  if (error is AppException) {
    log.w('$message: $error');
  } else {
    log.e('$message: $error', error: error, stackTrace: stackTrace);
  }
}
