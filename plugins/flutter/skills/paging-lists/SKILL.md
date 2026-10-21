---
name: paging-lists
description: Build paged or infinite lists in a Flutter app the kit way — a Paged<T> domain result with an opaque cursor, cursor and limit through the use case and repository contract, the cross-stack paged contract (cursor, limit, nextCursor), an offline-first first page cached per filter, bounded user-owned lists synced whole instead, a load bloc whose states extend the load-bloc lifecycle with LoadingMore and LoadMoreError (items always kept), refresh that resets to page one and drops stale pages, de-duplication by id, a scroll-end trigger that also fills short screens, page wiring, and tests. Use when a list grows by pages (feeds, search results, history, "load more"), when fixing duplicate or lost rows, endless spinners, or load-more errors that wipe the list.
---

# Paging lists

Policy: the stack `blocs` rule (load-bloc lifecycle, placeholders only without a payload) and `data` rule (cache policy); core `architecture-principles` (offline-first). Single-payload loading is `writing-load-blocs`; this skill adds pages. Errors in states: `handling-errors`.

## Domain

```dart
/// One page of a cursor-paged list. [nextCursor] is opaque (the backend's
/// token, or the last item's id for `startAfter` APIs); null on the last page.
final class Paged<T> extends Equatable {
  const Paged({required this.items, required this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  @override
  List<Object?> get props => [items, nextCursor];
}
```

`Paged<T>` lives in `domain/lib/src/common/model/` (not `Page`, which collides with Flutter's `Page`). Contract and use case:

```dart
// FooRepository
/// [cachePolicy] applies to the first page only (`cursor == null`).
Future<Paged<Foo>> fetchFoos({
  required String? cursor,
  required int limit,
  required CachePolicy cachePolicy,
});

typedef FetchFoosUseCaseParams = ({
  String? cursor,
  int limit,
  CachePolicy cachePolicy,
});

abstract class FetchFoosUseCase
    with CallableUseCase<FetchFoosUseCaseParams, Paged<Foo>> {}
```

- The cursor is opaque to the client. The kit's paged contract with the backend (both stacks): request `{cursor?: string, limit: number}` (limit 1–50, default 20), response `{items: [...], nextCursor: string | null}`, camelCase keys; the backend makes the cursor from the last document id and resolves it for `startAfter`. The bloc never interprets it.
- `hasMore` is `nextCursor != null`. A third-party API without a cursor: derive it in the repository (`items.length == limit` → the last id), never in the bloc.
- Filters and sort are params next to `cursor`; changing them starts over from page one, and each filter has its own cache key.

## Data

- The API client method mirrors the callable: `Future<FooPageDto> listFoos({required String? cursor, required int limit})`, parsing `FooPageApiModel` (`items`, `nextCursor`) into `FooPageDto(items:, nextCursor:)` (`calling-cloud-functions`).
- The database stores the **first page per filter key** (normalized: the page row keeps the ordered ids and the cursor, the items go to their own collection, both in one write), so screens paint offline:

  ```dart
  // DatabaseClient
  Future<DbRecord<FooPageDto>?> fetchFooPage({required String key});
  Future<void> saveFooPage({
    required String key,
    required DbRecord<FooPageDto> record,
  });
  ```

- The repository sends later pages straight to the network (never persisted: they go stale and inflate storage) and reads page one through a TTL provider keyed by the filter:

  ```dart
  final _firstPages = TtlDataProvider<Paged<Foo>>(
    ttl: const Duration(minutes: 1),
  );

  @override
  Future<Paged<Foo>> fetchFoos({
    required String? cursor,
    required int limit,
    required CachePolicy cachePolicy,
  }) => withAppExceptions(() async {
    if (cursor != null) {
      final page = await _apiClient.listFoos(cursor: cursor, limit: limit);
      return page.toDomain();
    }
    const key = 'all'; // one key per filter: 'status=draft', …
    return _firstPages.fetch(
      key: key,
      cachePolicy: cachePolicy,
      fetchFromDatabase: () => _database.fetchFooPage(key: key),
      fetchFromNetwork: () => _apiClient.listFoos(cursor: null, limit: limit),
      saveToDatabase: (record) =>
          _database.saveFooPage(key: key, record: record),
      toDomain: (dto) => dto.toDomain(),
    );
  });
  ```

- `CachePolicy.cache` with nothing stored throws `NotFoundException`; `network` fetches and saves page one; a `cursor != null` request ignores the policy. A confirmed write evicts the affected first-page keys and fires `fooUpdates` (`observing-data`).

### Bounded user-owned lists (favorites, drafts, downloads)

A list the user owns, small enough to hold entirely (hundreds of rows, not a feed), and that must work fully offline — including showing a change made offline-later or on another screen — is **synced whole** instead of paged from the network:

- The repository fetches the whole list (the backend pages through it with the same contract until `nextCursor` is null), saves it to the database in one write, and exposes `Stream<List<Foo>> observeFavoriteFoos()` from a database watch (`watchLazy` on the collection, re-query in order).
- The screen observes the database (`ObserveFavoriteFoosBloc`, `observing-data`) and pages locally if it needs to; a refresh action re-syncs from the network; un-favoriting removes the row because the write updates the stored list.
- Choose it when the list is bounded by the user's own actions and offline completeness matters; choose server paging (above) for feeds, search, and anything unbounded.

## States

The load-bloc names plus two: every `Loaded` subtype carries `items` and `nextCursor`, so the list never disappears.

| State | Shown | Footer |
| --- | --- | --- |
| `Idle`, `Loading` | skeleton | — |
| `Error(error)` | error view with retry | — |
| `Success` | items | load-more trigger if `hasMore` |
| `Reloading` | items (refresh indicator) | — |
| `ReloadError(error)` | items + non-destructive message | — |
| `LoadingMore` | items | spinner |
| `LoadMoreError(error)` | items | message + retry |

```dart
sealed class LoadFoosBlocStateLoaded extends LoadFoosBlocState {
  const LoadFoosBlocStateLoaded({
    required this.items,
    required this.nextCursor,
  });

  final List<FooUiModel> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  @override
  List<Object?> get props => [items, nextCursor];
}

final class LoadFoosBlocStateLoadMoreError extends LoadFoosBlocStateLoaded {
  const LoadFoosBlocStateLoadMoreError({
    required super.items,
    required super.nextCursor,
    required this.error,
  });

  final AppException error;

  @override
  List<Object?> get props => [...super.props, error];
}

// Idle, Loading, Error(error) extend LoadFoosBlocState; Success, Reloading,
// ReloadError(error), LoadingMore extend LoadFoosBlocStateLoaded the same way.
```

## Bloc

```dart
final class LoadFoosBloc extends Cubit<LoadFoosBlocState> {
  LoadFoosBloc(this._fetchFoosUseCase) : super(const LoadFoosBlocStateIdle());

  static const pageSize = 20;

  final FetchFoosUseCase _fetchFoosUseCase;

  /// First load and pull-to-refresh ([refresh]: past the in-memory TTL):
  /// page one, replacing the list.
  Future<void> reload({bool refresh = false}) async {
    final state = this.state;
    if (state is LoadFoosBlocStateLoading ||
        state is LoadFoosBlocStateReloading) {
      return;
    }
    if (state is LoadFoosBlocStateLoaded) {
      _emit(
        LoadFoosBlocStateReloading(
          items: state.items,
          nextCursor: state.nextCursor,
        ),
      );
    } else {
      _emit(const LoadFoosBlocStateLoading());
      if (await _fetchCachedFirstPage() case final cached?) {
        _emit(
          LoadFoosBlocStateReloading(
            items: _merge(const [], cached.items),
            nextCursor: cached.nextCursor,
          ),
        );
      }
    }
    try {
      final page = await _fetchFoosUseCase((
        cursor: null,
        limit: pageSize,
        cachePolicy: refresh ? .refresh : .network,
      ));
      _emit(
        LoadFoosBlocStateSuccess(
          items: _merge(const [], page.items),
          nextCursor: page.nextCursor,
        ),
      );
    } catch (e, stackTrace) {
      logFailure('Failed to load foos', e, stackTrace);
      final error = AppException.from(e);
      switch (this.state) {
        case LoadFoosBlocStateLoaded(:final items, :final nextCursor):
          _emit(
            LoadFoosBlocStateReloadError(
              items: items,
              nextCursor: nextCursor,
              error: error,
            ),
          );
        case _:
          _emit(LoadFoosBlocStateError(error: error));
      }
    }
  }

  /// Next page; a no-op unless the list is settled and has more.
  Future<void> loadMore() async {
    if (state
        case LoadFoosBlocStateSuccess(
              :final items,
              nextCursor: final cursor?,
            ) ||
            LoadFoosBlocStateLoadMoreError(
              :final items,
              nextCursor: final cursor?,
            )) {
      await _loadPage(items: items, cursor: cursor);
    }
  }

  Future<void> _loadPage({
    required List<FooUiModel> items,
    required String cursor,
  }) async {
    _emit(LoadFoosBlocStateLoadingMore(items: items, nextCursor: cursor));
    try {
      final page = await _fetchFoosUseCase((
        cursor: cursor,
        limit: pageSize,
        cachePolicy: .network,
      ));
      if (_isLoadingMore(cursor)) {
        _emit(
          LoadFoosBlocStateSuccess(
            items: _merge(items, page.items),
            nextCursor: page.nextCursor,
          ),
        );
      }
    } catch (e, stackTrace) {
      logFailure('Failed to load more foos', e, stackTrace);
      if (_isLoadingMore(cursor)) {
        _emit(
          LoadFoosBlocStateLoadMoreError(
            items: items,
            nextCursor: cursor,
            error: AppException.from(e),
          ),
        );
      }
    }
  }

  /// False when a refresh replaced the list while this page was loading.
  bool _isLoadingMore(String cursor) => switch (state) {
    LoadFoosBlocStateLoadingMore(:final nextCursor) => nextCursor == cursor,
    _ => false,
  };

  Future<Paged<Foo>?> _fetchCachedFirstPage() async {
    try {
      return await _fetchFoosUseCase((
        cursor: null,
        limit: pageSize,
        cachePolicy: .cache,
      ));
    } catch (_) {
      return null;
    }
  }

  void _emit(LoadFoosBlocState state) {
    if (!isClosed) emit(state);
  }
}

/// Appends [page] without repeating ids: items shift when the backend
/// inserts or deletes between page requests.
List<FooUiModel> _merge(List<FooUiModel> items, List<Foo> page) {
  final seen = {for (final item in items) item.id};
  return [
    ...items,
    ...page.where((foo) => seen.add(foo.id)).map(FooUiModel.fromFoo),
  ];
}
```

- The cursor is the only paging state, kept in the state; no `_page`, `_isFetching`, or token fields.
- `reload()` is allowed during `LoadingMore`; the stale page is dropped by `_isLoadingMore`. `loadMore()` is ignored while loading, reloading, or after a refresh error (the user pulls again or scrolls after the next success).
- Load-more failures never become `Error`: the items stay and the footer offers retry.
- Items changed elsewhere: subscribe to the repository's `fooUpdates` signal in the constructor (cancel it in `close()`). While only page one is loaded, call `reload()` — it refreshes page one with the items kept on screen as `Reloading`; a row that no longer belongs to the list (un-favorited, deleted) disappears with the refreshed page. Past page one, `reload()` would drop the user back to the top: re-read the changed ids the signal carries and patch or remove those rows in place.
- Sliver or grid lists use the same bloc; only the footer placement changes.

## Page wiring

```dart
BlocProvider(
  create: (_) => inject<LoadFoosBloc>()..reload(),
  child: const _FoosView(),
)

// _FoosView
RefreshIndicator(
  onRefresh: () => bloc.reload(refresh: true),
  child: BlocBuilder<LoadFoosBloc, LoadFoosBlocState>(
    builder: (context, state) => switch (state) {
      LoadFoosBlocStateLoaded(:final items) when items.isEmpty =>
        const FoosEmptyView(),
      LoadFoosBlocStateLoaded(:final items) => ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length + 1,
        itemBuilder: (context, index) => index < items.length
            ? FooTile(foo: items[index])
            : _ListFooter(state: state),
      ),
      LoadFoosBlocStateError(:final error) => ErrorView(
        error: error,
        onRetry: bloc.reload,
      ),
      LoadFoosBlocStateIdle() || LoadFoosBlocStateLoading() =>
        const FoosSkeleton(),
    },
  ),
)
```

The footer and the trigger:

```dart
class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.state});

  final LoadFoosBlocStateLoaded state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<LoadFoosBloc>();
    return switch (state) {
      LoadFoosBlocStateLoadingMore() => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      LoadFoosBlocStateLoadMoreError(:final error) => ListTile(
        title: Text(error.message(context.strings)),
        trailing: TextButton(
          onPressed: bloc.loadMore,
          child: Text(context.strings.retry),
        ),
      ),
      LoadFoosBlocStateSuccess(:final nextCursor?) => LoadMoreTrigger(
        key: ValueKey(nextCursor),
        onVisible: bloc.loadMore,
      ),
      LoadFoosBlocStateLoaded() => const SizedBox.shrink(),
    };
  }
}

/// Calls [onVisible] once, after the list first builds its end. The list
/// builds it only near the viewport, and also when a short first page does
/// not fill the screen.
class LoadMoreTrigger extends StatefulWidget {
  const LoadMoreTrigger({super.key, required this.onVisible});

  final VoidCallback onVisible;

  @override
  State<LoadMoreTrigger> createState() => _LoadMoreTriggerState();
}

class _LoadMoreTriggerState extends State<LoadMoreTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 4);
}
```

- `LoadMoreTrigger` goes to `ui/lib/src/common/widgets/` once a second list needs it. Keyed by the cursor so each page triggers once.
- A `ReloadError` shows a snackbar from a `BlocListener` (as in `writing-load-blocs`); the list stays.
- Empty is its own view, not an error; skeleton only before the first payload.

## Tests

Bloc (mock the use case; params are a record, so register one as fallback). By default these cases run as widget tests of the screen, with the real bloc over mocked use cases (`writing-widget-tests`); a `blocTest` is the exception for a case no widget or flow test reaches, or the norm only where the project unit-tests blocs (`blocs` rule). The cases, shown as `blocTest`s:

```dart
setUpAll(() {
  registerFallbackValue((
    cursor: null,
    limit: 0,
    cachePolicy: CachePolicy.cache,
  ));
});

blocTest<LoadFoosBloc, LoadFoosBlocState>(
  'appends the next page without duplicates',
  setUp: () {
    stubPage(
      null,
      () async => Paged(items: [_foo('a'), _foo('b')], nextCursor: 'c1'),
    );
    stubPage(
      'c1',
      () async => Paged(items: [_foo('b'), _foo('c')], nextCursor: null),
    );
  },
  build: () => LoadFoosBloc(fetchFoos),
  act: (bloc) async {
    await bloc.reload();
    await bloc.loadMore();
  },
  expect: () => [
    const LoadFoosBlocStateLoading(),
    LoadFoosBlocStateSuccess(items: _ui(['a', 'b']), nextCursor: 'c1'),
    LoadFoosBlocStateLoadingMore(items: _ui(['a', 'b']), nextCursor: 'c1'),
    LoadFoosBlocStateSuccess(items: _ui(['a', 'b', 'c']), nextCursor: null),
  ],
);
```

`stubPage(cursor, answer)` stubs `fetchFoos(any(that: …))` with a matcher on the record's `cursor` and `cachePolicy` (`isA<FetchFoosUseCaseParams>().having((p) => p.cursor, 'cursor', cursor)`); the cache read is stubbed to throw `NotFoundException` unless the case seeds it.

- [ ] First load without cache: `[Loading, Success]`; with cached page one: `[Loading, Reloading(cached), Success]`
- [ ] Load more appends, de-duplicates, and updates `nextCursor`; last page → no trigger, `loadMore()` calls nothing
- [ ] Load-more failure: `[LoadingMore, LoadMoreError]` with the items; retry succeeds
- [ ] Refresh failure keeps items (`ReloadError`); refresh during `LoadingMore` drops the stale page
- [ ] `loadMore()` while `Loading` / `Reloading` / `LoadingMore` → no call
- [ ] Repository: page one saved and read back offline; later pages not persisted; `cache` with nothing stored → `NotFoundException`
- [ ] Integration: scroll to the end loads the next page; offline start shows the cached first page; load-more error shows retry in the footer

## Checks

- [ ] `Paged<T>` with an opaque cursor; `hasMore` from the backend or derived in the repository
- [ ] Only page one cached, per filter key; policy ignored for later pages
- [ ] A bounded user-owned list that must work offline is synced whole and observed from the database instead
- [ ] Every `Loaded` state carries items and cursor; errors carry `AppException`; load-more errors keep items
- [ ] Stale pages dropped after a refresh; merge de-duplicates by id
- [ ] Trigger fills short screens; pull-to-refresh is `reload(refresh: true)`
