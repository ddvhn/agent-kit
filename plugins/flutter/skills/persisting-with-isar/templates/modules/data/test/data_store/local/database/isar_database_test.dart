import 'package:data/src/data_store/local/database/isar_database/isar_database.dart';
import 'package:data/src/data_store/local/database/isar_database/isar_database_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/database_test_utils.dart';

/// The store's lifecycle against a real database in build/test. Each
/// collection adds its round trips next to these (persisting-with-isar →
/// Tests).
void main() {
  late IsarDatabase database;

  setUp(() => database = testDatabase());
  tearDown(() => database.dispose(deleteFromDisk: true));

  test('initialize is idempotent', () async {
    await database.initialize();
    await database.initialize();
  });

  test('clearUserData on an open database succeeds', () async {
    await database.clearUserData();
  });

  test(
    'a disposed database refuses access; dispose twice is a no-op',
    () async {
      await database.initialize();
      await database.dispose();
      await database.dispose();

      expect(database.initialize, throwsStateError);
    },
  );

  test('dispose before the first access closes nothing', () async {
    await testDatabase().dispose();
  });

  test('a failed open is not cached: the next access retries', () async {
    final broken = IsarDatabase(
      customDatabaseDirPath: '/dev/null/not-a-directory',
      customDatabaseName: 'broken',
    );
    await expectLater(broken.initialize(), throwsA(anything));
    await expectLater(broken.initialize(), throwsA(anything));
  });

  test('dispose during a failing open returns without throwing', () async {
    final broken = IsarDatabase(
      customDatabaseDirPath: '/dev/null/not-a-directory',
      customDatabaseName: 'broken',
    );
    final open = broken.initialize();
    final dispose = broken.dispose();
    await expectLater(open, throwsA(anything));
    await dispose;
  });

  test('the factory builds the native database on the VM', () {
    expect(IsarDatabaseClientFactory.newClient(), isA<IsarDatabase>());
  });
}
