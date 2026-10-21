import 'dart:async';

import 'package:data/src/data_store/local/database/db_record.dart';
import 'package:data/src/ttl_data_provider/ttl_data_provider.dart';
import 'package:domain/domain_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TtlDataProvider<String> provider;
  late List<DbRecord<String>> saved;
  late int networkCalls;
  DbRecord<String>? stored;

  setUp(() {
    provider = TtlDataProvider(ttl: const Duration(minutes: 5));
    saved = [];
    networkCalls = 0;
    stored = null;
  });

  Future<String> fetch(
    CachePolicy cachePolicy, {
    Future<String> Function()? network,
  }) => provider.fetch<String>(
    cachePolicy: cachePolicy,
    fetchFromDatabase: () async => stored,
    fetchFromNetwork:
        network ??
        () async {
          networkCalls++;
          return 'network-$networkCalls';
        },
    saveToDatabase: (record) async => saved.add(record),
    toDomain: (dto) => dto,
  );

  test('cache with nothing stored throws NotFoundException', () async {
    await expectLater(fetch(.cache), throwsA(isA<NotFoundException>()));
    expect(networkCalls, 0);
  });

  test('cache reads the database and remembers it', () async {
    stored = DbRecord(dto: 'stored', dbTimestamp: DateTime.now());

    expect(await fetch(.cache), 'stored');
    stored = null;
    expect(await fetch(.cache), 'stored');
  });

  test(
    'network saves the result, and a fresh record skips the network',
    () async {
      expect(await fetch(.network), 'network-1');
      expect(saved.single.dto, 'network-1');
      expect(await fetch(.network), 'network-1');
      expect(networkCalls, 1);
    },
  );

  test('refresh goes to the network even when the record is fresh', () async {
    expect(await fetch(.network), 'network-1');

    expect(await fetch(.refresh), 'network-2');
  });

  test('network refetches when the stored record is stale', () async {
    stored = DbRecord(
      dto: 'stale',
      dbTimestamp: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(await fetch(.networkIfNotCached), 'stale');

    expect(await fetch(.network), 'network-1');
  });

  test('concurrent network requests share one call', () async {
    final response = Completer<String>();
    final first = fetch(.network, network: () => response.future);
    final second = fetch(.network, network: () async => 'second call');
    response.complete('shared');

    expect(await Future.wait([first, second]), ['shared', 'shared']);
  });

  test(
    'clear forgets records and drops a response that was in flight',
    () async {
      expect(await fetch(.network), 'network-1');
      final response = Completer<String>();
      provider.evict();
      final inFlight = fetch(.network, network: () => response.future);

      provider.clear();
      response.complete('previous user');
      await inFlight;

      expect(saved.map((record) => record.dto), ['network-1']);
      await expectLater(fetch(.cache), throwsA(isA<NotFoundException>()));
    },
  );
}
