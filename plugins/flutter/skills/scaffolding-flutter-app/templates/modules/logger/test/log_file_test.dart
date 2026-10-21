import 'dart:io';

import 'package:log/log.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('log_file_'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('initializeLogger with a directory writes latest.log', () async {
    await initializeLogger(logsDirectoryPath: directory.path);

    log.w('written to the file');

    final latest = File('${directory.path}/latest.log').readAsStringSync();
    expect(latest, contains('--- session'));
    expect(latest, contains('written to the file'));
  });
}
