import 'package:data/src/session/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

final class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth);

  final FirebaseAuth _auth;

  @override
  String? get userId => _auth.currentUser?.uid;

  @override
  Stream<String?> get userIdChanges =>
      _auth.authStateChanges().map((user) => user?.uid);

  @override
  Future<void> signOut() => _auth.signOut();
}
