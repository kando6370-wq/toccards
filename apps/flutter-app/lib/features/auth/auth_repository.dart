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
  Future<void> sendRegisterCode(String email);
  Future<AuthSession> verifyRegister({
    required String email,
    required String code,
    required String password,
    String? anonymousId,
  });
  Future<AuthSession> login({required String email, required String password});
  Future<void> sendForgotPasswordCode(String email);
  Future<String> verifyForgotPasswordCode({
    required String email,
    required String code,
  });
  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  });
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

  @override
  Future<void> sendRegisterCode(String email) async {}

  @override
  Future<AuthSession> verifyRegister({
    required String email,
    required String code,
    required String password,
    String? anonymousId,
  }) async {
    return _userSession(email);
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    return _userSession(email);
  }

  @override
  Future<void> sendForgotPasswordCode(String email) async {}

  @override
  Future<String> verifyForgotPasswordCode({
    required String email,
    required String code,
  }) async {
    return 'local-reset-token-$email';
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {}

  AuthSession _userSession(String email) {
    final issuedAt = DateTime.now().microsecondsSinceEpoch;

    return AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'local-user-access-$issuedAt',
      refreshToken: 'local-user-refresh-$issuedAt',
      userId: 'local-user-$email',
      email: email,
    );
  }
}
