import 'dart:async';

import 'package:data/src/core/disposable.dart';
import 'package:data/src/data_store/local/database/database_client.dart';
import 'package:data/src/repository/utils/with_app_exceptions.dart';
import 'package:data/src/session/auth_service.dart';
import 'package:domain/domain_model.dart';
import 'package:domain/domain_repository.dart';
import 'package:log/log.dart';
import 'package:rxdart/rxdart.dart';

final class SessionRepositoryImpl implements SessionRepository, Disposable {
  SessionRepositoryImpl(this._authService, this._database)
    : _session = BehaviorSubject.seeded(_sessionFor(_authService.userId)) {
    _subscription = _authService.userIdChanges
        .asyncMap(_onUserId)
        .listen(
          _session.add,
          onError: (Object e, StackTrace stackTrace) =>
              log.e('Auth state failed: $e', error: e, stackTrace: stackTrace),
        );
  }

  final AuthService _authService;
  final DatabaseClient _database;
  final BehaviorSubject<Session> _session;
  late final StreamSubscription<Session> _subscription;

  /// Cached data belongs to one user (`data` rule → Caching): the database is
  /// cleared before the next session is published.
  Future<Session> _onUserId(String? userId) async {
    final previous = _session.value;
    if (previous is SessionSignedIn && previous.userId != userId) {
      try {
        await _database.clearUserData();
      } catch (e, stackTrace) {
        log.e(
          'Failed to clear user data: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }
    return _sessionFor(userId);
  }

  @override
  Session get session => _session.value;

  @override
  Stream<Session> observeSession() => _session.stream.distinct();

  @override
  Future<void> signOut() => withAppExceptions(_authService.signOut);

  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await _session.close();
  }
}

Session _sessionFor(String? userId) =>
    userId == null ? const SessionSignedOut() : SessionSignedIn(userId: userId);
