import 'auth_models.dart';
import 'auth_storage.dart';

abstract class AuthRepository {
  Future<AuthSession?> currentSessionFromStorage();
  Future<AuthSession?> previousAnonymousSessionFromStorage();
  Future<AuthSession> createAnonymousSession(String deviceId);
  Future<AuthSession?> validateStoredSession(AuthSession session);
  Future<void> persistSession(AuthSession session);
  Future<void> clearUserSession();
  Future<void> clearAnonymousSession();
}

class LocalPlaceholderAuthRepository implements AuthRepository {
  LocalPlaceholderAuthRepository(this._storage);

  final InMemoryAuthStorage _storage;

  @override
  Future<AuthSession?> currentSessionFromStorage() {
    return _storage.readSession();
  }

  @override
  Future<AuthSession?> previousAnonymousSessionFromStorage() {
    return _storage.readPreviousAnonymousSession();
  }

  @override
  Future<AuthSession> createAnonymousSession(String deviceId) async {
    final issuedAt = DateTime.now().microsecondsSinceEpoch;

    return AuthSession(
      ownerType: OwnerType.anonymous,
      accessToken: 'local-anonymous-access-$issuedAt',
      refreshToken: 'local-anonymous-refresh-$issuedAt',
      anonymousId: 'local-$deviceId-$issuedAt',
    );
  }

  @override
  Future<AuthSession?> validateStoredSession(AuthSession session) async {
    return session;
  }

  @override
  Future<void> persistSession(AuthSession session) {
    return _storage.writeSession(session);
  }

  @override
  Future<void> clearUserSession() {
    return _storage.clearUserSession();
  }

  @override
  Future<void> clearAnonymousSession() {
    return _storage.clearAnonymousSession();
  }
}
