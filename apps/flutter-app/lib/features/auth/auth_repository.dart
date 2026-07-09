import 'package:dio/dio.dart';

import 'auth_models.dart';
import 'auth_storage.dart';

const oauthAuthorizationFailedMessage =
    'Authorization failed. Please try again.';
const authApiBaseUrl = String.fromEnvironment(
  'KANDO_API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787/api/v1',
);

Dio createAuthDio({String baseUrl = authApiBaseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
}

class OAuthAuthorizationException implements Exception {
  const OAuthAuthorizationException();

  @override
  String toString() => oauthAuthorizationFailedMessage;
}

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

abstract class AuthRepository {
  Future<AuthSession?> currentSessionFromStorage();
  Future<AuthSession?> previousAnonymousSessionFromStorage();
  Future<AuthSession> createAnonymousSession(String deviceId);
  Future<AuthSession?> validateStoredSession(AuthSession session);
  Future<void> persistSession(AuthSession session);
  Future<void> clearUserSession();
  Future<void> clearAnonymousSession();
  Future<void> deleteCurrentAccount(AuthSession session);
  Future<void> sendRegisterCode(String email);
  Future<AuthSession> verifyRegister({
    required String email,
    required String code,
    required String password,
    String? anonymousId,
  });
  Future<AuthSession> login({required String email, required String password});
  Future<AuthSession> googleCallback({
    required String code,
    required String redirectUri,
    String? anonymousId,
  });
  Future<AuthSession> appleCallback({
    required String code,
    required String idToken,
    String? anonymousId,
  });
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

class HttpAuthRepository implements AuthRepository {
  const HttpAuthRepository(this._dio, this._storage);

  final Dio _dio;
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
    final data = await _requestData(
      'POST',
      '/auth/anonymous',
      body: {'device_id': deviceId},
    );
    return _anonymousSession(data);
  }

  @override
  Future<AuthSession?> validateStoredSession(AuthSession session) async {
    final verified = await _readCurrentSession(session);
    if (verified != null) return verified;

    final refreshed = await _refreshSession(session);
    if (refreshed == null) return null;

    return await _readCurrentSession(refreshed) ?? refreshed;
  }

  @override
  Future<void> persistSession(AuthSession session) {
    return _storage.writeSession(session);
  }

  @override
  Future<void> clearUserSession() async {
    final session = await _storage.readSession();
    if (session?.isUser == true) {
      await _logout(session!);
    }
    await _storage.clearUserSession();
  }

  @override
  Future<void> clearAnonymousSession() async {
    await _storage.clearAnonymousSession();
  }

  @override
  Future<void> deleteCurrentAccount(AuthSession session) async {
    if (session.isUser) {
      await _requestVoid('DELETE', '/auth/account', session: session);
      await _storage.clearUserSession();
      return;
    }
    await _storage.clearAnonymousSession();
  }

  @override
  Future<void> sendRegisterCode(String email) async {
    await _requestVoid(
      'POST',
      '/auth/register/send-code',
      body: {'email': email},
    );
  }

  @override
  Future<AuthSession> verifyRegister({
    required String email,
    required String code,
    required String password,
    String? anonymousId,
  }) async {
    final body = <String, Object?>{
      'email': email,
      'code': code,
      'password': password,
    };
    if (anonymousId != null) {
      body['anonymous_id'] = anonymousId;
    }

    final data = await _requestData(
      'POST',
      '/auth/register/verify',
      body: body,
    );
    return _userSession(data);
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final data = await _requestData(
      'POST',
      '/auth/login',
      body: {'email': email, 'password': password},
    );
    return _userSession(data);
  }

  @override
  Future<AuthSession> googleCallback({
    required String code,
    required String redirectUri,
    String? anonymousId,
  }) {
    return _oauthCallback('/auth/oauth/google/callback', {
      'code': code,
      'redirect_uri': redirectUri,
      if (anonymousId != null) 'anonymous_id': anonymousId,
    });
  }

  @override
  Future<AuthSession> appleCallback({
    required String code,
    required String idToken,
    String? anonymousId,
  }) {
    return _oauthCallback('/auth/oauth/apple/callback', {
      'code': code,
      'id_token': idToken,
      if (anonymousId != null) 'anonymous_id': anonymousId,
    });
  }

  @override
  Future<void> sendForgotPasswordCode(String email) async {
    await _requestVoid(
      'POST',
      '/auth/forgot-password/send-code',
      body: {'email': email},
    );
  }

  @override
  Future<String> verifyForgotPasswordCode({
    required String email,
    required String code,
  }) async {
    final data = await _requestData(
      'POST',
      '/auth/forgot-password/verify-code',
      body: {'email': email, 'code': code},
    );
    return _requiredString(data['reset_token']);
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    await _requestVoid(
      'POST',
      '/auth/forgot-password/reset',
      body: {
        'email': email,
        'reset_token': resetToken,
        'new_password': newPassword,
      },
    );
  }

  Future<AuthSession> _oauthCallback(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final data = await _requestData('POST', path, body: body);
      return _userSession(data);
    } on AuthApiException {
      throw const OAuthAuthorizationException();
    } on DioException {
      throw const OAuthAuthorizationException();
    }
  }

  Future<AuthSession?> _readCurrentSession(AuthSession session) async {
    try {
      final data = await _requestData('GET', '/auth/me', session: session);
      final ownerType = _requiredString(data['owner_type']);
      if (ownerType == 'anonymous') {
        return AuthSession(
          ownerType: OwnerType.anonymous,
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          anonymousId: _nullableString(data['anonymous_id']),
        );
      }
      return AuthSession(
        ownerType: OwnerType.user,
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        userId: _nullableString(data['user_id']),
        email: _nullableString(data['email']),
      );
    } on AuthApiException catch (error) {
      if (error.code == 'UNAUTHORIZED') return null;
      rethrow;
    } on DioException {
      return null;
    }
  }

  Future<AuthSession?> _refreshSession(AuthSession session) async {
    try {
      final data = await _requestData(
        'POST',
        '/auth/token/refresh',
        body: {'refresh_token': session.refreshToken},
      );
      return AuthSession(
        ownerType: session.ownerType,
        accessToken: _requiredString(data['access_token']),
        refreshToken:
            _nullableString(data['refresh_token']) ?? session.refreshToken,
        anonymousId: session.anonymousId,
        userId: session.userId,
        email: session.email,
      );
    } on AuthApiException {
      return null;
    } on DioException {
      return null;
    }
  }

  Future<void> _logout(AuthSession session) async {
    try {
      await _requestVoid(
        'POST',
        '/auth/logout',
        body: {'refresh_token': session.refreshToken},
        session: session,
      );
    } on AuthApiException {
      // Local logout must still clear unusable client state.
    } on DioException {
      // Network logout failure is not allowed to trap the user signed in.
    }
  }

  Future<Map<String, Object?>> _requestData(
    String method,
    String path, {
    Map<String, Object?>? body,
    AuthSession? session,
  }) async {
    final response = await _dio.request<Object?>(
      path,
      data: body,
      options: Options(
        method: method,
        headers: session == null
            ? null
            : {'Authorization': 'Bearer ${session.accessToken}'},
        validateStatus: (_) => true,
      ),
    );
    final envelope = response.data;
    if (envelope is Map && envelope['success'] == true) {
      final data = envelope['data'];
      if (data is Map) {
        return Map<String, Object?>.from(data);
      }
      return <String, Object?>{};
    }

    throw _apiException(envelope);
  }

  Future<void> _requestVoid(
    String method,
    String path, {
    Map<String, Object?>? body,
    AuthSession? session,
  }) async {
    await _requestData(method, path, body: body, session: session);
  }

  AuthApiException _apiException(Object? envelope) {
    if (envelope is Map) {
      final error = envelope['error'];
      if (error is Map) {
        return AuthApiException(
          _nullableString(error['message']) ??
              'Something went wrong. Please try again.',
          code: _nullableString(error['code']),
        );
      }
    }
    return const AuthApiException('Something went wrong. Please try again.');
  }

  AuthSession _anonymousSession(Map<String, Object?> data) {
    return AuthSession(
      ownerType: OwnerType.anonymous,
      accessToken: _requiredString(data['access_token']),
      refreshToken: _requiredString(data['refresh_token']),
      anonymousId: _requiredString(data['anonymous_id']),
    );
  }

  AuthSession _userSession(Map<String, Object?> data) {
    return AuthSession(
      ownerType: OwnerType.user,
      accessToken: _requiredString(data['access_token']),
      refreshToken: _requiredString(data['refresh_token']),
      userId: _requiredString(data['user_id']),
      email: _nullableString(data['email']),
    );
  }

  String _requiredString(Object? value) {
    final normalized = _nullableString(value);
    if (normalized == null) {
      throw const AuthApiException('Something went wrong. Please try again.');
    }
    return normalized;
  }

  String? _nullableString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
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
  Future<void> deleteCurrentAccount(AuthSession session) {
    if (session.isUser) {
      return _storage.clearUserSession();
    }
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
  Future<AuthSession> googleCallback({
    required String code,
    required String redirectUri,
    String? anonymousId,
  }) async {
    if (redirectUri.isEmpty) {
      throw const OAuthAuthorizationException();
    }
    final identity = _parseMockIdentity(code, 'mock-google');
    return _userSession(identity.email, userId: identity.providerUid);
  }

  @override
  Future<AuthSession> appleCallback({
    required String code,
    required String idToken,
    String? anonymousId,
  }) async {
    if (code.isEmpty) {
      throw const OAuthAuthorizationException();
    }
    final identity = _parseMockIdentity(idToken, 'mock-apple');
    return _userSession(identity.email, userId: identity.providerUid);
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

  AuthSession _userSession(String email, {String? userId}) {
    final issuedAt = DateTime.now().microsecondsSinceEpoch;

    return AuthSession(
      ownerType: OwnerType.user,
      accessToken: 'local-user-access-$issuedAt',
      refreshToken: 'local-user-refresh-$issuedAt',
      userId: userId ?? 'local-user-$email',
      email: email,
    );
  }

  _MockOAuthIdentity _parseMockIdentity(String value, String prefix) {
    final parts = value.split(':');
    if (parts.length != 3 ||
        parts[0] != prefix ||
        parts[1].isEmpty ||
        parts[2].isEmpty ||
        !parts[2].contains('@')) {
      throw const OAuthAuthorizationException();
    }

    return _MockOAuthIdentity(providerUid: parts[1], email: parts[2]);
  }
}

class _MockOAuthIdentity {
  const _MockOAuthIdentity({required this.providerUid, required this.email});

  final String providerUid;
  final String email;
}
