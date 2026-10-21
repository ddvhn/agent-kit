import 'package:domain/src/session/model/session.dart';

abstract interface class SessionRepository {
  Session get session;

  /// The current session for each new listener, then every change.
  Stream<Session> observeSession();

  Future<void> signOut();
}
