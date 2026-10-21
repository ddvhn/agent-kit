import 'package:domain/src/common/usecase/callable_use_case.dart';
import 'package:domain/src/session/model/session.dart';
import 'package:domain/src/session/repository/session_repository.dart';

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
