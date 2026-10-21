import 'package:domain/domain_model.dart';
import 'package:domain/domain_repository.dart';
import 'package:domain/src/session/usecase/observe_session_use_case.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockSessionRepository extends Mock implements SessionRepository {}

void main() {
  late _MockSessionRepository repository;
  late ObserveSessionUseCase useCase;

  setUp(() {
    repository = _MockSessionRepository();
    useCase = ObserveSessionUseCaseImpl(repository);
  });

  test('current is the repository session', () {
    when(
      () => repository.session,
    ).thenReturn(const SessionSignedIn(userId: 'user-1'));

    expect(useCase.current, const SessionSignedIn(userId: 'user-1'));
  });

  test('call streams the repository sessions', () {
    when(repository.observeSession).thenAnswer(
      (_) => Stream.fromIterable(const [
        SessionSignedOut(),
        SessionSignedIn(userId: 'user-1'),
      ]),
    );

    expect(
      useCase(),
      emitsInOrder(const [
        SessionSignedOut(),
        SessionSignedIn(userId: 'user-1'),
      ]),
    );
  });
}
