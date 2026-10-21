/// The auth SDK, data-internal: only repositories use it.
abstract interface class AuthService {
  String? get userId;

  /// The signed-in user's id on every change; null when signed out.
  Stream<String?> get userIdChanges;

  Future<void> signOut();
}
