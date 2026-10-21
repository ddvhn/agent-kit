import 'package:log/src/log_types.dart';
import 'package:test/test.dart';

final class _RecordingOutput implements LogOutput {
  final events = <LogEvent>[];
  var initialized = false;
  var destroyed = false;

  @override
  Future<void> init() async => initialized = true;

  @override
  void output(LogEvent event, List<String> lines) => events.add(event);

  @override
  Future<void> destroy() async => destroyed = true;
}

void main() {
  test('every level reaches every output with the formatted lines', () async {
    final output = _RecordingOutput();
    final logger = Logger(
      format: (event) => ['${event.message}'],
      outputs: [output],
    );
    await logger.init();

    final error = StateError('boom');
    final stackTrace = StackTrace.current;
    logger
      ..t('t')
      ..d('d')
      ..i('i')
      ..w('w')
      ..e('e', error: error, stackTrace: stackTrace)
      ..f('f');
    await logger.close();

    expect(output.initialized, isTrue);
    expect(output.destroyed, isTrue);
    expect(output.events.map((event) => event.level), Level.values);
    expect(output.events[4].error, same(error));
    expect(output.events[4].stackTrace, same(stackTrace));
  });

  test('LogEvent takes the given time or now', () {
    final time = DateTime.utc(2026);
    expect(LogEvent(.info, 'm', time: time).time, time);
    expect(LogEvent(.info, 'm').time.isAfter(time), isTrue);
  });
}
