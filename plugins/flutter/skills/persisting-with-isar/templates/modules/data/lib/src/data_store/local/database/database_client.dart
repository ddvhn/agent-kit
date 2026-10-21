/// The local database. Speaks DTOs; one method pair per stored entity
/// (persisting-with-isar).
abstract interface class DatabaseClient {
  /// Idempotent; every other method awaits it, so `main` may only warm up.
  Future<void> initialize();

  Future<void> dispose({bool deleteFromDisk = false});

  /// Removes everything stored for the signed-in user, when the user changes
  /// (`data` rule → Caching). Collections that hold no user data may stay.
  Future<void> clearUserData();

  // Future<DbRecord<FooDto>?> fetchFoo({required String fooId});
  // Future<void> saveFoo(DbRecord<FooDto> record);
}
