import 'package:dio/dio.dart';

import '../../shared/api/api_environment.dart';
import 'auth_models.dart';
import 'auth_storage.dart';

const oauthAuthorizationFailedMessage =
    'Authorization failed. Please try again.';
const authApiBaseUrl = kandoApiBaseUrl;

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

class AuthNetworkException implements Exception {
  const AuthNetworkException();
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
  Future<void> verifyRegisterCode({
    required String email,
    required String code,
  });
  Future<AuthSession> verifyRegister({
    required String email,
    required String code,
    required String password,
    String? anonymousId,
  });
  Future<AuthSession> login({required String email, required String password});
  Future<AuthSession> googleCallback({
    required String idToken,
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
  final AuthStorage _storage;

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
    await _requestVoid('DELETE', '/auth/account', session: session);
    if (session.isUser) {
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
  Future<void> verifyRegisterCode({
    required String email,
    required String code,
  }) async {
    await _requestVoid(
      'POST',
      '/auth/register/verify-code',
      body: {'email': email, 'code': code},
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
    required String idToken,
    String? anonymousId,
  }) async {
    final anonymousSession = await _storage.readSession();
    return _oauthCallback(
      '/auth/oauth/google/callback',
      {
        'id_token': idToken,
        if (anonymousId != null) 'anonymous_id': anonymousId,
      },
      session: anonymousSession?.isAnonymous == true ? anonymousSession : null,
    );
  }

  @override
  Future<AuthSession> appleCallback({
    required String code,
    required String idToken,
    String? anonymousId,
  }) async {
    final anonymousSession = await _storage.readSession();
    return _oauthCallback(
      '/auth/oauth/apple/callback',
      {
        'code': code,
        'id_token': idToken,
        if (anonymousId != null) 'anonymous_id': anonymousId,
      },
      session: anonymousSession?.isAnonymous == true ? anonymousSession : null,
    );
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
    Map<String, Object?> body, {
    AuthSession? session,
  }) async {
    try {
      final data = await _requestData(
        'POST',
        path,
        body: body,
        session: session,
      );
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
        loginMethod: _loginMethod(data['login_method']),
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
        loginMethod: session.loginMethod,
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
    } on DioException {
      throw const AuthNetworkException();
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
      loginMethod: _requiredLoginMethod(data['login_method']),
    );
  }

  LoginMethod _requiredLoginMethod(Object? value) {
    final method = _loginMethod(value);
    if (method == null) {
      throw const AuthApiException('Something went wrong. Please try again.');
    }
    return method;
  }

  LoginMethod? _loginMethod(Object? value) {
    return switch (_nullableString(value)) {
      'email' => LoginMethod.email,
      'google' => LoginMethod.google,
      'apple' => LoginMethod.apple,
      _ => null,
    };
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
