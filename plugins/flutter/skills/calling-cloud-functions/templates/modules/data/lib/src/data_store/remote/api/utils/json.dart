/// Callable results arrive as `Map<Object?, Object?>` on mobile and as
/// converted JS objects on web; never test `is Map<String, dynamic>`.
/// Converts them, deeply, into the shape `fromJson` expects. Anything that
/// is not a JSON object throws [FormatException] (→ `invalidResponse`).
Map<String, Object?> jsonObject(Object? value) => switch (value) {
  final Map<Object?, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) '$key': _jsonValue(value),
  },
  _ => throw FormatException('Expected a JSON object, got $value'),
};

Object? _jsonValue(Object? value) => switch (value) {
  final Map<Object?, Object?> map => jsonObject(map),
  final List<Object?> list => list.map(_jsonValue).toList(),
  _ => value,
};
