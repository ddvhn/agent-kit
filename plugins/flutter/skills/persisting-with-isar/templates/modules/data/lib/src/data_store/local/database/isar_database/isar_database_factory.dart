import 'package:data/src/data_store/local/database/database_client.dart';
import 'package:data/src/data_store/local/database/isar_database/isar_database.dart'
    if (dart.library.js_interop) 'package:data/src/data_store/local/database/isar_database/isar_database_web.dart';

abstract final class IsarDatabaseClientFactory {
  static DatabaseClient newClient() => IsarDatabase();
}
