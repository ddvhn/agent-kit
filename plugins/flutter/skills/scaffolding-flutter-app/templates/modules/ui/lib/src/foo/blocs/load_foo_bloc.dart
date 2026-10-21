import 'package:domain/domain_model.dart';
import 'package:domain/domain_usecase.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ui/src/common/extensions/app_exception_x.dart';
import 'package:ui/src/foo/models/foo_ui_model.dart';

/// The no-id, network-only load bloc (writing-load-blocs): the page calls
/// `..reload()` in `create`.
sealed class LoadFooBlocState extends Equatable {
  const LoadFooBlocState();

  @override
  List<Object?> get props => const [];
}

final class LoadFooBlocStateIdle extends LoadFooBlocState {
  const LoadFooBlocStateIdle();
}

final class LoadFooBlocStateLoading extends LoadFooBlocState {
  const LoadFooBlocStateLoading();
}

final class LoadFooBlocStateError extends LoadFooBlocState {
  const LoadFooBlocStateError({required this.error});

  final AppException error;

  @override
  List<Object?> get props => [error];
}

sealed class LoadFooBlocStateLoaded extends LoadFooBlocState {
  const LoadFooBlocStateLoaded({required this.foo});

  final FooUiModel foo;

  @override
  List<Object?> get props => [foo];
}

final class LoadFooBlocStateSuccess extends LoadFooBlocStateLoaded {
  const LoadFooBlocStateSuccess({required super.foo});
}

final class LoadFooBlocStateReloading extends LoadFooBlocStateLoaded {
  const LoadFooBlocStateReloading({required super.foo});
}

final class LoadFooBlocStateReloadError extends LoadFooBlocStateLoaded {
  const LoadFooBlocStateReloadError({required super.foo, required this.error});

  final AppException error;

  @override
  List<Object?> get props => [foo, error];
}

final class LoadFooBloc extends Cubit<LoadFooBlocState> {
  LoadFooBloc(this._fetchFooUseCase) : super(const LoadFooBlocStateIdle());

  final FetchFooUseCase _fetchFooUseCase;

  Future<void> reload() async {
    final state = this.state;
    if (state is LoadFooBlocStateLoading ||
        state is LoadFooBlocStateReloading) {
      return;
    }
    _emit(
      state is LoadFooBlocStateLoaded
          ? LoadFooBlocStateReloading(foo: state.foo)
          : const LoadFooBlocStateLoading(),
    );
    try {
      final foo = await _fetchFooUseCase();
      _emit(LoadFooBlocStateSuccess(foo: FooUiModel.fromFoo(foo)));
    } catch (e, stackTrace) {
      logFailure('Failed to load foo', e, stackTrace);
      final error = AppException.from(e);
      _emit(switch (this.state) {
        LoadFooBlocStateLoaded(:final foo) => LoadFooBlocStateReloadError(
          foo: foo,
          error: error,
        ),
        _ => LoadFooBlocStateError(error: error),
      });
    }
  }

  void _emit(LoadFooBlocState state) {
    if (!isClosed) emit(state);
  }
}
