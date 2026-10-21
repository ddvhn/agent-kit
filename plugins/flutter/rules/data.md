---
description: Flutter data layer — data stores (one API client per remote source, generated from the contract when there is one; the local database behind DatabaseClient), their private models, the shared DTO, core services, cache policy, repositories and error mapping
paths:
  - "**/*.dart"
---

# Data layer

Data **stores** talk to one source each; **repositories** combine them and return domain models. Layout, model kinds, and services in detail: `creating-flutter-repositories`; the database and cache: `persisting-with-isar`; callables: `calling-cloud-functions`; OpenAPI clients: `generating-api-clients`.

## Stores and models

- One API client per remote source (or per API area of a large backend), one method per endpoint named like it; one database client per engine (`DatabaseClient`). Contract-first: a published OpenAPI contract is generated into its own package and wrapped by the client (`generating-api-clients`).
- Three model kinds: `FooApiModel` (the wire, that store only), `FooDbModel` (the stored record, that store only), `FooDto` (the data layer's shared shape). Store contracts speak DTOs; Api and Db models never leave their store.
- **Each store converts its own models**; the DTO imports nothing from any store and converts only to and from domain (`dto.toDomain()`, `FooDto.fromDomain(foo)`). A project that keeps conversions on the DTO keeps that convention consistently.
- A DTO keeps enum values and instants as the server sent them; `toDomain()` parses them, with an `unknown` enum case.
- Repositories reach the database only through `DatabaseClient` methods; no engine types (collections, transactions) outside the database store.
- SDK and device integrations are data-internal services (`FooService`, implementations named by provider), chosen once at registration.

## Caching

- One `CachePolicy` enum in domain (`cache`, `network`, `networkIfNotCached`, `refresh`); caching reads take it, with an in-memory TTL provider in front of the database that also shares concurrent requests (semantics: `persisting-with-isar` → Cache policies).
- A network result is saved before it is mapped to domain. Signed media URLs are never persisted or logged. Cached data belongs to one user: a user change clears user-scoped collections before the next user's first read.
- Online writes go to the network and update the local copy from the response; queued writes exist only where the project declared them (`architecture` rule → Offline and sync). Paged lists cache only page one.

## Repositories

- Map store errors to sealed domain exceptions by code, never by message, never raw to blocs.
- No JSON outside Api models; a new field travels through every layer it needs.
- A persisted schema change is an "ask first" item (`persisting-with-isar` → Schema changes).
