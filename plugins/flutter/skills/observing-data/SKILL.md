---
name: observing-data
description: Keep Flutter screens in sync with data that changes elsewhere, the kit way — repository streams (a seeded BehaviorSubject for app-wide values, a broadcast update stream for entities, a database watch for offline-first data), observing use cases whose call() returns a Stream and that expose current, combining streams in domain, ObserveFooBloc with a subscription cancelled in close, how observe blocs sit next to load and action blocs, and tests with emitsInOrder and through the screen's widget tests. Use when a value is shown on several screens (session, settings, entitlement, a counter), when a screen must update after a change made on another screen or in the background, or when adding a stream to a repository.
---

# Observing data

Policy: core `same-level-dependencies` (a repository stream both blocs observe through their own use cases — never bloc → bloc) and `architecture-principles` (offline-first: the database is the source of truth); the stack `architecture` rule (observing use cases), `blocs` rule, and `data` rule. One-shot loads: `writing-load-blocs`; writes that trigger updates: `writing-action-blocs`.

## Pick the source

| Data | Repository exposes | Use case | Bloc |
| --- | --- | --- | --- |
| App-wide value read synchronously (session, settings, entitlement, locale, unread count) | `Foo get foo` + `Stream<Foo> observeFoo()` (seeded `BehaviorSubject`) | `ObserveFooUseCase`: `call()` → `Stream<Foo>`, `current` | `ObserveFooBloc`, initial state from `current` |
| Entity loaded by id and changed by writes in the app | `Stream<void> get fooUpdates` (broadcast; fires after the backend confirmed a write and the local copy was saved) | an observing use case over the signal, or the contract directly for plain CRUD | the existing `LoadFooBloc` re-reads silently (`writing-load-blocs`, external triggers) |
| Offline-first entity or list that background sync or several writers change | `Stream<Foo?> observeFoo({required String fooId})` from the database store | `ObserveFooUseCase` with params, no `current` | `ObserveFooBloc` with `configure(fooId:)` |

Do not mirror database or repository state in a bloc field; the stream is the source and the bloc maps it to UI models. Names follow the table in `creating-flutter-repositories` (`observeFoo`, `fooUpdates`).

## Repository streams (data)

App-wide value: a seeded subject (`BehaviorSubject.seeded(...)`), so new listeners get the current value immediately and `current` is synchronous; the implementation subscribes to its source in the constructor, cancels in `dispose()` (`Disposable`, registered with `dispose: disposeIfDisposable`), and exposes `observeFoo()` as `_subject.stream.distinct()` over a model with value equality. Worked example: `SessionRepositoryImpl` in `adding-flutter-auth` → `templates/`.

Entity updates: a broadcast `Stream<void>` signal on the implementation, fired only after a confirmed backend response was saved locally; listeners re-read what they show:

```dart
final _updates = StreamController<void>.broadcast();

@override
Stream<void> get fooUpdates => _updates.stream;

/// Network first; the local copy and the caches from the server's
/// response; then the update signal.
Future<Foo> _write(Future<FooDto> Function() call) =>
    withAppExceptions(() async {
      final dto = await call();
      await _database.saveFoo(
        DbRecord(dto: dto, dbTimestamp: DateTime.now()),
      );
      _foos.evict(key: dto.id);
      _updates.add(null);
      return dto.toDomain();
    });

@override
Future<void> dispose() => _updates.close(); // FooRepositoryImpl is Disposable
```

Database watch (offline-first): the database store exposes a watch that emits the stored value immediately and after every save; the network refresh just saves, and every observer updates.

```dart
// DatabaseClient (contract speaks DTOs)
Stream<FooDto?> observeFoo({required String fooId});

// IsarDatabase
@override
Stream<FooDto?> observeFoo({required String fooId}) async* {
  final isar = await _open();
  yield* isar.fooDbModels
      .watchObject(fooId, fireImmediately: true)
      .map((model) => model?.toDto());
}

// FooRepositoryImpl
@override
Stream<Foo?> observeFoo({required String fooId}) =>
    _database.observeFoo(fooId: fooId).map((dto) => dto?.toDomain());
```

- `isar_plus` watchers: `watchObject(id, fireImmediately: true)`, `watchLazy()` on a collection or query. The in-memory web variant emits from its own broadcast controller on every save (`persisting-with-isar`).
- Subjects and controllers are private to the implementation. A repository that owns one implements the data-internal `Disposable` and is registered with `dispose: disposeIfDisposable` (`creating-flutter-repositories`, stack `di` rule). Streams never error for expected failures: a failed refresh is reported by whoever triggered it, not pushed into the stream.

## Observing use cases (domain)

```dart
abstract class ObserveSessionUseCase
    with CallableUseCaseWithoutParamsSync<Stream<Session>> {
  Session get current;
}

final class ObserveSessionUseCaseImpl extends ObserveSessionUseCase {
  ObserveSessionUseCaseImpl(this._sessionRepository);

  final SessionRepository _sessionRepository;

  @override
  Session get current => _sessionRepository.session;

  @override
  Stream<Session> call() => _sessionRepository.observeSession();
}
```

By id (no synchronous `current`, the source is async):

```dart
typedef ObserveFooUseCaseParams = ({String fooId});

abstract class ObserveFooUseCase
    with CallableUseCaseSync<ObserveFooUseCaseParams, Stream<Foo?>> {}
```

Combining sources is orchestration, so it belongs to the use case (`rxdart` is allowed in domain):

```dart
@override
Home get current => (
  session: _sessionRepository.session,
  unreadCount: _barRepository.unreadCount,
);

@override
Stream<Home> call() => Rx.combineLatest2(
  _sessionRepository.observeSession(),
  _barRepository.observeUnreadCount(),
  (session, unreadCount) => (session: session, unreadCount: unreadCount),
).distinct();
```

## ObserveFooBloc (ui)

App-wide value, subscribed for the bloc's whole life:

```dart
final class ObserveSessionBloc extends Cubit<ObserveSessionBlocState> {
  ObserveSessionBloc(this._observeSessionUseCase)
    : super(
        ObserveSessionBlocState.fromSession(_observeSessionUseCase.current),
      ) {
    _subscription = _observeSessionUseCase().listen(
      (session) => _emit(ObserveSessionBlocState.fromSession(session)),
      onError: (Object e, StackTrace stackTrace) => log.e(
        'Failed to observe the session: $e',
        error: e,
        stackTrace: stackTrace,
      ),
    );
  }

  final ObserveSessionUseCase _observeSessionUseCase;
  late final StreamSubscription<Session> _subscription;

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }

  void _emit(ObserveSessionBlocState state) {
    if (!isClosed) emit(state);
  }
}
```

By id, started by `configure` (the id lives in state, like load blocs):

```dart
sealed class ObserveFooBlocState extends Equatable {
  const ObserveFooBlocState();

  @override
  List<Object?> get props => const [];
}

final class ObserveFooBlocStateNotConfigured extends ObserveFooBlocState {
  const ObserveFooBlocStateNotConfigured();
}

sealed class ObserveFooBlocStateConfigured extends ObserveFooBlocState {
  const ObserveFooBlocStateConfigured({required this.fooId});

  final String fooId;

  @override
  List<Object?> get props => [fooId];
}

/// Configured; nothing stored yet (the first refresh has not saved it).
final class ObserveFooBlocStateWaiting extends ObserveFooBlocStateConfigured {
  const ObserveFooBlocStateWaiting({required super.fooId});
}

final class ObserveFooBlocStateLoaded extends ObserveFooBlocStateConfigured {
  const ObserveFooBlocStateLoaded({required super.fooId, required this.foo});

  final FooUiModel foo;

  @override
  List<Object?> get props => [fooId, foo];
}

final class ObserveFooBloc extends Cubit<ObserveFooBlocState> {
  ObserveFooBloc(this._observeFooUseCase)
    : super(const ObserveFooBlocStateNotConfigured());

  final ObserveFooUseCase _observeFooUseCase;
  StreamSubscription<Foo?>? _subscription;

  void configure({required String fooId}) {
    if (state is ObserveFooBlocStateConfigured) return;
    _emit(ObserveFooBlocStateWaiting(fooId: fooId));
    _subscription = _observeFooUseCase((fooId: fooId)).listen(
      (foo) => _emit(
        foo == null
            ? ObserveFooBlocStateWaiting(fooId: fooId)
            : ObserveFooBlocStateLoaded(
                fooId: fooId,
                foo: FooUiModel.fromFoo(foo),
              ),
      ),
      onError: (Object e, StackTrace stackTrace) => log.e(
        'Failed to observe foo $fooId: $e',
        error: e,
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }

  // _emit as above
}
```

- States: `NotConfigured` → `Waiting(fooId)` (nothing stored yet) → `Loaded(fooId, foo)`. The bloc emits UI models, never domain types.
- Subscription stored in a field and cancelled in `close()` (`cancel_subscriptions`); no `listen` without a stored subscription.
- App-wide observe blocs are created once in `Application` (`scaffolding-flutter-app` → Application widget); screen-level ones in the page's `BlocProvider` (`..configure(fooId: id)`).

## With load and action blocs

- **Watch + refresh** (offline-first by id): the page provides `ObserveFooBloc` for what it paints and triggers the network refresh with an action (`RefreshFooBloc` calling a use case that fetches with `CachePolicy.network`, or `refresh` when the user pulled, and saves). The refresh's failure is shown non-destructively (snackbar), the watched data stays. Skeleton only while `Waiting`.
- **Load + update stream** (default for entities): `LoadFooBloc` loads and subscribes to the update stream; nothing extra on the page.
- An action on one screen and an observer on another never talk to each other: the repository write emits, the observer re-emits.

## Tests

Use case (domain, `dart test`):

```dart
test('combines the latest session and unread count', () async {
  final sessions = StreamController<Session>();
  final counts = StreamController<int>();
  when(
    () => sessionRepository.observeSession(),
  ).thenAnswer((_) => sessions.stream);
  when(
    () => barRepository.observeUnreadCount(),
  ).thenAnswer((_) => counts.stream);
  const signedIn = SessionSignedIn(userId: 'user-1');

  final home = ObserveHomeUseCaseImpl(sessionRepository, barRepository)();
  final expectation = expectLater(
    home,
    emitsInOrder([
      (session: signedIn, unreadCount: 0),
      (session: signedIn, unreadCount: 3),
      emitsDone,
    ]),
  );
  sessions.add(signedIn);
  counts
    ..add(0)
    ..add(0)
    ..add(3);
  await Future.wait([sessions.close(), counts.close()]);
  await expectation;
});
```

Bloc (ui): by default through the screen's widget test, pushing values into the `StreamController` and expecting the repaint (`writing-widget-tests`); the `blocTest` form below is for the exception (`blocs` rule):

```dart
setUp(() {
  observeSession = _MockObserveSessionUseCase();
  sessions = StreamController<Session>();
  when(() => observeSession.current).thenReturn(const SessionSignedOut());
  when(() => observeSession()).thenAnswer((_) => sessions.stream);
});

blocTest<ObserveSessionBloc, ObserveSessionBlocState>(
  'emits each change',
  build: () => ObserveSessionBloc(observeSession),
  act: (_) => sessions.add(const SessionSignedIn(userId: 'user-1')),
  expect: () => const [ObserveSessionBlocStateSignedIn(userId: 'user-1')],
);

test('cancels the subscription on close', () async {
  final bloc = ObserveSessionBloc(observeSession);
  expect(sessions.hasListener, isTrue);

  await bloc.close();

  expect(sessions.hasListener, isFalse);
});
```

- [ ] Use case: emits in order, `distinct` drops repeats, `current` matches the repositories
- [ ] Bloc: initial state from `current`; each event mapped; subscription cancelled on close; by-id `configure` twice subscribes once
- [ ] Repository: subject seeded; update stream emits only after a confirmed write; database watch emits after a save (round-trip test against a real per-test database, `persisting-with-isar`)
- [ ] Integration: a change on screen A is visible on screen B without a manual refresh

## Checks

- [ ] Source picked from the table; no bloc mirrors repository state
- [ ] Subjects private, seeded where `current` is needed, closed in `dispose:`
- [ ] Observing use case returns a `Stream` from `call()` and exposes `current` when synchronous; combining in domain
- [ ] Subscription cancelled in `close()`; emits guarded after close
- [ ] Screens never call each other's blocs; writes reach observers through repositories
