import 'dart:io';

import 'package:log/src/file_log_sink_io.dart';
import 'package:log/src/log_types.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('log_sink_'));
  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  File latest() => File('${directory.path}/latest.log');

  test('no sink when the directory cannot be created', () async {
    final blocker = File('${directory.path}/file')..writeAsStringSync('');
    expect(
      await createFileLogOutput(directoryPath: '${blocker.path}/logs'),
      isNull,
    );
    expect(await snapshotLogFilesForShare(), isEmpty);
  });

  test('writes a session header and each event', () async {
    final output = (await createFileLogOutput(directoryPath: directory.path))!;
    await output.init();
    output.output(LogEvent(.info, 'm'), ['line one', 'line two']);

    expect(latest().readAsStringSync(), contains('line one\nline two\n\n'));
  });

  test('rotates past 1 MB and keeps two rotated files', () async {
    final output = (await createFileLogOutput(directoryPath: directory.path))!;
    for (final day in ['01', '02', '03']) {
      final name = '2000-01-$day.log';
      File('${directory.path}/$name').writeAsStringSync('old');
    }
    latest().writeAsStringSync('x' * (1024 * 1024));

    output.output(LogEvent(.info, 'm'), ['after rotation']);

    final logs = directory.listSync().whereType<File>().where(
      (file) => file.path.endsWith('.log'),
    );
    expect(logs, hasLength(3)); // latest.log + two rotated
    expect(latest().readAsStringSync(), 'after rotation\n\n');
  });

  test('never throws when the directory disappears', () async {
    final output = (await createFileLogOutput(directoryPath: directory.path))!;
    directory.deleteSync(recursive: true);

    await output.init();
    output.output(LogEvent(.info, 'm'), ['lost']);
    expect(await snapshotLogFilesForShare(), isEmpty);
  });

  test('snapshots the log files into share/', () async {
    final output = (await createFileLogOutput(directoryPath: directory.path))!;
    await output.init();
    await snapshotLogFilesForShare(); // a second snapshot replaces the first

    final files = await snapshotLogFilesForShare();
    expect(files.single, endsWith('share/latest.log'));
  });

  test('destroy forgets only the active sink', () async {
    final first = (await createFileLogOutput(directoryPath: directory.path))!;
    final second = (await createFileLogOutput(directoryPath: directory.path))!;
    await second.init();

    await first.destroy();
    expect(await snapshotLogFilesForShare(), isNotEmpty);

    await second.destroy();
    expect(await snapshotLogFilesForShare(), isEmpty);
  });
}
