import 'package:log/src/log_format.dart';
import 'package:log/src/log_types.dart';
import 'package:test/test.dart';

void main() {
  test('labels every level', () {
    final labels = Level.values.map(
      (level) => formatLogEvent(LogEvent(level, 'm')).first.split(' ')[1],
    );
    expect(labels, ['TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL']);
  });

  test('splits message, error, and stack trace into lines', () {
    final lines = formatLogEvent(
      LogEvent(
        .error,
        'first\nsecond',
        error: 'cause',
        stackTrace: StackTrace.fromString('#0 main (file:///foo.dart:1:1)'),
        time: DateTime.utc(2026),
      ),
    );
    expect(lines.first, startsWith('2026-01-01T00:00:00.000Z ERROR '));
    expect(lines, containsAllInOrder(['first', 'second', 'cause']));
  });

  test('the caller is the first frame outside the log package', () {
    final trace = StackTrace.fromString(
      '#0 Logger.i (package:log/src/log_types.dart:1:1)\n'
      '#1 main (package:foo/main.dart:7:3)',
    );
    expect(logCallerLocation(trace), contains('main.dart 7:3'));
  });

  test('no caller when every frame is in the log package', () {
    final trace = StackTrace.fromString(
      '#0 Logger.i (package:log/src/log_types.dart:1:1)',
    );
    expect(logCallerLocation(trace), isNull);
    expect(
      formatLogEvent(LogEvent(.info, 'm', stackTrace: trace)).first,
      endsWith('<unknown>'),
    );
  });

  test('without a stack trace the current one is used', () {
    expect(logCallerLocation(null), isNotNull);
  });
}
