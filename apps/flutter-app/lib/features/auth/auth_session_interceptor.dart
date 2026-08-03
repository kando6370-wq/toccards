import 'dart:async';

import 'package:dio/dio.dart';

import 'auth_models.dart';
import 'auth_storage.dart';

class AuthSessionInterceptor extends Interceptor {
  AuthSessionInterceptor({required Dio dio, required AuthStorage storage})
    : _dio = dio,
      _storage = storage;

  static const _retriedKey = 'auth_session_retried';
  static const _requestRefreshTokenKey = 'auth_session_refresh_token';

  final Dio _dio;
  final AuthStorage _storage;
  Future<AuthSession?>? _refreshing;
  String? _refreshingRefreshToken;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(_attachCurrentToken(options, handler));
  }

  Future<void> _attachCurrentToken(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final accessToken = _bearerAccessToken(options);
    if (accessToken != null) {
      final session = await _storage.readSession();
      if (session?.accessToken == accessToken) {
        options.extra[_requestRefreshTokenKey] = session!.refreshToken;
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

    final requestRefreshToken = options.extra[_requestRefreshTokenKey];
    final currentSession = await _storage.readSession();
    if (requestRefreshToken is! String ||
        currentSession?.refreshToken != requestRefreshToken) {
      handler.next(response);
      return;
    }

    final session = await _refreshSession(currentSession!);
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

  Future<AuthSession?> _refreshSession(AuthSession session) async {
    final activeRefresh = _refreshing;
    if (activeRefresh != null &&
        _refreshingRefreshToken == session.refreshToken) {
      return activeRefresh;
    }

    final refresh = _performRefresh(session);
    _refreshing = refresh;
    _refreshingRefreshToken = session.refreshToken;
    try {
      return await refresh;
    } finally {
      if (identical(_refreshing, refresh)) {
        _refreshing = null;
        _refreshingRefreshToken = null;
      }
    }
  }

  Future<AuthSession?> _performRefresh(AuthSession session) async {
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
        return null;
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
    return _bearerAccessToken(options) != null;
  }

  String? _bearerAccessToken(RequestOptions options) {
    final authorization = options.headers['Authorization'];
    if (authorization is! String || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final token = authorization.substring('Bearer '.length).trim();
    return token.isEmpty ? null : token;
  }
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
