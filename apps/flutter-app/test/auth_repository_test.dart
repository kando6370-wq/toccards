import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

import 'support/in_memory_auth_storage.dart';

void main() {
  test(
    'creates a backend anonymous session because asset APIs require a signed owner token',
    () async {
      final adapter = _FakeAuthAdapter({
        'POST /auth/anonymous': _ok({
          'anonymous_id': 'anon-1',
          'access_token': 'anon-access',
          'refresh_token': 'anon-refresh',
          'expires_in': 900,
        }),
      });
      final repository = HttpAuthRepository(
        _dio(adapter),
        InMemoryAuthStorage(),
      );

      final session = await repository.createAnonymousSession('device-1');

      expect(session.ownerType, OwnerType.anonymous);
      expect(session.anonymousId, 'anon-1');
      expect(session.accessToken, 'anon-access');
      expect(session.refreshToken, 'anon-refresh');
      expect(adapter.requests.single.body, {'device_id': 'device-1'});
    },
  );

  test(
    'validates stored sessions with auth me because local tokens alone are not proof of identity',
    () async {
      final stored = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'stored-access',
        refreshToken: 'stored-refresh',
        userId: 'stale-user',
      );
      final adapter = _FakeAuthAdapter({
        'GET /auth/me': _ok({
          'owner_type': 'user',
          'user_id': 'user-1',
          'anonymous_id': null,
          'email': 'person@example.com',
          'login_method': 'google',
          'display_name': null,
          'created_at': '2026-07-09T00:00:00.000Z',
        }),
      });
      final repository = HttpAuthRepository(
        _dio(adapter),
        InMemoryAuthStorage(),
      );

      final session = await repository.validateStoredSession(stored);

      expect(session!.ownerType, OwnerType.user);
      expect(session.userId, 'user-1');
      expect(session.email, 'person@example.com');
      expect(session.loginMethod, LoginMethod.google);
      expect(session.accessToken, 'stored-access');
      expect(adapter.requests.single.authorization, 'Bearer stored-access');
    },
  );

  test(
    'refreshes stale access tokens because returning users should not lose sessions on expiry',
    () async {
      final stored = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'expired-access',
        refreshToken: 'stored-refresh',
        userId: 'user-1',
        email: 'person@example.com',
      );
      final adapter = _FakeAuthAdapter({
        'GET /auth/me': _Response(401, {
          'success': false,
          'error': {'code': 'UNAUTHORIZED', 'message': 'Unauthorized.'},
        }),
        'POST /auth/token/refresh': _ok({
          'access_token': 'fresh-access',
          'refresh_token': 'fresh-refresh',
          'expires_in': 900,
        }),
      });
      final repository = HttpAuthRepository(
        _dio(adapter),
        InMemoryAuthStorage(),
      );

      final session = await repository.validateStoredSession(stored);

      expect(session!.accessToken, 'fresh-access');
      expect(session.refreshToken, 'fresh-refresh');
      expect(session.userId, 'user-1');
      final refreshRequest = adapter.requests.firstWhere(
        (request) => request.key == 'POST /auth/token/refresh',
      );
      expect(refreshRequest.body, {'refresh_token': 'stored-refresh'});
    },
  );

  test(
    'logs in through the backend because user sessions must be server-issued',
    () async {
      final adapter = _FakeAuthAdapter({
        'POST /auth/login': _ok({
          'user_id': 'user-1',
          'email': 'person@example.com',
          'login_method': 'email',
          'access_token': 'user-access',
          'refresh_token': 'user-refresh',
          'expires_in': 900,
        }),
      });
      final repository = HttpAuthRepository(
        _dio(adapter),
        InMemoryAuthStorage(),
      );

      final session = await repository.login(
        email: 'person@example.com',
        password: 'password123',
      );

      expect(session.ownerType, OwnerType.user);
      expect(session.userId, 'user-1');
      expect(session.email, 'person@example.com');
      expect(session.loginMethod, LoginMethod.email);
      expect(adapter.requests.single.body, {
        'email': 'person@example.com',
        'password': 'password123',
      });
    },
  );

  test(
    'registration proves guest ownership because only that guest assets may migrate',
    () async {
      final storage = InMemoryAuthStorage();
      await storage.writeSession(
        const AuthSession(
          ownerType: OwnerType.anonymous,
          accessToken: 'anon-access',
          refreshToken: 'anon-refresh',
          anonymousId: 'anon-1',
        ),
      );
      final adapter = _FakeAuthAdapter({
        'POST /auth/register/verify': _ok({
          'user_id': 'user-1',
          'email': 'person@example.com',
          'login_method': 'email',
          'access_token': 'user-access',
          'refresh_token': 'user-refresh',
        }),
      });
      final repository = HttpAuthRepository(_dio(adapter), storage);

      await repository.verifyRegister(
        email: 'person@example.com',
        code: '123456',
        password: 'password123',
        anonymousId: 'anon-1',
      );

      expect(adapter.requests.single.body, {
        'email': 'person@example.com',
        'code': '123456',
        'password': 'password123',
        'anonymous_id': 'anon-1',
      });
      expect(adapter.requests.single.authorization, 'Bearer anon-access');
    },
  );

  test(
    'google callback proves guest ownership because new OAuth users may migrate only their own assets',
    () async {
      final storage = InMemoryAuthStorage();
      await storage.writeSession(
        const AuthSession(
          ownerType: OwnerType.anonymous,
          accessToken: 'anon-access',
          refreshToken: 'anon-refresh',
          anonymousId: 'anon-1',
        ),
      );
      final adapter = _FakeAuthAdapter({
        'POST /auth/oauth/google/callback': _ok({
          'user_id': 'user-1',
          'email': 'person@example.com',
          'login_method': 'google',
          'access_token': 'user-access',
          'refresh_token': 'user-refresh',
        }),
      });
      final repository = HttpAuthRepository(_dio(adapter), storage);

      final session = await repository.googleCallback(
        idToken: 'google-id-token',
        anonymousId: 'anon-1',
      );

      expect(adapter.requests.single.body, {
        'id_token': 'google-id-token',
        'anonymous_id': 'anon-1',
      });
      expect(adapter.requests.single.authorization, 'Bearer anon-access');
      expect(session.loginMethod, LoginMethod.google);
    },
  );

  test(
    'logout keeps the stored user when the network fails because offline logout must not change account state',
    () async {
      final storage = InMemoryAuthStorage();
      const user = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'user-access',
        refreshToken: 'user-refresh',
        userId: 'user-1',
      );
      await storage.writeSession(user);
      final repository = HttpAuthRepository(
        _dio(_FakeAuthAdapter({'POST /auth/logout': _NetworkFailure()})),
        storage,
      );

      await expectLater(
        repository.clearUserSession(),
        throwsA(isA<AuthNetworkException>()),
      );

      expect(await storage.readSession(), same(user));
    },
  );

  test(
    'deletes an anonymous account through the backend because guest cloud assets must be removed too',
    () async {
      final storage = InMemoryAuthStorage();
      const guest = AuthSession(
        ownerType: OwnerType.anonymous,
        accessToken: 'anon-access',
        refreshToken: 'anon-refresh',
        anonymousId: 'anon-1',
      );
      await storage.writeSession(guest);
      final adapter = _FakeAuthAdapter({
        'DELETE /auth/account': _ok(<String, Object?>{}),
      });
      final repository = HttpAuthRepository(_dio(adapter), storage);

      await repository.deleteCurrentAccount(guest);

      expect(adapter.requests.single.authorization, 'Bearer anon-access');
      expect(await storage.readSession(), isNull);
    },
  );

  test(
    'keeps an anonymous session when backend deletion fails because the user must be able to retry',
    () async {
      final storage = InMemoryAuthStorage();
      const guest = AuthSession(
        ownerType: OwnerType.anonymous,
        accessToken: 'anon-access',
        refreshToken: 'anon-refresh',
        anonymousId: 'anon-1',
      );
      await storage.writeSession(guest);
      final repository = HttpAuthRepository(
        _dio(
          _FakeAuthAdapter({
            'DELETE /auth/account': _Response(500, {
              'success': false,
              'error': {
                'code': 'INTERNAL_ERROR',
                'message': 'Unable to complete this action.',
              },
            }),
          }),
        ),
        storage,
      );

      await expectLater(
        repository.deleteCurrentAccount(guest),
        throwsA(isA<AuthApiException>()),
      );

      expect(await storage.readSession(), same(guest));
    },
  );
}

Dio _dio(_FakeAuthAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
  dio.httpClientAdapter = adapter;
  return dio;
}

_Response _ok(Map<String, Object?> data) {
  return _Response(200, {'success': true, 'data': data});
}

class _FakeAuthAdapter implements HttpClientAdapter {
  _FakeAuthAdapter(this.responses);

  final Map<String, Object> responses;
  final List<_RecordedRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = await _decodeBody(requestStream) ?? options.data;
    final key = '${options.method} ${options.path}';
    requests.add(
      _RecordedRequest(
        key: key,
        body: body,
        authorization: options.headers['Authorization']?.toString(),
      ),
    );
    final response = responses[key];
    if (response is _NetworkFailure) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    if (response == null) {
      return ResponseBody.fromString(
        jsonEncode({
          'success': false,
          'error': {'code': 'NOT_FOUND', 'message': key},
        }),
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode((response as _Response).body),
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<Object?> _decodeBody(Stream<Uint8List>? requestStream) async {
  if (requestStream == null) return null;
  final bytes = <int>[];
  await for (final chunk in requestStream) {
    bytes.addAll(chunk);
  }
  if (bytes.isEmpty) return null;
  return jsonDecode(utf8.decode(bytes));
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final Map<String, Object?> body;
}

class _NetworkFailure {
  const _NetworkFailure();
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.key,
    required this.body,
    required this.authorization,
  });

  final String key;
  final Object? body;
  final String? authorization;
}
