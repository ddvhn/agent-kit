import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:data/testing.dart';
import 'package:isar_plus/isar_plus.dart';

/// Host builds of the Isar core for `flutter test` (the VM has no
/// isar_plus_flutter_libs). Native code loaded into the test process: each
/// asset is pinned by SHA-256 for this Isar version; bumping isar_plus means
/// new hashes here (`sha256sum` of the release assets), or the load fails.
const _release = 'https://github.com/ahmtydn/isar_plus/releases/download';
const _pinnedVersion = '1.3.9';
const _sha256 = {
  'libisar_plus_linux_x64.so':
      'd0889e21a8b474f4be5ba0bfa3c0e335dc1cca13b3020338e5d4e8924d5e6f58',
  'isar_plus_windows_x64.dll':
      'bc9933f020c1aa7aac3db10b1bda306cc024e568cbf5776395e51923e242bf0d',
  'isar_plus_core.xcframework.zip':
      '01f709c7b3ae6a01292e211789e3cc0118986aab98b713a75efb988091086356',
};

Future<void>? _isarCore;

/// Once per test isolate; memoized, so a later call never downloads.
Future<void> initializeTestIsarCore() => _isarCore ??= _loadIsarCore();

/// A fresh database per test; `dispose(deleteFromDisk: true)` in tearDown.
IsarDatabase testDatabase() => IsarDatabase(
  customDatabaseDirPath: 'build/test/database',
  customDatabaseName: 'test_${DateTime.now().microsecondsSinceEpoch}',
);

Future<void> _loadIsarCore() async {
  if (Isar.version != _pinnedVersion) {
    throw StateError(
      'isar_plus ${Isar.version} has no pinned core hashes: update _sha256.',
    );
  }
  final dir = Directory('build/test/isar/${Isar.version}');
  await dir.create(recursive: true);
  final lock = await File('${dir.path}/.lock').open(mode: FileMode.write);
  // Parallel test isolates download once.
  await lock.lock(FileLock.blockingExclusive);
  try {
    await Isar.initialize((await _hostLibrary(dir)).absolute.path);
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<File> _hostLibrary(Directory dir) async {
  if (Platform.isLinux || Platform.isWindows) {
    // x64 assets; an arm64 runner needs its own asset and hash.
    final (name, asset) = Platform.isLinux
        ? ('libisar_plus.so', 'libisar_plus_linux_x64.so')
        : ('isar_plus.dll', 'isar_plus_windows_x64.dll');
    final file = File('${dir.path}/$name');
    if (!file.existsSync()) await _download(asset, file);
    return file;
  }
  final unpacked = Directory('${dir.path}/xcframework'); // macOS
  if (!unpacked.existsSync()) {
    final zip = File('${dir.path}/core.zip');
    await _download('isar_plus_core.xcframework.zip', zip);
    final unzip = await Process.run('unzip', [
      '-q',
      '-o',
      zip.path,
      '-d',
      unpacked.path,
    ]);
    if (unzip.exitCode != 0) {
      throw ProcessException(
        'unzip',
        [zip.path],
        '${unzip.stderr}',
        unzip.exitCode,
      );
    }
  }
  return unpacked
      .listSync(recursive: true)
      .whereType<File>()
      .firstWhere(
        (file) =>
            file.path.contains('macos-') &&
            file.path.endsWith('/IsarPlusCore') &&
            !file.path.contains('dSYM'),
      );
}

/// Downloads to a temp file, checks the pinned SHA-256, then renames, so a
/// partial or tampered file is never loaded and never cached.
Future<void> _download(String asset, File dest) async {
  final url = Uri.parse('$_release/v${Isar.version}/$asset');
  final client = HttpClient();
  final tmp = File('${dest.path}.tmp');
  try {
    final response = await (await client.getUrl(url)).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    await response.pipe(tmp.openWrite());
    final actual = sha256.convert(await tmp.readAsBytes()).toString();
    if (actual != _sha256[asset]) {
      await tmp.delete();
      throw StateError('$asset: SHA-256 $actual does not match the pin');
    }
    await tmp.rename(dest.path);
  } finally {
    client.close(force: true);
  }
}
