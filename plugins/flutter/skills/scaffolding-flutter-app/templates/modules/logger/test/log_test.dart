import 'package:log/log.dart';
import 'package:test/test.dart';

// One isolate per test file: this file covers the logger before and after a
// console-only initialization; log_file_test.dart covers the file sink.
void main() {
  test('log throws until initializeLogger ran', () {
    expect(isLoggerInitialized, isFalse);
    expect(() => log, throwsStateError);
  });

  test('initializeLogger is idempotent and enables log', () async {
    final first = initializeLogger();
    expect(identical(first, initializeLogger()), isTrue);
    await first;

    expect(isLoggerInitialized, isTrue);
    log.i('started');
    await log.close();
  });

  group('redaction', () {
    test('short values reveal nothing', () {
      expect(redactedLogValue('123456789012345'), '***');
    });

    test('long values keep four leading and two trailing characters', () {
      expect(redactedLogValue('abcdefghijklmnopqrstuvwxyz'), 'abcd...yz');
    });

    test('loggedSecret redacts only in release', () {
      const value = 'abcdefghijklmnopqrstuvwxyz';
      expect(loggedSecret(value, release: false), value);
      expect(loggedSecret(value, release: true), 'abcd...yz');
    });
  });
}
