---
name: persisting-with-isar
description: Persist data locally in a Flutter app with Isar (isar_plus) — set up the database store (DatabaseClient contract, lazily initialized IsarDatabase, in-memory web variant), add Db models and their DTO conversions, read and save with timestamps, TTL-aware cache-then-network repositories, schema changes, and database tests (Isar core in flutter_test_config.dart). Use when adding offline caching or a new persisted entity, changing a Db model or schema, wiring the database in DI, or writing database round-trip tests.
---

# Persisting with Isar

Policy: the stack `data` rule (stores, model kinds, Database lifecycle, Caching) and `blocs` rule (cache-then-refresh). The project's Isar package, database folder, and schema-change strategy: the repository's `.claude/rules/`.

## Package

Default: **`isar_plus`** (`isar_plus` + `isar_plus_flutter_libs`, Isar 4 API) — maintained, string ids, `openAsync`, `writeAsync`. `isar_community` (Isar 3 API) only in projects that already use it; moving one to `isar_plus` is a planned migration with an ADR (`recording-decisions`), since the file format differs and the local database is rebuilt. The templates below use the `isar_plus` API.

| | `isar_plus` (default, Isar 4 API) | `isar_community` (legacy, Isar 3 API) |
| --- | --- | --- |
| Id | `@id final String fooId` (or `int`) | `Id id = Isar.autoIncrement;` + `@Index(unique: true, replace: true)` on the business key |
| Open | `await Isar.openAsync(schemas: [...], directory:, name:)` | `await Isar.open([...], directory:, name:)` |
| Read | `await isar.fooDbModels.getAsync(id)`, `isar.fooDbModels.where()…` | `await isar.fooDbModels.get(id)`, `isar.fooDbModels.filter().fooIdEqualTo(id).findFirst()` |
| Write | `await isar.writeAsync((db) => db.fooDbModels.put(model))` | `await isar.writeTxn(() => isar.fooDbModels.put(model))` |

Dependencies: the Isar package and its `_flutter_libs` in the data package, `build_runner` as a dev dependency (`isar_plus` ships its own builder; no separate generator package); `path_provider` for the directory. Regenerate `*.g.dart` with `dart run build_runner build` (`CLAUDE.md` → Verification).

## Files

The scaffolded app has no database. The first collection brings the whole store from `templates/` next to this skill (laid out as in the app):

- domain: `src/common/model/cache_policy.dart`, exported from `domain_model.dart`.
- data: `src/data_store/local/database/` (`database_client.dart`, `db_record.dart`, `isar_database/` native, web, and factory), `src/ttl_data_provider/ttl_data_provider.dart`; tests: `test/flutter_test_config.dart` (replaces the scaffold's), `test/helpers/database_test_utils.dart`, `test/data_store/local/database/isar_database_test.dart`, `test/ttl_data_provider/ttl_data_provider_test.dart` (Tests below). Dependencies: `isar_plus`, `isar_plus_flutter_libs`, `path_provider`; dev: `build_runner`, `crypto`.
- `coverage-exclusions.txt` gains `lib/src/data_store/local/database/isar_database/isar_database_web.dart`: the web-only alternative of a conditional import, never loaded by the VM run (the factory test covers the native pick).
- `data/lib/testing.dart` exports `DatabaseClient`, `DbRecord`, and `IsarDatabase` (by conditional export, so web gets the in-memory variant); `data.dart` exports `DatabaseClient` for the warm-up in `main`.
- `main` warms the database up after DI and before `runApp`, logged and never fatal:

  ```dart
  try {
    await getIt<DatabaseClient>().initialize();
  } catch (e, stackTrace) {
    log.e('Failed to open the database: $e', error: e, stackTrace: stackTrace);
  }
  ```

Later collections add their files and methods only:

```
data_store/local/database/
  database_client.dart                 # DatabaseClient contract — speaks DTOs
  db_record.dart                       # DbRecord<Dto>(dto, dbTimestamp)
  isar_database/
    isar_database.dart                 # IsarDatabase implements DatabaseClient (native)
    isar_database_web.dart             # same class name, in-memory maps (web)
    isar_database_factory.dart         # IsarDatabaseClientFactory: conditional import picks one
    models/{feature}/foo_db_model.dart # @collection / @embedded
ttl_data_provider/ttl_data_provider.dart # in-memory TTL layer in front of the database
```

## Db model

```dart
part 'foo_db_model.g.dart';

@collection
final class FooDbModel {
  FooDbModel({
    required this.fooId,
    required this.dbTimestamp,
    required this.name,
    required this.bars,
  });

  @id
  final String fooId;
  final DateTime dbTimestamp; // when the payload was saved; feeds the TTL
  final String name;
  final List<FooBarDbModel> bars;
}

@embedded
final class FooBarDbModel {
  FooBarDbModel({required this.barId, required this.rank});

  final String barId;
  final int? rank;
}
```

- Key by the business id (`fooId`, or a composite string key such as `'$fooId|$barId'` when the source keys by several values). A single-row collection uses a constant id (`static const dbId = …`).
- Nested data as `@embedded` objects, not separate collections, unless it is queried on its own. `@Index` only for fields the store filters on.
- Only types Isar stores (primitives, `DateTime`, enums with the package's enum annotation, lists, embedded objects). Map anything else in the DTO conversion. A stored `DateTime` comes back in **local time**: call `.toUtc()` when reading, so a round trip compares equal.
- Imports the DTO for its adapter (`fromDto` / `toDto`), never domain.

## Conversions (on the Db model)

The Db model is the database store's adapter: it converts to and from the shared DTO; the DTO does not know it exists (`data` rule).

```dart
// in FooDbModel
factory FooDbModel.fromDto(FooDto dto, {required DateTime dbTimestamp}) =>
    FooDbModel(
      fooId: dto.id,
      dbTimestamp: dbTimestamp,
      name: dto.name,
      bars: dto.bars.map(FooBarDbModel.fromDto).toList(),
    );

FooDto toDto() => FooDto(
  id: fooId,
  name: name,
  bars: bars.map((bar) => bar.toDto()).toList(),
);
```

- Storage-only context (timestamp, a partition key such as cached vs downloaded, the parent id, a locale) is a factory parameter; it never goes on the DTO.
- **Normalized storage** (a parent collection plus per-locale or per-child rows): each Db model converts its own part (`FooTranslationDbModel.fromDto(fooId: id, dto: translation, locale: l)`); the database implementation queries all parts, assembles with `parent.toDto(translation.toDto())`, and writes all parts in one transaction. Choose it when parts are read or replaced independently; store the whole payload as one document with `@embedded` children when it is always read and replaced together.

## DatabaseClient contract and Isar implementation

The templates hold `DbRecord`, `DatabaseClient` (`initialize`, `dispose`, `clearUserData`), and `IsarDatabase` (lazy shared open in Application Support, retry after a failed open, `clearUserData`, `dispose`). A collection adds its schema and one method pair:

```dart
// database_client.dart
Future<DbRecord<FooDto>?> fetchFoo({required String fooId});
Future<void> saveFoo(DbRecord<FooDto> record);

// isar_database.dart
static final _schemas = <IsarGeneratedSchema>[FooDbModelSchema];

@override
Future<DbRecord<FooDto>?> fetchFoo({required String fooId}) async {
  final isar = await _open();
  final model = await isar.fooDbModels.getAsync(fooId);
  if (model == null) return null;
  return DbRecord(dto: model.toDto(), dbTimestamp: model.dbTimestamp.toUtc()); // Isar returns local time
}

@override
Future<void> saveFoo(DbRecord<FooDto> record) async {
  final isar = await _open();
  await isar.writeAsync((db) {
    db.fooDbModels.put(
      FooDbModel.fromDto(record.dto, dbTimestamp: record.dbTimestamp),
    );
  });
}
```

- `DbRecord` only for cached remote payloads that need freshness; local-only state (sessions, settings) reads and saves the DTO directly.
- No work in the constructor. Every method awaits `_open()`, so the first access opens the database and concurrent first calls share one open; `initialize()` is the same call, for `main` to warm up and for harnesses. A failed open is not cached: the next access tries again.
- One write transaction per logical save; put a parent and its children in the same transaction.
- `clearUserData()` (one `writeAsync`) empties every collection that holds user data when the signed-in user changes; in an app that declares the offline queue it runs only with an empty queue and refuses otherwise (`queueing-offline-actions` → Requirements, 14–15) (`data` rule → Caching; `SessionRepositoryImpl` calls it); a collection of shared reference data may be kept by clearing the others one by one.
- `dispose(deleteFromDisk: true)` is for tests.

## Web

`isar_plus` can run on web (WASM, persisted in IndexedDB) once `await Isar.initialize()` has loaded its WASM assets. The kit default is still an **in-memory web variant**: `isar_database_web.dart` declares the same `IsarDatabase` class **with the same constructor** (`customDatabaseDirPath`, `customDatabaseName`, accepted and ignored, so harnesses build either one the same way) backed by maps of DTOs (`Map<String, DbRecord<FooDto>>`) and a broadcast controller for `observeFoo`, so web works offline within a session and refetches after a reload. Persist on web only when the web app needs data to survive a reload — a decision with an ADR (`recording-decisions`), verified on the web build. The factory picks the file by conditional import:

```dart
import 'package:data/src/data_store/local/database/database_client.dart';
import 'package:data/src/data_store/local/database/isar_database/isar_database.dart'
    if (dart.library.js_interop) 'package:data/src/data_store/local/database/isar_database/isar_database_web.dart';

abstract final class IsarDatabaseClientFactory {
  static DatabaseClient newClient() => IsarDatabase();
}
```

Every new `DatabaseClient` method is implemented in both files. Shared code never imports the Isar package outside these files. Test harnesses get the same pair through `package:data/testing.dart`, which exports `IsarDatabase` with the same conditional export.


## Database lifecycle

- `IsarDatabase implements DatabaseClient`, built by `IsarDatabaseClientFactory.newClient()` (the conditional import picks native or web).
- No side effects in the constructor. `initialize()` is idempotent, and every read and write awaits it, so the first access opens the database; `main` may call it early as a warm-up.
- Tests pass `customDatabaseName` / `customDatabaseDirPath` and call `dispose(deleteFromDisk: true)`.

## DI

`getIt.registerLazySingleton<DatabaseClient>(IsarDatabaseClientFactory.newClient, dispose: (database) => database.dispose())` in `injectDataLayer` (the contract has `dispose`); repositories receive `DatabaseClient`, never `IsarDatabase` (`di` rule).


## Cache policies

One `enum CachePolicy { cache, network, networkIfNotCached, refresh }` per app, in domain (`domain/lib/src/common/model/cache_policy.dart`). Repositories that cache take it on reads:

| Policy | Reads | Use |
| --- | --- | --- |
| `cache` | local only (in-memory, then database); nothing stored → the app's not-found domain exception | a load bloc's first paint |
| `network` | the network, unless the in-memory TTL record is still fresh | automatic refresh: `reload()` after the cache paint, background polls |
| `refresh` | always the network (concurrent calls still shared) | the user asked: pull-to-refresh |
| `networkIfNotCached` | the local copy if any, even stale; otherwise the network | a value that only must exist (a sibling's lookup, startup) |

- An in-memory TTL provider (`TtlDataProvider`) sits in front of the database: per-key records with their timestamp, in-flight de-duplication of concurrent requests, a TTL per repository (seconds for live data, longer for static data). A record read from the database carries its `dbTimestamp`, which feeds the TTL.
- A network result is saved with `DbRecord(dto: dto, dbTimestamp: now)` before mapping `dto.toDomain()`.
- **Cached data belongs to one user.** When the signed-in user id changes (sign-out, account switch, deletion), user-scoped database collections and every TTL provider are cleared before the next user's first read — each store reacting to the auth service's user-id stream itself, so no repository calls another. A flow test signs in as a second user and sees none of the first user's data.
- Online-only writes go to the network first and update the local copy from the server response, not from the request. Offline-capable writes go through the action queue: optimistic in the local store, confirmed or rolled back by the server (`queueing-offline-actions` → Policy).
- Paged lists cache only the first page; later pages are network-only and never persisted, and the policy applies to page one only (`paging-lists`).

## Repository with cache

The TTL provider (`templates/modules/data/lib/src/ttl_data_provider/ttl_data_provider.dart`, with its tests) implements the `CachePolicy` semantics (`data` rule → Caching): the in-memory record (from the network or from the database with its `dbTimestamp`) answers `cache` and `networkIfNotCached`, and answers `network` while younger than the TTL; concurrent network requests for one key share one call; `clear()` forgets everything, including a response still in flight.

```dart
final class FooRepositoryImpl implements FooRepository, Disposable {
  FooRepositoryImpl(this._apiClient, this._database, AuthService authService) {
    // Cached data belongs to one user (`data` rule → Caching).
    _userChanges = authService.userIdChanges.distinct().listen(
      (_) => _foos.clear(),
    );
  }

  final BackendApiClient _apiClient;
  final DatabaseClient _database;
  final _foos = TtlDataProvider<Foo>(ttl: const Duration(minutes: 5));
  late final StreamSubscription<String?> _userChanges;

  @override
  Future<void> dispose() => _userChanges.cancel();

  @override
  Future<Foo> fetchFoo({
    required String fooId,
    required CachePolicy cachePolicy,
  }) => withAppExceptions(
    () => _foos.fetch(
      key: fooId,
      cachePolicy: cachePolicy,
      fetchFromDatabase: () => _database.fetchFoo(fooId: fooId),
      fetchFromNetwork: () => _apiClient.getFoo(fooId: fooId),
      saveToDatabase: _database.saveFoo,
      toDomain: (dto) => dto.toDomain(),
    ),
  );
}
```

- `NotFoundException` is the app's not-found domain exception; `withAppExceptions` is the repository error guard (`handling-errors`).
- TTL per repository: seconds for data that changes live, minutes or hours for reference data. A write that changes the entity calls `evict(key:)` or saves the server's copy through the same provider.
- Reuse the project's provider if it has one; do not hand-write the policy switch in each repository. A failed network call is never cached, the next call retries.
- Register the repository with `dispose: disposeIfDisposable` (`di` rule).
- Paged lists cache the first page per filter key: `paging-lists`.

## Schema changes

Ask first (persistence schema is a working-agreement "ask first" item). Isar adds and drops fields and collections on its own; a changed field type, a changed id, or reinterpreted data does not migrate. Pick one, as the project does:

- **Cache only** (everything can be re-fetched): bump a cache version kept in a sidecar file next to the database; `_openIsar()` compares it before `Isar.openAsync` and deletes the database files on a mismatch. Test it with a database written under the old version.
- **Holds user data** (offline downloads, drafts): a migration step at startup that reads the old shape and writes the new one, tested with a database created by the old version.

Never ship a type change without one of these. A database that holds the offline action queue never takes the cache-only reset (`queueing-offline-actions` → Requirements, 17).

## Tests

`flutter test` runs on the host VM, where `isar_plus_flutter_libs` provides no native core. The store's test files are templates next to this skill:

- `test/flutter_test_config.dart` **replaces** the scaffold's. Order: the logger; `initializeTestIsarCore()` **first**, because a cold `build/test` downloads the core and both `TestWidgetsFlutterBinding` (its own `HttpOverrides`, answering 400 to everything) and the network block would kill that download; then `TestWidgetsFlutterBinding.ensureInitialized()`, which installs its overrides once; then `HttpOverrides.global = _NoNetwork()` last, so it is the block every test sees.
- `test/helpers/database_test_utils.dart`: `initializeTestIsarCore()` (memoized: a later call never downloads), `testDatabase()` (a unique database under `build/test/database`), and the core loader. It downloads the host asset for the pinned `Isar.version` once into `build/test/isar/<version>/` (a file lock, so parallel test isolates download once), checks its **SHA-256 against the pin** before renaming the temp file into place, and fails on a mismatch or on an unpinned `isar_plus` version. Bumping `isar_plus` updates `_pinnedVersion` and the hashes (`sha256sum` of the release assets). Linux and Windows assets are x64; an arm64 runner needs its own asset and hash. Dev dependency: `crypto`.
- `test/data_store/local/database/isar_database_test.dart`: the lifecycle (idempotent `initialize`, `clearUserData`, dispose twice, access after dispose, a failed open retried, dispose during a failing open) and the factory on the VM. It needs at least one collection in `_schemas`, which is why the store arrives with the first collection.

```dart
// test/flutter_test_config.dart (the template, abridged)
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await initializeLogger();
  await initializeTestIsarCore();               // 1. may download
  TestWidgetsFlutterBinding.ensureInitialized(); // 2. installs its overrides once
  HttpOverrides.global = _NoNetwork();          // 3. the block every test sees
  await testMain();
}
```

CI needs network on the first run (or a cached `build/test/isar`). Projects on `isar_community` call that package's core initializer the same way.
- Round-trips against the real `IsarDatabase` from `testDatabase()`; `dispose(deleteFromDisk: true)` in `tearDown`.
- Per DTO: save → fetch equals the input; nested lists and embedded objects; null optionals; empty lists; a missing id returns `null`; a second save replaces the first.
- Repository: each cache policy (cache hit, cache miss → `NotFoundException`, network saves with a timestamp, `network` within the TTL makes no call, `refresh` always calls, concurrent calls make one) and a user change clearing the provider, with a mocked API client and the real test database.
- Patrol uses a real per-test database in the harness (`writing-patrol-tests`).

## Checks

- [ ] Db model has the id, `dbTimestamp` when cached, embedded children; added to `_schemas`; generator re-run
- [ ] Conversions on the Db model (`fromDto` / `toDto`); the DTO imports no Db model; storage keys only on the Db model
- [ ] `DatabaseClient` method implemented natively and on web; no constructor side effects; every method awaits `_open()`
- [ ] Repository reads through the TTL provider and maps `dto.toDomain()`; no Db or Api model outside its store
- [ ] Schema change handled (version reset or migration), user asked
- [ ] User data cleared on a user change (`clearUserData` covers the new collection; the repository clears its TTL provider)
- [ ] Round-trip tests added
