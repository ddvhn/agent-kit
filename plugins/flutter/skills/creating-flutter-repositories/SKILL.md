---
name: creating-flutter-repositories
description: >-
  Create or extend Flutter repositories: contract in domain, implementation in
  data (FooRepository / FooRepositoryImpl), transport-error mapping to domain
  exceptions, DTO mapping, DI registration. Use when adding a repository, CRUD
  methods, or local database wrappers.
---

# Creating repositories

Policy: the stack `data` rule (stores, DTOs, caching, error mapping) and `architecture` rule → Use cases. The error guard (`withAppExceptions`): `handling-errors`; the cache provider and `CachePolicy`: `persisting-with-isar`; the project's own names, DI entry points, and barrel files: the repository's `.claude/rules/`. Callables: [calling-cloud-functions](../calling-cloud-functions/SKILL.md). Local cache: [persisting-with-isar](../persisting-with-isar/SKILL.md). Tests: [testing-flutter-apps](../testing-flutter-apps/SKILL.md).

Do not invent parallel shapes. A repository method that carries a business rule, or is combined with another repository, gets a use case (`modeling-domain`) in the same change; a plain CRUD call may be injected into the bloc directly. Do not mass-refactor neighbors unless asked.

## Workflow

1. Read the closest neighbor repository (API-backed, and API + local DB if relevant) and its mappings.
2. Confirm the API client of that remote source (`BackendApiClient`, one per source) or the database client already has the methods. If not, add them first (`calling-cloud-functions`, `persisting-with-isar`).
3. Add the contract `foo_repository.dart` and the model `foo.dart` in domain under the feature folder; add `foo_repository_impl.dart` in data.
4. Map in data (`dto.toDomain()`, `FooDto.fromDomain`). Map transport and store exceptions to the app's sealed domain exceptions in the project's error-mapping helper (`architecture` rule → Errors). Domain models do not import DTOs.
5. Export the contract and model through the domain barrels. Register `FooRepositoryImpl` as `FooRepository` in `injectDataLayer`. Platform-specific repositories go on their platform's DI branch.
6. If the API client changed and a test double exists, update it.
7. Tests first where the repository has logic (caching, mapping, error mapping): a round-trip against the real test database with the API client mocked (`testing` rule).
8. Analyze.

## Shape

```dart
// domain
abstract interface class FooRepository {
  Future<Foo> fetchFoo({required String fooId});
  Future<Foo> updateFoo({required Foo foo});
}

// data
final class FooRepositoryImpl implements FooRepository {
  FooRepositoryImpl(this._apiClient);

  final BackendApiClient _apiClient;

  @override
  Future<Foo> fetchFoo({required String fooId}) => withAppExceptions(() async {
    final dto = await _apiClient.getFoo(fooId: fooId);
    return dto.toDomain();
  });

  @override
  Future<Foo> updateFoo({required Foo foo}) => withAppExceptions(() async {
    final dto = await _apiClient.updateFoo(foo: FooDto.fromDomain(foo));
    return dto.toDomain(); // the server's copy, not the request
  });
}
```

- `withAppExceptions` is the repository error guard (`handling-errors`): it maps `ApiException` codes to the matching domain exception (`NetworkUnavailableException`, `NotFoundException`) and anything else to `UnknownException`, so blocs never see transport errors.
- Contract `abstract interface class` in domain, `final class … implements` in data (`dart` rule).
- Domain models only on the contract — no wire models, no widgets, no DTOs.
- A read that caches takes `CachePolicy` and goes through the TTL provider (`data` rule → Caching; template in `persisting-with-isar`).
- Live updates only where the feature needs them (`observing-data`), named as in the table below. The controller stays on the impl.
- A repository that owns a controller, subject, or subscription implements the data-internal `Disposable` (`data/lib/src/core/disposable.dart`) and is registered by its contract with `dispose: disposeIfDisposable` — a capability check, the one allowed type test; no cast to the implementation:

  ```dart
  getIt.registerLazySingleton<FooRepository>(
    () => FooRepositoryImpl(getIt(), getIt()),
    dispose: disposeIfDisposable,
  );
  ```

Local-only data (settings, a session): the impl injects `DatabaseClient` and skips network error mapping.


## Data layout

```
data/lib/src/
  data_store/
    dto/{feature}/foo_dto.dart                          # FooDto — shared by every store
    remote/api/{source}/client/{source}_api_client.dart # BackendApiClient contract (+ _impl)
    remote/api/{source}/models/{feature}/foo_api_model.dart
    remote/api/utils/                                   # JSON helpers, ApiException
    local/database/database_client.dart                 # DatabaseClient contract
    local/database/db_record.dart                       # DbRecord<Dto>(dto, dbTimestamp)
    local/database/isar_database/                       # IsarDatabase (+ _web), factory, models/{feature}/
  {service}/                                            # core services (below)
  ttl_data_provider/                                    # in-memory TTL layer (Caching)
  repository/foo_repository_impl.dart
  di.dart
```

**One API client per remote source** (`{source}`: the app backend, a store API, a third-party API): `BackendApiClient`, `StoreApiClient`, with one method per endpoint, named exactly like it (`getFoo`, `listFoos`, `updateFoo`) — never one client per feature (a large backend may split by API area: `FooApiClient`, `BarApiClient`). One database client per engine.

**Contract-first:** when the backend publishes an OpenAPI contract, the low-level client and the Api models are generated from it into its own workspace package, `modules/generated_api`, that only data depends on (never edited by hand, regenerated in the change that needs a new field). The app's `abstract interface class BackendApiClient` wraps the generated client; its impl maps generated models to DTOs, adds headers (auth, idempotency key, tenant), and turns error responses into `ApiException(code, serverCode: …)` (`handling-errors`). Generated types never leave the impl (`generating-api-clients`).

## Model kinds

| Model | Lives in | Shape | Seen by |
| --- | --- | --- | --- |
| `FooApiModel` | its remote store | the wire JSON (`json_serializable`, `@JsonKey` to match the backend) | that store only |
| `FooDbModel` | its database store | the stored record (engine annotations, id, `dbTimestamp`) | that store only |
| `FooDto` | `data_store/dto/` | the data layer's common shape, independent of any source | stores and repositories |

- **Store contracts speak DTOs.** `BackendApiClient.getFoo()` returns `FooDto`; `DatabaseClient.fetchFoo()` returns `DbRecord<FooDto>?` and `saveFoo(DbRecord<FooDto>)` takes one. Api and Db models never leave their store.
- **Each store converts its own models** (adapters). The DTO is the hub and imports nothing from any store; it converts only to and from domain (`dto.toDomain()`, `FooDto.fromDomain(foo)`). Dependencies point inward: Api model → DTO ← Db model, DTO → domain.
  - Remote: `FooApiModel.fromJson(json).toDto()` inside the client; requests `FooRequestApiModel.fromDto(dto)` (or from plain params).
  - Database: `FooDbModel.fromDto(dto, dbTimestamp: t)` and `model.toDto()`. Storage-only context (timestamps, a partition key, the parent id, a locale split) is a Db-model factory parameter, never a DTO field.
  - Normalized storage (one DTO kept in several collections): the database implementation reads every part, assembles the DTO, and writes every part in one transaction.
- Why not on the DTO: a DTO that converts to every store model imports every store, so swapping the engine or adding a source changes the shared DTO. An existing project that keeps conversions on the DTO keeps its convention consistently (repository rules); do not mix directions within one store or migrate without asking.
- A DTO keeps enum values (and instants) as the server sent them, raw strings, so an unknown value survives a database round trip; `toDomain()` parses them into the domain enum with its `unknown` case and into UTC instants (parse, don't validate).
- DTOs are `final class` with value equality; nested parts get their own DTOs (`FooBarDto`). A field the domain needs that one source lacks is nullable on the DTO and filled by the repository, not faked in the store.

## Core services

SDK and device integrations (auth, push, in-app purchases, location, playback, preferences, analytics transport) are **services** in `data/lib/src/{service}/`: a contract `abstract interface class FooService` and implementations named by provider — `FcmFooService`, `RevenueCatFooService`, `InMemoryFooService` (web, tests, non-prod), never `ProdFooService`. Picked once at DI registration (`di` rule). Only repositories use them. A platform variant is chosen by a factory (conditional import, `universal_platform`) at registration, never by checks at call sites.

## Naming

| Kind | Repository (domain verbs) | API client (mirrors the callable) |
| --- | --- | --- |
| Single read | `fetchFoo({fooId, cachePolicy})` | `getFoo` |
| Lists, paged | `fetchFoos({cursor, limit, cachePolicy})`, `fetchMyFoos` | `listFoos`, `listMyFoos` |
| Write | `createFoo` / `updateFoo` / `deleteFoo` | the callable's name (`createFoo`, `setFooFavorite`) |
| Local save | `saveFoo` | — |
| Current value + changes | `Foo get foo` + `Stream<Foo> observeFoo()` | — |
| Stored entity, live | `Stream<Foo?> observeFoo({required String fooId})` | — |
| Change signal after confirmed writes | `Stream<void> get fooUpdates` | — |

- The API client method is named exactly like the backend callable (`getFoo`); repositories and use cases use the domain verb (`fetchFoo`). Never rename a callable on the client side.
- Named parameters everywhere, DTOs included (`updateFoo(foo: dto)`). Ids: `{entity}Id` (`fooId`, `barId`).
- Domain types on the contract (`Locale`, enums); convert to wire values in data.
- The project's own naming wins (repository rules).

## Layer boundaries

- No `ui` imports, no wire models, no UI policy, no business rules in the repository (I/O + mapping only).
- Peers: core `same-level-dependencies` — shared I/O moves down into a data store, a sequence moves up into a use case.
- SDKs (`FirebaseFunctions`, HTTP) only inside data stores and services; nobody outside data calls an API client.

## Anti-patterns

- Mapping JSON in domain (that is `data`).
- Skipping the error-mapping helper so SDK exceptions leak into blocs.
- Putting `fromJson` on a DTO when the project parses into wire models first.
- One API client per feature instead of per remote source.
- Forgetting DI registration and barrel exports.
- A widget calling the API client — that is the owning bloc's job, through a use case or the repository.
