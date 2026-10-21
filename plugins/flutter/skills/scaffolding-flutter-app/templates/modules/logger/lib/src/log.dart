import 'package:log/src/file_log_sink.dart';
import 'package:log/src/log_format.dart';
import 'package:log/src/log_types.dart';

export 'package:log/src/file_log_sink.dart' show snapshotLogFilesForShare;
export 'package:log/src/log_types.dart' show Level, Logger;

/// Flutter's `kReleaseMode`, without depending on Flutter.
const _isRelease = bool.fromEnvironment('dart.vm.product');

Logger? _log;
Future<void>? _initialization;

/// The app logger: `log.d` / `log.i` / `log.w` / `log.e(message, error:,
/// stackTrace:)`. Not in GetIt; [initializeLogger] runs first in `main` and
/// in every test setup whose code logs.
Logger get log =>
    _log ?? (throw StateError('Call initializeLogger() before using log'));

bool get isLoggerInitialized => _log != null;

/// Idempotent: later calls return the first initialization. Without
/// [logsDirectoryPath] (tests, web) there is no file sink.
Future<void> initializeLogger({String? logsDirectoryPath}) =>
    _initialization ??= _initialize(logsDirectoryPath);

Future<void> _initialize(String? logsDirectoryPath) async {
  final fileOutput = logsDirectoryPath == null
      ? null
      : await createFileLogOutput(directoryPath: logsDirectoryPath);
  final logger = Logger(
    format: formatLogEvent,
    outputs: [if (!_isRelease) const _ConsoleLogOutput(), ?fileOutput],
  );
  await logger.init();
  _log = logger;
}

/// `abcd...yz` for long values: enough to correlate, not enough to use.
/// Shorter values reveal nothing.
String redactedLogValue(String value) => value.length < 16
    ? '***'
    : '${value.substring(0, 4)}...${value.substring(value.length - 2)}';

/// A token or id that is sensitive but needed when debugging: full in debug
/// and profile builds, redacted in release. Never for passwords or payment
/// data — those are not logged at all.
String loggedSecret(String value, {bool release = _isRelease}) =>
    release ? redactedLogValue(value) : value;

final class _ConsoleLogOutput implements LogOutput {
  const _ConsoleLogOutput();

  @override
  Future<void> init() async {}

  @override
  void output(LogEvent event, List<String> lines) {
    lines.forEach(print);
  }

  @override
  Future<void> destroy() async {}
}
