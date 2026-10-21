import 'package:data/src/data_store/local/database/database_client.dart';

/// Web: the same class and constructor as the native file, backed by
/// in-memory maps of DTOs (persisting-with-isar → Web). The parameters are
/// accepted so harnesses build it the same way; they have no effect.
final class IsarDatabase implements DatabaseClient {
  IsarDatabase({this.customDatabaseDirPath, this.customDatabaseName});

  final String? customDatabaseDirPath;
  final String? customDatabaseName;
  var _isDisposed = false;

  // final _foos = <String, DbRecord<FooDto>>{};

  @override
  Future<void> initialize() async {
    if (_isDisposed) throw StateError('Database is disposed');
  }

  @override
  Future<void> clearUserData() async {
    // _foos.clear();
  }

  @override
  Future<void> dispose({bool deleteFromDisk = false}) async {
    _isDisposed = true;
  }
}
