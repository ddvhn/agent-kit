/// An in-memory cache with a time to live and least-recently-used eviction:
/// at most [maxEntries], each valid for [ttl]. A null from [get] means
/// missing or expired, so store non-null values. Time is injected so tests
/// step it.
final class MemoryCache<K, V extends Object> {
  MemoryCache({
    required this.maxEntries,
    required this.ttl,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxEntries;
  final Duration ttl;
  final DateTime Function() _now;

  /// Insertion-ordered: the first key is the least recently used.
  final _entries = <K, ({V value, DateTime storedAt})>{};

  V? get(K key) {
    final entry = _entries.remove(key);
    if (entry == null || _now().difference(entry.storedAt) >= ttl) return null;
    _entries[key] = entry;
    return entry.value;
  }

  void set(K key, V value) {
    _entries
      ..remove(key)
      ..[key] = (value: value, storedAt: _now());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(K key) => _entries.remove(key);

  void clear() => _entries.clear();
}
