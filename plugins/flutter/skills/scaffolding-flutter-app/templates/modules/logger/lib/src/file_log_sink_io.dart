import 'dart:io';

import 'package:log/src/log_types.dart';

const _latestFileName = 'latest.log';
const _maxFileSizeBytes = 1024 * 1024;
const _maxRotatedFiles = 2;

_RotatingFileLogOutput? _active;

/// A rotating file sink in [directoryPath] (1 MB, two rotated files), or null
/// when the directory cannot be created. Logging never throws.
Future<LogOutput?> createFileLogOutput({required String directoryPath}) async {
  try {
    final directory = Directory(directoryPath);
    await directory.create(recursive: true);
    return _active = _RotatingFileLogOutput(directory);
  } catch (_) {
    return _active = null;
  }
}

/// Copies of the current log files for "report an issue" (share sheet or
/// email attachment). Empty when there is no file sink.
Future<List<String>> snapshotLogFilesForShare() async =>
    await _active?._snapshot() ?? const [];

final class _RotatingFileLogOutput implements LogOutput {
  _RotatingFileLogOutput(this._directory);

  final Directory _directory;

  File get _latest => File('${_directory.path}/$_latestFileName');

  @override
  Future<void> init() async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    try {
      await _latest.writeAsString('--- session $stamp ---\n', mode: .append);
    } on FileSystemException {
      // Logging never throws: the app starts, and output() keeps trying.
    }
  }

  @override
  void output(LogEvent event, List<String> lines) {
    try {
      _rotateIfNeeded();
      _latest.writeAsStringSync('${lines.join('\n')}\n\n', mode: .append);
    } catch (_) {}
  }

  @override
  Future<void> destroy() async {
    if (identical(_active, this)) _active = null;
  }

  /// Copies into `share/` under the logs directory, replacing the last
  /// snapshot, so the files stay stable while the share sheet reads them.
  Future<List<String>> _snapshot() async {
    try {
      final target = Directory('${_directory.path}/share');
      if (target.existsSync()) await target.delete(recursive: true);
      await target.create();
      return _logFiles()
          .map(
            (file) => file
                .copySync('${target.path}/${file.uri.pathSegments.last}')
                .path,
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<File> _logFiles() =>
      _directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  void _rotateIfNeeded() {
    final latest = _latest;
    if (!latest.existsSync() || latest.lengthSync() < _maxFileSizeBytes) {
      return;
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    latest.renameSync('${_directory.path}/$stamp.log');
    final rotated =
        _logFiles().where((file) => file.path != latest.path).toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (final file in rotated.skip(_maxRotatedFiles)) {
      file.deleteSync();
    }
  }
}
