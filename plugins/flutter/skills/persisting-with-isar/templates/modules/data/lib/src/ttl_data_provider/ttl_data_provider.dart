import 'package:data/src/data_store/local/database/db_record.dart';
import 'package:domain/domain_model.dart';

/// Implements `CachePolicy` (`data` rule, Caching): the in-memory record
/// (from the network, or from the database with its `dbTimestamp`) answers
/// `cache` and `networkIfNotCached`, and answers `network` while younger than
/// [ttl]; `refresh` always goes to the network. Concurrent network requests
/// for one key share one call.
final class TtlDataProvider<T> {
  TtlDataProvider({required this.ttl});

  final Duration ttl;
  final _records = <String, ({T value, DateTime timestamp})>{};
  final _inFlight = <String, Future<T>>{};

  /// Bumped by [clear]: a request that started before it is not remembered.
  var _generation = 0;

  Future<T> fetch<Dto>({
    String key = '',
    required CachePolicy cachePolicy,
    required Future<DbRecord<Dto>?> Function() fetchFromDatabase,
    required Future<Dto> Function() fetchFromNetwork,
    required Future<void> Function(DbRecord<Dto> record) saveToDatabase,
    required T Function(Dto dto) toDomain,
  }) async {
    final memory = _records[key];
    if (memory != null && cachePolicy != .refresh) {
      final fresh = DateTime.now().difference(memory.timestamp) < ttl;
      if (fresh || cachePolicy != .network) return memory.value;
    }
    if (cachePolicy case .cache || .networkIfNotCached) {
      final stored = await fetchFromDatabase();
      if (stored != null) {
        return _remember(key, toDomain(stored.dto), stored.dbTimestamp);
      }
      if (cachePolicy == .cache) throw const NotFoundException();
    }
    // Stored before anything can complete, removed when it completes. The
    // callback has a block body: an arrow would return the removed future,
    // and the whenComplete future would wait on itself.
    return _inFlight[key] ??=
        _fetchAndSave(
          key: key,
          fetchFromNetwork: fetchFromNetwork,
          saveToDatabase: saveToDatabase,
          toDomain: toDomain,
        ).whenComplete(() {
          _inFlight.remove(key);
        });
  }

  void evict({String key = ''}) => _records.remove(key);

  /// Forgets every record; the owning repository calls it when the signed-in
  /// user changes (`data` rule → Caching).
  void clear() {
    _generation++;
    _records.clear();
    _inFlight.clear();
  }

  Future<T> _fetchAndSave<Dto>({
    required String key,
    required Future<Dto> Function() fetchFromNetwork,
    required Future<void> Function(DbRecord<Dto> record) saveToDatabase,
    required T Function(Dto dto) toDomain,
  }) async {
    final generation = _generation;
    final record = DbRecord(
      dto: await fetchFromNetwork(),
      dbTimestamp: DateTime.now(),
    );
    final value = toDomain(record.dto);
    if (generation != _generation) return value; // the user changed meanwhile
    await saveToDatabase(record);
    return _remember(key, value, record.dbTimestamp);
  }

  T _remember(String key, T value, DateTime timestamp) {
    _records[key] = (value: value, timestamp: timestamp);
    return value;
  }
}
