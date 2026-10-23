---
name: calling-cloud-functions
description: Add or change Firebase callable clients (API client method, wire model, DTO) in a Flutter app. Use when wiring a new Cloud Function, changing request/response JSON, region, or pagination.
---

# Calling Cloud Functions

For projects whose Flutter app **consumes** Firebase callables (it does not deploy them). Stores, models, and the one API client per remote source: the stack `data` rule. Backend compatibility: the stack `architecture` rule → Client API compatibility (when to ask: the working agreement). The backend repo and other clients: `CLAUDE.md` → Related repositories. The project's client class, helpers, regions, file paths, and canonical example: the repository's `.claude/rules/`. The scaffolded app has no API layer. The first endpoint brings it from `templates/` next to this skill (laid out as in the app): `modules/data/build.yaml` (`json_serializable` with `checked: true`, `explicit_to_json: true`, `field_rename` matching the backend), `src/data_store/remote/api/utils/` (`ApiException` + codes, `sendApiRequest`, `jsonObject`) with their tests in `test/data_store/remote/api/utils/`, `src/data_store/remote/api/backend/client/` (`BackendApiClient`, `FirebaseBackendApiClient` with the `callJson` helper: region from DI, a 70 s timeout — longer than the backend's default function timeout, the HttpsError code table), and the repository guard `src/repository/utils/with_app_exceptions.dart` (`handling-errors`). Dependencies in data: `firebase_core`, `cloud_functions`, `json_annotation`; dev: `build_runner`, `json_serializable`. `data/lib/testing.dart` exports `BackendApiClient` and `ApiException`.

First-endpoint wiring in `injectDataLayer` (Firebase itself: `configuring-flutter-flavors` → Firebase and crash reporting):

```dart
/// The backend's callable region (its project config).
const backendRegion = 'us-central1';

Future<void> injectDataLayer(
  GetIt getIt, {
  required AppConfig config,
  bool skipSdkInit = false, // harnesses register doubles instead
}) async {
  getIt.registerSingleton(config);
  if (!skipSdkInit) {
    final functions = FirebaseFunctions.instanceFor(region: backendRegion);
    if (config.useEmulators) {
      functions.useFunctionsEmulator(config.emulatorHost, 5001); // backend firebase.json
    }
    getIt.registerSingleton(functions);
  }
  getIt.registerLazySingleton<BackendApiClient>(
    () => FirebaseBackendApiClient(getIt()),
  );
  // …repositories
}
```

## Workflow

1. Confirm the exact callable name, region, and payload in the backend (or an existing neighbor); before the callable exists, in the merged contract schemas and fixtures (`core:shipping-feature-branch` → Backend and client).
2. Add one method for the endpoint to the backend's API client contract (`abstract interface class BackendApiClient`, or the project's name for it) — not a new client per feature. The method is named exactly like the callable (`getFoo`, `listFoos`, `setFooFavorite`); the repository uses the domain verb (`fetchFoo`) — table in `creating-flutter-repositories`.
3. Add the wire model (`FooApiModel`, `json_serializable` with `fromJson` / `toJson`) next to its neighbors. JSON keys are camelCase on both sides (`field_rename: none`); backend enums get `@JsonKey(unknownEnumValue: …)`.
4. Add or extend the DTO and the Api model's adapter (`FooApiModel.toDto()`, request models `FooRequestApiModel.fromDto`; `data` rule): the client method returns `FooApiModel.fromJson(json).toDto()`; the Api model never leaves the client.
5. Implement the method on the Firebase implementation (`FirebaseBackendApiClient implements BackendApiClient`, or the project's) through its existing call helper (region, timeout, mapping `FirebaseFunctionsException` to `ApiException`). Parse the result through the project's JSON helper — on web, callable results are JS maps, not `Map<String, dynamic>`. Paged lists follow the cross-stack paged contract: request `{cursor?: string, limit: number}` (limit 1–50, default 20), response `{items: [...], nextCursor: string | null}`; the cursor is opaque to the client (`FooPageApiModel` → `FooPageDto`; `paging-lists`).
6. If an API-client test double exists, implement the same method there.
7. Map `dto.toDomain()` and `ApiException` → domain exceptions in the repository (`creating-flutter-repositories`). Re-run code generation if wire models changed.
8. Analyze.

## Constraints

- Regions: the one `FirebaseFunctions.instanceFor(region: …)` registered in DI, matching the backend's deploy region; do not guess a new one.
- Parse with the JSON helper / `FooApiModel.fromJson`; never test `data is Map<String, dynamic>`. `FirebaseFunctionsException` becomes the store's `ApiException` in one place (the call helper's code table, which covers every HttpsError code including `resource-exhausted`; `handling-errors`).
- Do not call callables from `ui`. Keep the timeout the call helper sets unless a neighbor uses a different value; it stays longer than the function's `timeoutSeconds`, or a retry can duplicate a write the backend still commits.
- Localhost: `AppConfig.useEmulators` / `emulatorHost` (`configuring-flutter-flavors` → appFlavor and dart-defines) from a `dev-local` launch config and `.dart_defines.local.json`; `injectDataLayer` points `FirebaseFunctions` (5001) and, with auth, `FirebaseAuth` (9099, `adding-flutter-auth`) at them — ports as in the backend's `firebase.json`. Never hardcode production project URLs in tests.

## Checklist

- [ ] Callable name/region match backend
- [ ] Client contract + Firebase implementation in sync (and test double if it exists)
- [ ] Wire model generated; DTO exported; mapped to domain in data
- [ ] Responses go through the JSON helper
- [ ] Breaking changes approved or additive-only
- [ ] Analyze clean for touched files
