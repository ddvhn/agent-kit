import 'dart:io';

import 'package:data/src/data_store/local/database/database_client.dart';
import 'package:isar_plus/isar_plus.dart';
import 'package:path_provider/path_provider.dart';

final class IsarDatabase implements DatabaseClient {
  IsarDatabase({this.customDatabaseDirPath, this.customDatabaseName});

  static const defaultDatabaseName = 'app';
  static final _schemas = <IsarGeneratedSchema>[/* FooDbModelSchema, … */];

  final String? customDatabaseDirPath; // tests: a temp dir
  final String? customDatabaseName; // tests: a unique name per test
  Future<Isar>? _isar;
  var _isDisposed = false;

  @override
  Future<void> initialize() => _open();

  Future<Isar> _open() {
    if (_isDisposed) throw StateError('Database is disposed');
    return _isar ??= _openIsar().catchError((Object error, StackTrace stack) {
      _isar = null; // the next access retries
      Error.throwWithStackTrace(error, stack);
    });
  }

  // Application Support, not Documents: a re-fetchable cache is neither user
  // content nor something to back up.
  Future<Isar> _openIsar() async {
    final dir =
        customDatabaseDirPath ?? (await getApplicationSupportDirectory()).path;
    await Directory(dir).create(recursive: true);
    return Isar.openAsync(
      schemas: _schemas,
      directory: dir,
      name: customDatabaseName ?? defaultDatabaseName,
      // The inspector serves the database to a browser page in debug builds;
      // it holds user data, so it stays off (turn it on locally to debug).
      inspector: false,
    );
  }

  /// Empties every collection. An app with the offline queue runs it only
  /// with an empty queue and refuses otherwise (queueing-offline-actions →
  /// Requirements, 14–15).
  @override
  Future<void> clearUserData() async {
    final isar = await _open();
    await isar.writeAsync((isar) => isar.clear());
  }

  @override
  Future<void> dispose({bool deleteFromDisk = false}) async {
    if (_isDisposed) return;
    _isDisposed = true;
    final pending = _isar;
    if (pending == null) return;
    final Isar isar;
    try {
      isar = await pending;
    } catch (_) {
      return; // the open failed: nothing to close
    }
    isar.close(deleteFromDisk: deleteFromDisk);
  }
}
