---
name: writing-action-blocs
description: Write or change a Flutter action bloc (a Cubit for a mutation or form submit — create, update, delete, toggle, purchase) the kit way — constructor-injected use case (or repository contract for a plain CRUD call), Idle / InProgress / Success / Failure states holding the domain exception, double-submit guard, validation in domain, one-shot effects (navigation, toasts) as bloc_presentation events instead of state, an optimistic value held in the bloc state for online toggles, refreshing other screens through repository update streams instead of bloc-to-bloc calls, page wiring, and tests. Use when adding a button or form that changes data, fixing double submits, lost errors, repeated toasts or navigation, or stale screens after a change.
---

# Writing action blocs

Policy: the stack `blocs` rule (one bloc per action, sealed states, no emit after close, catch style, Action blocs); core `same-level-dependencies` (no bloc → bloc). Loading data is `writing-load-blocs`; errors and copy: `handling-errors`; validation rules: `modeling-domain`.

## Shape

- `final class CreateFooBloc extends Cubit<CreateFooBlocState> with BlocPresentationMixin<CreateFooBlocState, CreateFooBlocEvent>` in `create_foo_bloc.dart`, one action (or a tight family: buy / restore) per bloc.
- **Dependencies through the constructor**: the use case when there is a rule or orchestration; the repository contract directly for a plain CRUD call with no rule. Inputs (ids, drafts) are method arguments.
- **State** = what the screen shows while it is open: Idle, InProgress (button disabled, spinner), Success, Failure (inline error). **Presentation event** = something that happens once: navigate, pop with a result, toast, haptic. An event in state replays on rebuild and on re-subscribe; a state as an event is lost when nobody listens.
- **Double-submit guard**: the action is a no-op while `InProgress` (and after `Success` when the screen is leaving).


## Rules

- A mutation (save, submit, delete, send, purchase) has its own bloc: `Idle` → `InProgress` (holding the pending value when the UI shows it) → `Success` / `Failure` (holding the domain exception). A call while `InProgress` is ignored: one tap, one use-case call, one queued item.
- One-shot effects (navigate, pop with a result, a toast, a haptic, open a sheet) are `bloc_presentation` events, never state: a state replays on rebuild, an event as state is lost when nobody listens.
- Queued offline actions are optimistic; online-only ones are not (`queueing-offline-actions` → Policy). Template and page wiring: Template and Page wiring below.

## Template

```dart
sealed class CreateFooBlocState extends Equatable {
  const CreateFooBlocState();

  @override
  List<Object?> get props => const [];
}

final class CreateFooBlocStateIdle extends CreateFooBlocState {
  const CreateFooBlocStateIdle();
}

final class CreateFooBlocStateInProgress extends CreateFooBlocState {
  const CreateFooBlocStateInProgress();
}

final class CreateFooBlocStateSuccess extends CreateFooBlocState {
  const CreateFooBlocStateSuccess();
}

final class CreateFooBlocStateFailure extends CreateFooBlocState {
  const CreateFooBlocStateFailure({required this.error});

  final AppException error;

  @override
  List<Object?> get props => [error];
}

/// One-shot effects: they happen once and are never replayed on rebuild.
sealed class CreateFooBlocEvent {
  const CreateFooBlocEvent();
}

final class CreateFooBlocEventCreated extends CreateFooBlocEvent {
  const CreateFooBlocEventCreated({required this.fooId});

  final String fooId;
}

final class CreateFooBloc extends Cubit<CreateFooBlocState>
    with BlocPresentationMixin<CreateFooBlocState, CreateFooBlocEvent> {
  CreateFooBloc(this._createFooUseCase)
    : super(const CreateFooBlocStateIdle());

  final CreateFooUseCase _createFooUseCase;

  Future<void> submit({required FooDraft draft}) async {
    if (state is CreateFooBlocStateInProgress ||
        state is CreateFooBlocStateSuccess) {
      return;
    }
    _emit(const CreateFooBlocStateInProgress());
    try {
      final foo = await _createFooUseCase((draft: draft));
      _emit(const CreateFooBlocStateSuccess());
      _present(CreateFooBlocEventCreated(fooId: foo.id));
    } catch (e, stackTrace) {
      logFailure('Failed to create foo', e, stackTrace);
      _emit(CreateFooBlocStateFailure(error: AppException.from(e)));
    }
  }

  void _emit(CreateFooBlocState state) {
    if (!isClosed) emit(state);
  }

  void _present(CreateFooBlocEvent event) {
    if (!isClosed) emitPresentation(event);
  }
}
```

- `_emit` / `_present` stand in for the project's emit-after-close helpers (repository rules); `logFailure` and `AppException.from`: `handling-errors`.
- Registered with `registerFactory(() => CreateFooBloc(getIt()))`; a new instance per `BlocProvider`.
- The bloc does not validate: the use case runs `draft.validate()` and throws `FooDraftInvalidException(violations)`, which lands in `Failure` like any other error. Live validation while typing, where the design wants it, calls the same domain `validate()` from a form bloc method that emits the violations; it never re-implements a rule.
- After `Failure` the next `submit` is allowed (retry); `Failure` is cleared by the next `InProgress`.

## Optimistic updates

For instant toggles (favorite, like, mark done) on an online write, the target value lives in `InProgress` and, once the server confirmed it, in `Success`; on `Failure` the widget falls back to the payload. Nothing was written locally, so there is nothing to roll back: the bloc state is the only optimistic copy. Rollback of the local store is a separate, explicit step that exists only for queued offline actions (`queueing-offline-actions` → Policy). `Success` keeps the value because the payload catches up only after the load bloc re-reads — showing the payload at once would flash the old value.

```dart
/// [favorite] is the optimistic value the UI shows until the call ends.
final class FavoriteFooBlocStateInProgress extends FavoriteFooBlocState {
  const FavoriteFooBlocStateInProgress({required this.favorite});

  final bool favorite;

  @override
  List<Object?> get props => [favorite];
}

/// The server confirmed [favorite]; shown until the payload catches up.
final class FavoriteFooBlocStateSuccess extends FavoriteFooBlocState {
  const FavoriteFooBlocStateSuccess({required this.favorite});

  final bool favorite;

  @override
  List<Object?> get props => [favorite];
}

/// Plain CRUD with no rule behind it: the repository contract directly.
final class FavoriteFooBloc extends Cubit<FavoriteFooBlocState>
    with BlocPresentationMixin<FavoriteFooBlocState, FavoriteFooBlocEvent> {
  FavoriteFooBloc(this._fooRepository)
    : super(const FavoriteFooBlocStateIdle());

  final FooRepository _fooRepository;

  Future<void> setFavorite({
    required String fooId,
    required bool favorite,
  }) async {
    if (state is FavoriteFooBlocStateInProgress) return;
    _emit(FavoriteFooBlocStateInProgress(favorite: favorite));
    try {
      await _fooRepository.updateFooFavorite(fooId: fooId, favorite: favorite);
      _emit(FavoriteFooBlocStateSuccess(favorite: favorite));
    } catch (e, stackTrace) {
      logFailure('Failed to set foo $fooId favorite', e, stackTrace);
      final error = AppException.from(e);
      _emit(FavoriteFooBlocStateFailure(error: error));
      _present(FavoriteFooBlocEventFailed(error: error));
    }
  }

  // _emit / _present as above
}
```

The widget shows `switch (state) { FavoriteFooBlocStateInProgress(:final favorite) || FavoriteFooBlocStateSuccess(:final favorite) => favorite, _ => payload.favorite }`. The row provides the bloc with `key: ValueKey((foo.id, foo.favorite))`, so a payload change (the re-read, or another screen) starts a fresh bloc that shows the payload. The repository writes to the backend first and updates its local copy and update stream from the response (stack `data` rule), so the payload changes only when the server confirmed. A write the user can make offline is not this bloc's job: it goes through the action queue, optimistic in the local store with explicit rollback, and only in apps that declare queued offline writes (`queueing-offline-actions` → Policy).

## Refreshing other screens

- After a confirmed write, the **repository** fires its update signal (`fooUpdates`) or saves to the database that observers watch. Load and observe blocs on other screens re-emit from it (`observing-data`, `writing-load-blocs`).
- Never call another bloc from a bloc, and never pass a bloc into one. On the same page, the page may wire two blocs with a `BlocPresentationListener` / `BlocListener` that calls the second one (one level up).
- Navigation results: `final created = await CreateFooRoute().push<String>(context)` when the caller needs the id; the update stream handles everything else.

## Page wiring

```dart
class CreateFooPage extends StatelessWidget {
  const CreateFooPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => inject<CreateFooBloc>(),
    child: BlocPresentationListener<CreateFooBloc, CreateFooBlocEvent>(
      listener: (context, event) => switch (event) {
        CreateFooBlocEventCreated(:final fooId) =>
          FooDetailsRoute(fooId: fooId).go(context),
      },
      child: const _CreateFooForm(),
    ),
  );
}
```

In the form (a `StatefulWidget` owning the `TextEditingController`s):

```dart
BlocBuilder<CreateFooBloc, CreateFooBlocState>(
  builder: (context, state) {
    final violations = switch (state) {
      CreateFooBlocStateFailure(
        error: FooDraftInvalidException(:final violations),
      ) =>
        violations,
      _ => const <FooDraftViolation>{},
    };
    final inProgress = state is CreateFooBlocStateInProgress;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _title,
          decoration: InputDecoration(
            labelText: context.strings.fooTitle,
            errorText: _titleError(context.strings, violations),
          ),
        ),
        if (state case CreateFooBlocStateFailure(
          :final error,
        ) when error is! FooDraftInvalidException)
          Text(error.message(context.strings)),
        ElevatedButton(
          onPressed: inProgress
              ? null
              : () => context.read<CreateFooBloc>().submit(
                  draft: FooDraft(title: _title.text, itemIds: _itemIds),
                ),
          child: inProgress
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(),
                )
              : Text(context.strings.fooCreate),
        ),
      ],
    );
  },
)
```

- The button is disabled while `InProgress` (the guard in the bloc still holds for other callers).
- Field errors from the violations, one copy per violation; other failures inline or as a toast event — pick one per screen, not both.
- An action bloc used by one widget in a list (a favorite button per row) is provided by that widget, not by the page.
- A purchase or other action whose error must surface on any screen is an app-wide bloc in `Application`, with a `BlocPresentationListener` there (`scaffolding-flutter-app`).

## Tests

By default these cases run as widget tests of the screen, with the real bloc over mocked use cases (`writing-widget-tests`); a `blocTest` is the exception for a case no widget or flow test reaches, or the norm only where the project unit-tests blocs (`blocs` rule). Integration flows cover the page either way. Mock the use case or repository (`testing-use-cases` for mocktail and fallbacks). The shape of a case, shown as a `blocTest`:

```dart
blocTest<CreateFooBloc, CreateFooBlocState>(
  'emits InProgress then Success',
  setUp: () => when(() => createFoo(any())).thenAnswer((_) async => foo),
  build: () => CreateFooBloc(createFoo),
  act: (bloc) => bloc.submit(draft: draft),
  expect: () => const [
    CreateFooBlocStateInProgress(),
    CreateFooBlocStateSuccess(),
  ],
);

test('presents Created with the new id', () async {
  when(() => createFoo(any())).thenAnswer((_) async => foo);
  final bloc = CreateFooBloc(createFoo);
  final presented = expectLater(
    bloc.presentation,
    emits(
      isA<CreateFooBlocEventCreated>().having(
        (event) => event.fooId,
        'fooId',
        'foo-1',
      ),
    ),
  );

  await bloc.submit(draft: draft);

  await presented;
  await bloc.close();
});

test('ignores a second submit while the first runs', () async {
  final pending = Completer<Foo>();
  when(() => createFoo(any())).thenAnswer((_) => pending.future);
  final bloc = CreateFooBloc(createFoo);

  final first = bloc.submit(draft: draft);
  await bloc.submit(draft: draft);
  pending.complete(foo);
  await first;

  verify(() => createFoo(any())).called(1);
  await bloc.close();
});
```

- [ ] Success: `[InProgress, Success]` and the presentation event with its data
- [ ] Failure: `[InProgress, Failure(error)]` with the domain exception; no success event
- [ ] Invalid draft: `Failure(FooDraftInvalidException)` with the violations
- [ ] Double submit: one use-case call
- [ ] Optimistic: `InProgress(target)` then `Success`; failure → `Failure` and the `Failed` event
- [ ] `close()` during the call: no emit or presentation after close
- [ ] Integration: submit → navigation / toast; failure → message visible and button enabled again; the other screen shows the change (update stream)

## Checks

- [ ] Dependencies via constructor; inputs as method arguments; plain factory registration
- [ ] Idle / InProgress / Success / Failure; Failure holds `AppException`
- [ ] Guard against double submit
- [ ] Navigation and toasts are presentation events; nothing one-shot in state
- [ ] Validation in domain; the bloc never re-implements a rule
- [ ] Optimistic value only in `InProgress`; confirmed value from the repository
- [ ] Other screens refresh through repository streams, never bloc → bloc
