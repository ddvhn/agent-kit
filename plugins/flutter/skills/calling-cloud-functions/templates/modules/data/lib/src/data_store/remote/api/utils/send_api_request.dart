import 'dart:async';

import 'package:data/src/data_store/remote/api/utils/api_exception.dart';
import 'package:json_annotation/json_annotation.dart';

/// Wraps every client call: whatever the transport throws leaves as an
/// [ApiException]. Transport-specific errors (HTTP status, callable codes)
/// are classified by the client's [classify], which builds the whole
/// exception (code, HTTP status, the server's own code) or returns null for
/// an error it does not know.
Future<T> sendApiRequest<T>(
  Future<T> Function() request, {
  ApiException? Function(Object error)? classify,
}) async {
  try {
    return await request();
  } on ApiException {
    rethrow;
  } on TimeoutException catch (_, stackTrace) {
    Error.throwWithStackTrace(const ApiException(.timeout), stackTrace);
  } on CheckedFromJsonException catch (_, stackTrace) {
    // `checked: true` (build.yaml) wraps every model parse failure in this.
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
