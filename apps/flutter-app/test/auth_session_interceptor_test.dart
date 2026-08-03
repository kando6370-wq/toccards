import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_session_interceptor.dart';
import 'package:kando_app/features/auth/auth_storage.dart';

void main() {
  test(
    'refreshes and retries once because an active app session must survive the 15 minute access-token lifetime',
    () async {
      final storage = _MemoryAuthStorage(_session('expired-access'));
      final adapter = _AuthRetryAdapter(refreshSucceeds: true);
      final dio = _dio(adapter, storage);

      final response = await dio.get<Object?>(
        '/portfolio/items',
        options: Options(
          headers: {'Authorization': 'Bearer expired-access'},
          validateStatus: (_) => true,
        ),
      );

      expect(response.statusCode, 200);
      expect(adapter.paths, [
        '/api/v1/portfolio/items',
        '/api/v1/auth/token/refresh',
        '/api/v1/portfolio/items',
      ]);
      expect(adapter.authorizationHeaders, [
        'Bearer expired-access',
        null,
        'Bearer refreshed-access',
      ]);
      expect(storage.session?.accessToken, 'refreshed-access');
    },
  );

  test(
    'returns the original unauthorized response when refresh fails because retry must not loop',
    () async {
      final storage = _MemoryAuthStorage(_session('expired-access'));
      final adapter = _AuthRetryAdapter(refreshSucceeds: false);
      final dio = _dio(adapter, storage);

      final response = await dio.get<Object?>(
        '/wishlist',
        options: Options(
          headers: {'Authorization': 'Bearer expired-access'},
          validateStatus: (_) => true,
        ),
      );

      expect(response.statusCode, 401);
      expect(adapter.paths, ['/api/v1/wishlist', '/api/v1/auth/token/refresh']);
      expect(storage.session?.accessToken, 'expired-access');
    },
  );

  test(
    'uses the latest token for the same owner because one parallel request may refresh before another starts',
    () async {
      final oldAccess = _jwt(ownerId: 'anon-1', sessionId: 'session-old');
      final currentAccess = _jwt(
        ownerId: 'anon-1',
        sessionId: 'session-current',
      );
      final storage = _MemoryAuthStorage(_session(currentAccess));
      final adapter = _AuthRetryAdapter(
        refreshSucceeds: true,
        acceptedAccessToken: currentAccess,
      );
      final dio = _dio(adapter, storage);

      final response = await dio.get<Object?>(
        '/collection/dashboard',
        options: Options(
          headers: {'Authorization': 'Bearer $oldAccess'},
          validateStatus: (_) => true,
        ),
      );

      expect(response.statusCode, 200);
      expect(adapter.paths, ['/api/v1/collection/dashboard']);
      expect(adapter.authorizationHeaders, ['Bearer $currentAccess']);
    },
  );

  test(
    'keeps the request session when storage changed because owner-scoped data must not be sent with another account token',
    () async {
      final oldAccess = _jwt(ownerId: 'anon-1', sessionId: 'session-old');
      final newAccess = _jwt(ownerId: 'anon-2', sessionId: 'session-new');
      final storage = _MemoryAuthStorage(
        _session(
          newAccess,
          refreshToken: 'new-owner-refresh',
          anonymousId: 'anon-2',
        ),
      );
      final adapter = _AuthRetryAdapter(refreshSucceeds: true);
      final dio = _dio(adapter, storage);

      final response = await dio.post<Object?>(
        '/cards/663187/collect',
        data: {'folder_id': 'old-owner-folder'},
        options: Options(
          headers: {'Authorization': 'Bearer $oldAccess'},
          validateStatus: (_) => true,
        ),
      );

      expect(response.statusCode, 401);
      expect(adapter.paths, ['/api/v1/cards/663187/collect']);
      expect(adapter.authorizationHeaders, ['Bearer $oldAccess']);
      expect(storage.session?.accessToken, newAccess);
    },
  );
}

Dio _dio(_AuthRetryAdapter adapter, AuthStorage storage) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(AuthSessionInterceptor(dio: dio, storage: storage));
  return dio;
}

AuthSession _session(
  String accessToken, {
  String refreshToken = 'refresh-token',
  String anonymousId = 'anon-1',
}) {
  return AuthSession(
    ownerType: OwnerType.anonymous,
    accessToken: accessToken,
    refreshToken: refreshToken,
    anonymousId: anonymousId,
  );
}

class _MemoryAuthStorage implements AuthStorage {
  _MemoryAuthStorage(this.session);

  AuthSession? session;

  @override
  Future<AuthSession?> readSession() async => session;

  @override
  Future<void> writeSession(AuthSession session) async {
    this.session = session;
  }

  @override
  Future<AuthSession?> readPreviousAnonymousSession() async => null;

  @override
  Future<void> clearAnonymousSession() async => session = null;

  @override
  Future<void> clearUserSession() async => session = null;

  @override
  Future<String> readOrCreateDeviceId() async => 'device-1';
}

class _AuthRetryAdapter implements HttpClientAdapter {
  _AuthRetryAdapter({
    required this.refreshSucceeds,
    this.acceptedAccessToken = 'refreshed-access',
  });

  final bool refreshSucceeds;
  final String acceptedAccessToken;
  final List<String> paths = [];
  final List<String?> authorizationHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.uri.path);
    authorizationHeaders.add(options.headers['Authorization'] as String?);

    if (options.uri.path.endsWith('/auth/token/refresh')) {
      return _json(
        refreshSucceeds
            ? {
                'success': true,
                'data': {'access_token': 'refreshed-access'},
              }
            : {
                'success': false,
                'error': {'code': 'UNAUTHORIZED'},
              },
        refreshSucceeds ? 200 : 401,
      );
    }
    if (options.headers['Authorization'] == 'Bearer $acceptedAccessToken') {
      return _json({'success': true, 'data': {}}, 200);
    }
    return _json({
      'success': false,
      'error': {'code': 'UNAUTHORIZED'},
    }, 401);
  }

  ResponseBody _json(Object body, int statusCode) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _jwt({required String ownerId, required String sessionId}) {
  String encode(Object value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'owner_type': 'anonymous', 'owner_id': ownerId, 'session_id': sessionId})}.'
      'signature';
}
