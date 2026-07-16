import 'dart:async';

import 'package:dio/dio.dart';

import 'auth_models.dart';
import 'auth_storage.dart';

class AuthSessionInterceptor extends Interceptor {
  AuthSessionInterceptor({required Dio dio, required AuthStorage storage})
    : _dio = dio,
      _storage = storage;

  static const _retriedKey = 'auth_session_retried';

  final Dio _dio;
  final AuthStorage _storage;
  Future<AuthSession?>? _refreshing;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(_attachCurrentToken(options, handler));
  }

  Future<void> _attachCurrentToken(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_hasBearerToken(options)) {
      final session = await _storage.readSession();
      if (session != null) {
        options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    unawaited(_retryUnauthorized(response, handler));
  }

  Future<void> _retryUnauthorized(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final options = response.requestOptions;
    if (response.statusCode != 401 ||
        options.extra[_retriedKey] == true ||
        !_hasBearerToken(options)) {
      handler.next(response);
      return;
    }

    final session = await _refreshSession();
    if (session == null) {
      handler.next(response);
      return;
    }

    options.extra[_retriedKey] = true;
    options.headers['Authorization'] = 'Bearer ${session.accessToken}';
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (error) {
      handler.reject(error);
    }
  }

  Future<AuthSession?> _refreshSession() async {
    final activeRefresh = _refreshing;
    if (activeRefresh != null) return activeRefresh;

    final refresh = _performRefresh();
    _refreshing = refresh;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshing, refresh)) {
        _refreshing = null;
      }
    }
  }

  Future<AuthSession?> _performRefresh() async {
    final session = await _storage.readSession();
    if (session == null) return null;

    try {
      final response = await _dio.post<Object?>(
        '/auth/token/refresh',
        data: {'refresh_token': session.refreshToken},
        options: Options(validateStatus: (_) => true),
      );
      final envelope = response.data;
      if (envelope is! Map || envelope['success'] != true) return null;
      final data = envelope['data'];
      if (data is! Map) return null;
      final accessToken = _nonEmptyString(data['access_token']);
      if (accessToken == null) return null;

      final latestSession = await _storage.readSession();
      if (latestSession?.refreshToken != session.refreshToken) {
        return latestSession;
      }

      final refreshed = AuthSession(
        ownerType: session.ownerType,
        accessToken: accessToken,
        refreshToken:
            _nonEmptyString(data['refresh_token']) ?? session.refreshToken,
        anonymousId: session.anonymousId,
        userId: session.userId,
        email: session.email,
        loginMethod: session.loginMethod,
      );
      await _storage.writeSession(refreshed);
      return refreshed;
    } on DioException {
      return null;
    }
  }

  bool _hasBearerToken(RequestOptions options) {
    final authorization = options.headers['Authorization'];
    return authorization is String && authorization.startsWith('Bearer ');
  }
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
