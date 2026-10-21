import 'package:log/src/log_types.dart';
import 'package:stack_trace/stack_trace.dart';

List<String> formatLogEvent(LogEvent event) => [
  '${event.time.toIso8601String()} ${_label(event.level)} '
      '${logCallerLocation(event.stackTrace) ?? '<unknown>'}',
  ...'${event.message}'.split('\n'),
  if (event.error case final error?) ...'$error'.split('\n'),
  if (event.stackTrace case final stackTrace?) ...'$stackTrace'.split('\n'),
];

/// The first frame outside this package: where `log.x(...)` was called, or
/// where [stackTrace] was thrown.
String? logCallerLocation(StackTrace? stackTrace) {
  final frames = Trace.from(stackTrace ?? StackTrace.current).frames;
  for (final frame in frames) {
    if (frame.package == 'log') continue;
    return frame.location;
  }
  return null;
}

String _label(Level level) => switch (level) {
  .trace => 'TRACE',
  .debug => 'DEBUG',
  .info => 'INFO',
  .warning => 'WARN',
  .error => 'ERROR',
  .fatal => 'FATAL',
};
