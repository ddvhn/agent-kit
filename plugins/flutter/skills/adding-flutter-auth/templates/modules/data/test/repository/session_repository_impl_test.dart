import 'dart:async';

import 'package:data/src/data_store/local/database/database_client.dart';
import 'package:data/src/repository/session_repository_impl.dart';
import 'package:data/src/session/auth_service.dart';
import 'package:domain/domain_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDatabaseClient extends Mock implements DatabaseClient {}

final class _FakeAuthService implements AuthService {
  _FakeAuthService(this.userId);

  final _changes = StreamController<String?>.broadcast();

  @override
  String? userId;

  @override
  Stream<String?> get userIdChanges => _changes.stream;

  void emit(String? id) {
    userId = id;
    _changes.add(id);
  }

  @override
  Future<void> signOut() async => emit(null);
}

void main() {
  late _FakeAuthService auth;
  late _MockDatabaseClient database;
  late SessionRepositoryImpl repository;

  setUp(() {
    auth = _FakeAuthService('user-1');
    database = _MockDatabaseClient();
    when(database.clearUserData).thenAnswer((_) async {});
    repository = SessionRepositoryImpl(auth, database);
  });

  tearDown(() => repository.dispose());

  test('starts with the auth service user', () {
    expect(repository.session, const SessionSignedIn(userId: 'user-1'));
  });

  test('the same user again changes nothing', () async {
    auth.emit('user-1');
    await pumpEventQueue();

    verifyNever(database.clearUserData);
  });

  test('sign-out clears user data before publishing the session', () async {
    final sessions = <Session>[];
    repository.observeSession().listen(sessions.add);
    await pumpEventQueue();
    when(database.clearUserData).thenAnswer((_) async {
      expect(repository.session, const SessionSignedIn(userId: 'user-1'));
    });

    await repository.signOut();
    await pumpEventQueue();

    verify(database.clearUserData).called(1);
    expect(sessions, const [
      SessionSignedIn(userId: 'user-1'),
      SessionSignedOut(),
    ]);
  });

  test('another user clears the previous user data', () async {
    auth.emit('user-2');
    await pumpEventQueue();

    verify(database.clearUserData).called(1);
    expect(repository.session, const SessionSignedIn(userId: 'user-2'));
  });
}
