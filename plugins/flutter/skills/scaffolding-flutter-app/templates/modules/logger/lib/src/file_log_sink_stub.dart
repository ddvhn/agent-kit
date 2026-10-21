import 'package:log/src/log_types.dart';

// Web: no file sink.
Future<LogOutput?> createFileLogOutput({required String directoryPath}) async =>
    null;

Future<List<String>> snapshotLogFilesForShare() async => const [];
