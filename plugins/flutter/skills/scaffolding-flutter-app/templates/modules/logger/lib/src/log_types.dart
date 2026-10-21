enum Level { trace, debug, info, warning, error, fatal }

final class LogEvent {
  LogEvent(
    this.level,
    this.message, {
    this.error,
    this.stackTrace,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final Level level;
  final Object? message;
  final Object? error;
  final StackTrace? stackTrace;
  final DateTime time;
}

abstract interface class LogOutput {
  Future<void> init();

  void output(LogEvent event, List<String> lines);

  Future<void> destroy();
}

final class Logger {
  Logger({
    required List<String> Function(LogEvent event) format,
    required List<LogOutput> outputs,
  }) : _format = format,
       _outputs = outputs;

  final List<String> Function(LogEvent event) _format;
  final List<LogOutput> _outputs;

  Future<void> init() async {
    await Future.wait(_outputs.map((output) => output.init()));
  }

  void t(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _log(.trace, message, error: error, stackTrace: stackTrace);

  void d(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _log(.debug, message, error: error, stackTrace: stackTrace);

  void i(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _log(.info, message, error: error, stackTrace: stackTrace);

  void w(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _log(.warning, message, error: error, stackTrace: stackTrace);

  void e(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _log(.error, message, error: error, stackTrace: stackTrace);

  void f(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _log(.fatal, message, error: error, stackTrace: stackTrace);

  Future<void> close() async {
    await Future.wait(_outputs.map((output) => output.destroy()));
  }

  void _log(
    Level level,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final event = LogEvent(
      level,
      message,
      error: error,
      stackTrace: stackTrace,
    );
    final lines = _format(event);
    for (final output in _outputs) {
      output.output(event, lines);
    }
  }
}
