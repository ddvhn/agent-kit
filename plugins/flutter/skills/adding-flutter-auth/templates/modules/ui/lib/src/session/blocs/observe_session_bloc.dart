import 'dart:async';

import 'package:domain/domain_model.dart';
import 'package:domain/domain_usecase.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:log/log.dart';

sealed class ObserveSessionBlocState extends Equatable {
  const ObserveSessionBlocState();

  factory ObserveSessionBlocState.fromSession(Session session) =>
      switch (session) {
        SessionSignedOut() => const ObserveSessionBlocStateSignedOut(),
        SessionSignedIn(:final userId) => ObserveSessionBlocStateSignedIn(
          userId: userId,
        ),
      };

  @override
  List<Object?> get props => const [];
}

final class ObserveSessionBlocStateSignedOut extends ObserveSessionBlocState {
  const ObserveSessionBlocStateSignedOut();
}

final class ObserveSessionBlocStateSignedIn extends ObserveSessionBlocState {
  const ObserveSessionBlocStateSignedIn({required this.userId});

  final String userId;

  @override
  List<Object?> get props => [userId];
}

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
