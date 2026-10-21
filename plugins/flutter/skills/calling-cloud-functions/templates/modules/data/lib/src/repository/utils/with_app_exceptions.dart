import 'package:data/src/data_store/remote/api/utils/api_exception.dart';
import 'package:domain/domain_model.dart';
import 'package:log/log.dart';

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
/// leave the data layer. A code with a feature meaning is mapped inside the
/// body first (handling-errors).
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
