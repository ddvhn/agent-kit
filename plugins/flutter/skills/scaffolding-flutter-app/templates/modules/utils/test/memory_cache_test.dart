import 'package:test/test.dart';
import 'package:utils/utils.dart';

void main() {
  late DateTime now;
  late MemoryCache<String, int> cache;

  setUp(() {
    now = DateTime.utc(2030);
    cache = MemoryCache(
      maxEntries: 2,
      ttl: const Duration(minutes: 1),
      now: () => now,
    );
  });

  test('a missing key is null', () => expect(cache.get('a'), isNull));

  test('an entry expires exactly at its ttl', () {
    cache.set('a', 1);
    now = now.add(const Duration(seconds: 59));
    expect(cache.get('a'), 1);
    now = now.add(const Duration(seconds: 1));
    expect(cache.get('a'), isNull);
  });

  test('evicts the least recently used entry', () {
    cache
      ..set('a', 1)
      ..set('b', 2);
    expect(cache.get('a'), 1);
    cache.set('c', 3);
    expect([cache.get('a'), cache.get('b'), cache.get('c')], [1, null, 3]);
  });

  test('remove and clear drop entries', () {
    cache
      ..set('a', 1)
      ..set('b', 2)
      ..remove('a');
    expect(cache.get('a'), isNull);
    cache.clear();
    expect(cache.get('b'), isNull);
  });
}
