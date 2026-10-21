---
name: adding-flutter-auth
description: Add sign-in to a kit Flutter app — the AuthService over Firebase Auth, the Session model and SessionRepository, ObserveSessionUseCase and the app-wide ObserveSessionBloc, the router's auth redirect with deep-link return, the web restore wait, clearing the previous user's cached data on a user change, emulator wiring, and the tests. Use when the app gets its first signed-in screen, a sign-in or sign-out flow, an auth gate on routes, or when one user's data shows to another.
---

# Adding auth

Policy: core `same-level-dependencies`; the stack `architecture`, `data` (→ Caching: cached data belongs to one user), `di`, and `dart` rules. Routes: `adding-flutter-routes`; the sign-in flow's screens and blocs: `writing-action-blocs`; errors: `handling-errors`. The provider here is Firebase Auth; another provider replaces `FirebaseAuthService` only.

**Ask first**: sign-in methods (email link, Apple, Google, anonymous), which routes stay public, and what a signed-out deep link does [return to it after sign-in].

## Files

`templates/` next to this skill, laid out as in the app:

| Layer | Files |
| --- | --- |
| domain | `src/session/model/session.dart` (`Session`: `SessionSignedOut` / `SessionSignedIn(userId)`, value equality), `src/session/repository/session_repository.dart`, `src/session/usecase/observe_session_use_case.dart` (stream + synchronous `current`) |
| data | `src/session/auth_service.dart` (data-internal contract), `src/session/firebase_auth_service.dart`, `src/repository/session_repository_impl.dart` |
| ui | `src/session/blocs/observe_session_bloc.dart`, `src/session/pages/sign_in_page.dart` (placeholder) |
| tests | `domain/test/session/…/observe_session_use_case_test.dart`, `data/test/repository/session_repository_impl_test.dart` |

Exports: `Session` in `domain_model.dart`, `SessionRepository` in `domain_repository.dart`, `ObserveSessionUseCase` (`hide ObserveSessionUseCaseImpl`) in `domain_usecase.dart`; `AuthService` in `data/testing.dart` for harnesses. Copy: a `signIn` key in `app_en.arb`. `signOut` runs through the repository guard `withAppExceptions` (`calling-cloud-functions` templates; copy it if the app has none yet). Dependencies: `firebase_core`, `firebase_auth`, and `rxdart` in data (and a Firebase app per flavor: `configuring-flutter-flavors`).

## Wiring

```dart
// data/lib/src/di.dart — SDK setup, skipped by test harnesses
Future<void> injectDataLayer(
  GetIt getIt, {
  required AppConfig config,
  bool skipSdkInit = false,
}) async {
  getIt.registerSingleton(config);
  if (!skipSdkInit) await _registerFirebase(getIt, config);
  getIt
    ..registerLazySingleton<AuthService>(() => FirebaseAuthService(getIt()))
    ..registerLazySingleton<SessionRepository>(
      () => SessionRepositoryImpl(getIt(), getIt()),
      dispose: disposeIfDisposable,
    );
}

Future<void> _registerFirebase(GetIt getIt, AppConfig config) async {
  final auth = FirebaseAuth.instance;
  if (config.useEmulators) {
    await auth.useAuthEmulator(config.emulatorHost, 9099); // backend firebase.json
  }
  // Web restores the signed-in user asynchronously; until then currentUser is
  // null and the first frame would send a signed-in user to sign-in.
  if (UniversalPlatform.isWeb) await auth.authStateChanges().first;
  getIt.registerSingleton(auth);
}

// domain/lib/src/di.dart
getIt.registerFactory<ObserveSessionUseCase>(
  () => ObserveSessionUseCaseImpl(getIt()),
);

// ui/lib/src/di.dart
getIt.registerFactory(() => ObserveSessionBloc(getIt()));
```

- `main` calls `Firebase.initializeApp()` after the config (`configuring-flutter-flavors` → Firebase and crash reporting). `useEmulators` / `emulatorHost` are `AppConfig` switches (`configuring-flutter-flavors` → appFlavor and dart-defines).
- The session is app-wide: `Application` wraps `MaterialApp.router` in `MultiBlocProvider(providers: [BlocProvider<ObserveSessionBloc>(create: (_) => inject())])` and a `BlocListener<ObserveSessionBloc, ObserveSessionBlocState>` that calls `_router.refresh()`.

## Redirect

One global `redirect` on the `GoRouter`, exhaustive over the session bloc's sealed states, never to the current location:

```dart
GoRouter createRouter() => GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: const HomeRoute().location,
  routes: $appRoutes,
  redirect: _redirect,
  errorBuilder: (context, state) => const _NotFoundPage(),
);

/// A signed-out deep link goes through sign-in and comes back.
String? _redirect(BuildContext context, GoRouterState state) {
  final atSignIn = state.matchedLocation == const SignInRoute().location;
  return switch (context.read<ObserveSessionBloc>().state) {
    ObserveSessionBlocStateSignedOut() =>
      atSignIn ? null : SignInRoute(from: state.uri.toString()).location,
    ObserveSessionBlocStateSignedIn() =>
      atSignIn ? _inAppLocation(state.uri.queryParameters['from']) : null,
  };
}

/// Only a path inside this app, never another origin (`//host`, `https:`).
String _inAppLocation(String? from) =>
    from != null && from.startsWith('/') && !from.startsWith('//')
    ? from
    : const HomeRoute().location;

@TypedGoRoute<SignInRoute>(path: '/sign-in', name: 'SignIn')
@immutable
class SignInRoute extends GoRouteData with $SignInRoute {
  const SignInRoute({this.from});

  /// Where to go after sign-in (a query parameter).
  final String? from;

  @override
  Widget build(BuildContext context, GoRouterState state) => const SignInPage();
}
```

Public routes (onboarding, legal pages) get a case in the same redirect; pages never check auth to bounce the user themselves.

## User change

Cached data belongs to one user (`data` rule → Caching). `SessionRepositoryImpl` clears the database's user data (`DatabaseClient.clearUserData()`, `persisting-with-isar`) before it publishes the next session; each caching repository clears its own TTL provider from `AuthService.userIdChanges`. An app without a local database drops the `DatabaseClient` parameter. Sign-out is `SessionRepository.signOut()`; the redirect does the navigation.

**Apps with the offline queue** (`queueing-offline-actions` → Requirements, 14–16): the queue has one owner. Sign-out goes through the queue's flush-or-ask first. On a forced sign-out (a refused refresh) with items queued, the expected `QueueNotEmptyException` from `clearUserData` is caught by type and logged at info level, and the data stays; any other failure stays `log.e`. The sign-in page reads the queue owner before calling the provider and offers only "sign in as <owner> to send N items" or "delete N items" (which deletes the items, then clears the user data); if another user's id still arrives from the provider, `SessionRepositoryImpl` signs it out and does not publish that session. Tests: another user is refused while items are queued; a forced sign-out keeps the items and pending rows; after "delete N items" the next user sees no earlier data, also after a restart.

## Tests

- Use case: `current` and the stream pass through (template).
- Session repository: starts with the auth user; the same user again changes nothing; sign-out and another user clear user data before the new session is published (template — remove the clear and it fails).
- Router: a signed-out deep link lands on sign-in and returns after sign-in; a signed-in user at `/sign-in` goes to Home; `from` pointing elsewhere (`//evil.example`) goes to Home.
- Patrol (`writing-patrol-tests`): sign in, sign out, sign in as a second user — none of the first user's data shows.

## Checks

- [ ] `AuthService` stays in data; ui sees only `Session` through the use case and the bloc
- [ ] Apps with the offline queue: no other user signs in while items are queued; "delete N items" deletes and clears in one transaction
- [ ] One app-wide `ObserveSessionBloc`; the router refreshes on its changes; the redirect is exhaustive and loop-free
- [ ] Web waits for the restored user before the first frame
- [ ] User data cleared on a user change (database and TTL providers)
- [ ] Emulator wiring only through `AppConfig`; the harness skips SDK setup (`skipSdkInit`) and replaces `AuthService`
