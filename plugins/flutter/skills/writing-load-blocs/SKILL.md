---
name: writing-load-blocs
description: Write or change a Flutter load bloc (LoadFooBloc, a Cubit) with the configure-then-reload lifecycle and cache-then-refresh — sealed state hierarchy, configure / reload, cache policy for offline-first apps, page wiring with BlocProvider and pull-to-refresh, and the tests to write. Use when adding a screen or screen region that loads data, loading an entity by id, adding offline cache or pull-to-refresh to a bloc, or fixing skeletons, error states, or lost payloads during refresh.
---

# Writing load blocs

Policy: the stack `blocs` rule (Shape, Load blocs) and `ui` rule → Widgets. The project's emit helper, DI lookup, localization accessor, and whether it caches locally: the repository's `.claude/rules/` and `CLAUDE.md`. Use cases: `modeling-domain`; repositories: `creating-flutter-repositories`. Paged or accumulating lists: `paging-lists`; streams the bloc only observes: `observing-data`; mutations: `writing-action-blocs`. This skill covers one payload per bloc.

## Which variant

| | Offline-first (local database cache) | Network-only |
| --- | --- | --- |
| Use case / repository read | takes `CachePolicy` | no policy |
| `reload()` from `Idle` | paint cache, then network as `Reloading` | `Loading`, then network |
| Offline start | cached payload shown, `ReloadError` after the failed refresh | `Error` with retry |
| Tests | add the cache-hit cases | skip them |

Everything else — states, `configure`, `reload`, page wiring — is identical. A repository that itself falls back to its database when the network fails is network-only from the bloc's view.

## Cache policy (offline-first only)

`CachePolicy` and what each value reads: the `data` rule → Caching. In a bloc: `cache` paints first, `network` refreshes (`reload()`, background polls), `refresh` answers the user's pull-to-refresh (`reload(refresh: true)`). The use case takes it in its params record (`typedef FetchFooUseCaseParams = ({String fooId, CachePolicy cachePolicy});`). Write `.network` instead of `CachePolicy.network` when the SDK supports dot shorthands (`dart` rule).


## Lifecycle rules

- A page creates its load blocs in `BlocProvider.create`. Blocs are not a cache: the repository (and its local database, when the project caches) is the source of truth.
- By id: the bloc starts `NotConfigured`; `configure(fooId: …)` emits `Idle` and is a no-op once configured; `reload()` is a no-op until configured. The id lives in the state, never in the constructor or DI factory parameters. The page calls `..configure(fooId: id)..reload()` in `create`; no first load from `initState`. Without an id the bloc starts `Idle`.
- States: `NotConfigured` → configured (`Idle` / `Loading` / `Error`) → loaded (`Success` / `Reloading` / `ReloadError`, each carrying the payload). `Error` holds the exception (`architecture` rule → Errors). A failed refresh emits `ReloadError` and keeps the payload; `Error` only when nothing is shown yet. `reload()` while `Loading` / `Reloading` is a no-op.
- With a local cache: `reload()` from `Idle` paints the cached payload first, then refreshes from the network as `Reloading`; pull-to-refresh is `reload(refresh: true)` (`CachePolicy.refresh`, past the TTL). Offline with a cache is a supported state, not an error.
- Paged lists: the same lifecycle without `NotConfigured`; every loaded state carries the items and the cursor, plus `LoadingMore` / `LoadMoreError` that keep the items (`paging-lists`).
- Placeholders (skeletons) only while there is no payload (`Idle` / `Loading`), per loaded region; static chrome stays on screen (`ui` rule → Widgets).

## States

```dart
sealed class LoadFooBlocState extends Equatable {
  const LoadFooBlocState();

  @override
  List<Object?> get props => const [];
}

final class LoadFooBlocStateNotConfigured extends LoadFooBlocState {
  const LoadFooBlocStateNotConfigured();
}

sealed class LoadFooBlocStateConfigured extends LoadFooBlocState {
  const LoadFooBlocStateConfigured({required this.fooId});

  final String fooId;

  @override
  List<Object?> get props => [fooId];
}

final class LoadFooBlocStateIdle extends LoadFooBlocStateConfigured {
  const LoadFooBlocStateIdle({required super.fooId});
}

final class LoadFooBlocStateLoading extends LoadFooBlocStateConfigured {
  const LoadFooBlocStateLoading({required super.fooId});
}

final class LoadFooBlocStateError extends LoadFooBlocStateConfigured {
  const LoadFooBlocStateError({required super.fooId, required this.error});

  final AppException error;

  @override
  List<Object?> get props => [fooId, error];
}

sealed class LoadFooBlocStateLoaded extends LoadFooBlocStateConfigured {
  const LoadFooBlocStateLoaded({required super.fooId, required this.foo});

  final FooUiModel foo;

  @override
  List<Object?> get props => [fooId, foo];
}

final class LoadFooBlocStateSuccess extends LoadFooBlocStateLoaded {
  const LoadFooBlocStateSuccess({required super.fooId, required super.foo});
}

final class LoadFooBlocStateReloading extends LoadFooBlocStateLoaded {
  const LoadFooBlocStateReloading({required super.fooId, required super.foo});
}

final class LoadFooBlocStateReloadError extends LoadFooBlocStateLoaded {
  const LoadFooBlocStateReloadError({
    required super.fooId,
    required super.foo,
    required this.error,
  });

  final AppException error;

  @override
  List<Object?> get props => [fooId, foo, error];
}
```

- `Idle` = configured, nothing requested yet. `Error` = failed with nothing to show. Every `Loaded` subtype carries the payload, so widgets paint it in all three.
- `Error` and `ReloadError` hold the domain exception (`AppException.from(e)`); the UI turns it into copy with `error.message(context.strings)` (`handling-errors`).
- Value equality the project's way (`Equatable` shown). Use primary constructors only where the SDK and neighbors do.

## Bloc

```dart
final class LoadFooBloc extends Cubit<LoadFooBlocState> {
  LoadFooBloc(this._fetchFooUseCase)
    : super(const LoadFooBlocStateNotConfigured());

  final FetchFooUseCase _fetchFooUseCase;

  void configure({required String fooId}) {
    if (state is LoadFooBlocStateConfigured) return;
    _emit(LoadFooBlocStateIdle(fooId: fooId));
  }

  /// [refresh]: the user asked (pull-to-refresh) — past the in-memory TTL.
  Future<void> reload({bool refresh = false}) async {
    final state = this.state;
    if (state is! LoadFooBlocStateConfigured) return;
    if (state is LoadFooBlocStateLoading || state is LoadFooBlocStateReloading) {
      return;
    }
    final fooId = state.fooId;

    if (state is LoadFooBlocStateLoaded) {
      _emit(LoadFooBlocStateReloading(fooId: fooId, foo: state.foo));
    } else {
      _emit(LoadFooBlocStateLoading(fooId: fooId));
      // Offline-first only: paint the cached payload before the network call.
      final cached = await _readCachedFoo(fooId);
      if (cached != null) {
        _emit(LoadFooBlocStateReloading(fooId: fooId, foo: cached));
      }
    }

    try {
      final foo = await _fetchFooUseCase((
        fooId: fooId,
        cachePolicy: refresh ? .refresh : .network, // network-only: no policy
      ));
      _emit(LoadFooBlocStateSuccess(fooId: fooId, foo: FooUiModel.fromFoo(foo)));
    } catch (e, stackTrace) {
      logFailure('Failed to load foo $fooId', e, stackTrace);
      final error = AppException.from(e);
      switch (this.state) {
        case LoadFooBlocStateLoaded(:final foo):
          _emit(
            LoadFooBlocStateReloadError(fooId: fooId, foo: foo, error: error),
          );
        case LoadFooBlocStateConfigured():
          _emit(LoadFooBlocStateError(fooId: fooId, error: error));
        case LoadFooBlocStateNotConfigured():
          break;
      }
    }
  }

  // Offline-first only.
  Future<FooUiModel?> _readCachedFoo(String fooId) async {
    try {
      final foo = await _fetchFooUseCase((
        fooId: fooId,
        cachePolicy: CachePolicy.cache,
      ));
      return FooUiModel.fromFoo(foo);
    } catch (_) {
      return null; // nothing cached: the network call decides
    }
  }

  void _emit(LoadFooBlocState state) {
    if (!isClosed) emit(state);
  }
}
```

- Dependencies only through the constructor: the use case, or the repository contract (`FooRepository`) when the read is a plain CRUD call with no rule behind it (`architecture` rule → Use cases). Never clients or services.
- `_emit` stands in for the project's emit-after-close helper; use that helper where it exists. `logFailure` logs expected failures as warnings and unknown ones with the trace (`handling-errors`).
- No `fetch()`, no id in the constructor, no DI factory parameters: a plain factory in `injectUiLayer`, `getIt.registerFactory(() => LoadFooBloc(getIt()))` (`scaffolding-flutter-app` → DI lifetimes).
- Maps `Foo` → `FooUiModel` here; widgets never see `Foo`.
- Several ids or inputs (`fooId`, `barId`): all of them are `configure` parameters and fields on `LoadFooBlocStateConfigured`.

### Variants

- **No id** (the signed-in user's data, a fixed list): drop `NotConfigured`, `Configured`, and `fooId`; the initial state is `Idle` and the page calls `..reload()`.
- **Seeded from a payload the caller already holds** (a list row opening a sheet, a parent bloc's state — never a route `$extra`): `configureWithFoo({required FooUiModel foo})` emits `Success` when not yet configured; the following `reload()` refreshes it as `Reloading`.

### External triggers (only where the feature needs them)

- **Locale change** (localized payloads): emit `Idle(fooId: …)` and call `reload()`; read the locale before the request and drop the result if it changed meanwhile.
- **Update signal** (`fooUpdates`, through an observing use case or the repository contract for plain CRUD; `observing-data`): subscribe in `configure` (by id) or the constructor (no id), keep the subscription in a field, cancel it in `close()`. On a signal, when loaded, re-read with `CachePolicy.cache` (the repository saved the server's copy before firing) and re-emit the same subtype with the new payload (`Success` / `ReloadError` → `Success`, `Reloading` stays `Reloading`); a `NotFoundException` there means the entity was deleted — emit what the screen shows for a missing entity.

  ```dart
  void configure({required String fooId}) {
    if (state is LoadFooBlocStateConfigured) return;
    _emit(LoadFooBlocStateIdle(fooId: fooId));
    _updates = _observeFooUpdatesUseCase().listen((_) => _refreshSilently());
  }
  ```

  `_updates` is a `StreamSubscription<void>?` field; `_refreshSilently()` does the `cache` re-read above and ignores failures after logging them.
- **Background poll or "data updated" signal**: re-read silently with `network` (the TTL provider skips the request while the payload is fresh) and emit `Success` without `Reloading` chrome; log and ignore failures.
- **Page shown again** (returning from a pushed route): `reload()` only where neighboring screens do.

## Page wiring

```dart
class FooPage extends StatelessWidget {
  const FooPage({super.key, required this.fooId});

  final String fooId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => inject<LoadFooBloc>()
      ..configure(fooId: fooId)
      ..reload(),
    child: const _FooView(),
  );
}

class _FooView extends StatelessWidget {
  const _FooView();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LoadFooBloc>();
    return BlocListener<LoadFooBloc, LoadFooBlocState>(
      listenWhen: (_, current) => current is LoadFooBlocStateReloadError,
      listener: (context, state) {
        if (state is! LoadFooBlocStateReloadError) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.error.message(context.strings))),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: Text(context.strings.fooTitle)),
        body: RefreshIndicator(
          onRefresh: () => bloc.reload(refresh: true),
          child: BlocBuilder<LoadFooBloc, LoadFooBlocState>(
            builder: (context, state) => switch (state) {
              LoadFooBlocStateLoaded(:final foo) => FooContent(foo: foo),
              LoadFooBlocStateError(:final error) => ErrorView(
                error: error,
                onRetry: bloc.reload,
              ),
              LoadFooBlocStateNotConfigured() ||
              LoadFooBlocStateIdle() ||
              LoadFooBlocStateLoading() => const FooSkeleton(),
            },
          ),
        ),
      ),
    );
  }
}
```

- `inject<T>()` is the UI lookup helper (`di` rule → Wiring); `logFailure`, `error.message(strings)`, and the shared `ErrorView` come from `handling-errors`; `context.strings` stands for the project's localization accessor.
- First load only in `create` (`configure` then `reload`); never from `initState`, `didChangeDependencies`, or `build`.
- Exhaustive `switch` over the sealed state; no `default`. Skeleton only without a payload; the app bar, close / back, and other static chrome are outside the switch.
- `RefreshIndicator` needs a scrollable child in every branch (`AlwaysScrollableScrollPhysics` on the error and skeleton views).
- Show `ReloadError` the way neighbors do (snackbar, inline banner, the project's notification helper); never replace the content with an error view.
- Several blocs on one page: `MultiBlocProvider`, each `..configure(…)..reload()`; pull-to-refresh awaits `Future.wait([...])` over their `reload()`s.
- A bloc whose input comes from another bloc's payload (author of a loaded post): `configure` it from a `BlocListener` on the first bloc's `Loaded` state, then `reload()`.

## Tests

By default these cases run as widget tests of the screen, with the real bloc over mocked use cases (`writing-widget-tests`); a `blocTest` is the exception for a case no widget or flow test reaches, or the norm only where the project unit-tests blocs (`blocs` rule). Mock the use case (or the repository the bloc injects).

Bloc (each case through the page's widget test):

- [ ] `reload()` before `configure` emits nothing and calls nothing
- [ ] `configure` twice keeps the first id
- [ ] Cache miss → `[Loading, Success]`; cache miss and network failure → `[Loading, Error(exception)]`
- [ ] Offline-first: cache hit → `[Loading, Reloading(cached), Success(network)]`; cache hit and network failure → `[Loading, Reloading(cached), ReloadError(cached)]`
- [ ] Loaded, refresh fails → `[Reloading, ReloadError]` with the old payload
- [ ] `reload()` while `Loading` / `Reloading` → one use-case call
- [ ] `close()` during a request → no emit after close
- [ ] Each external trigger the bloc has (locale, update stream, poll)

Integration (`writing-patrol-tests`), driven through the UI:

- [ ] Happy path: the page shows the content
- [ ] Offline-first: seeded cache and failing network → content visible, no error view
- [ ] No cache and failing network → error view with the mapped message; retry succeeds
- [ ] Pull-to-refresh failure keeps the content and shows the reload message

## Checks

- [ ] `final class LoadFooBloc extends Cubit<LoadFooBlocState>` in `load_foo_bloc.dart`; sealed states as above
- [ ] Use case (or plain-CRUD repository contract) through the constructor; id in state via `configure`; plain DI factory; no `fetch()`
- [ ] Failed refresh keeps the payload (`ReloadError`); `Error` only with nothing shown; both hold the exception
- [ ] Skeleton only without a payload; static chrome always visible
- [ ] Variant matches the project (cache policy only when it caches locally)
- [ ] Tests above for the variant
