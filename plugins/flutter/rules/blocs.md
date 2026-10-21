---
description: Flutter state management — flutter_bloc Cubits, one bloc per action (load, observe, save / submit / delete), sealed states, UI models, re-entry ignored, one-off effects through bloc_presentation, no emit after close, form edits in widget state, blocs tested through their screen
paths:
  - "**/*.dart"
---

# Blocs

- `flutter_bloc` **Cubits**: `final class FooBloc extends Cubit<FooBlocState>` in `foo_bloc.dart`; an event `Bloc` only where transformers are needed.
- **One bloc per action, not per screen**, named after its use case: `LoadFooBloc`, `ObserveFooBloc`, `SaveFooBloc` / `SubmitFooBloc` / `DeleteFooBloc`. A page composes them (`MultiBlocProvider`, `MultiBlocListener`); a bloc never knows the screen or another bloc.
- Dependencies through the constructor; ids through `configure` (`writing-load-blocs`). Registered as factories; app-wide blocs are created once by `Application`.
- States are a `sealed class` with `Equatable`; widgets `switch` exhaustively (one exception: a timer owner that renders nothing, like the sync poller, may be a `Cubit<void>` — `syncing-server-changes`). A bloc emits UI models (`FooUiModel.fromFoo`), never domain types.
- Every emit is guarded after `close` (`if (!isClosed) emit(…)` or the project's helper). Catch with `catch (e)`, not `on Exception`.
- **Load**: `NotConfigured` → `Idle` / `Loading` / `Error` → `Success` / `Reloading` / `ReloadError` with the payload; a failed refresh keeps the payload; `reload()` while loading is a no-op (`writing-load-blocs`, `paging-lists`).
- **Observe**: subscribe once to a use case's `Stream`, cancel in `close()` (`observing-data`).
- **Action**: `Idle` → `InProgress` → `Success` / `Failure(exception)`; a call while `InProgress` is ignored: one tap, one use-case call. One-shot effects (navigate, toast) are `bloc_presentation` events, never state (`writing-action-blocs`).
- Form values stay in widget state; the bloc gets the finished value on submit.
- **Tests:** no separate bloc suite by default: the screen's widget tests run the real bloc over fake use cases and reach every state, error, and re-entry (`writing-widget-tests`). A `bloc_test` only for a case no widget or flow test reaches, with the reason in the PR.
