import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/analytics/mixpanel_bootstrap.dart';

void main() {
  test('retries Mixpanel initialization after 2s, 5s, and 15s', () async {
    var attempts = 0;
    final waits = <Duration>[];

    final client = await initializeMixpanelWithRetry<String>(
      loadToken: () async => 'project-token',
      initialize: (_) async {
        attempts++;
        if (attempts < 4) throw StateError('initialization failed');
        return 'mixpanel-client';
      },
      wait: (delay) async => waits.add(delay),
    );

    expect(client, 'mixpanel-client');
    expect(attempts, 4);
    expect(waits, const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
    ]);
  });

  test('does not retry after the first successful initialization', () async {
    var attempts = 0;
    final waits = <Duration>[];

    final client = await initializeMixpanelWithRetry<String>(
      loadToken: () async => 'project-token',
      initialize: (_) async {
        attempts++;
        return 'mixpanel-client';
      },
      wait: (delay) async => waits.add(delay),
    );

    expect(client, 'mixpanel-client');
    expect(attempts, 1);
    expect(waits, isEmpty);
  });

  test('retries when the project token is temporarily unavailable', () async {
    var tokenLoads = 0;
    var initializations = 0;
    final waits = <Duration>[];

    final client = await initializeMixpanelWithRetry<String>(
      loadToken: () async {
        tokenLoads++;
        return tokenLoads == 1 ? null : 'project-token';
      },
      initialize: (_) async {
        initializations++;
        return 'mixpanel-client';
      },
      wait: (delay) async => waits.add(delay),
    );

    expect(client, 'mixpanel-client');
    expect(tokenLoads, 2);
    expect(initializations, 1);
    expect(waits, const [Duration(seconds: 2)]);
  });

  test('stops after the initial attempt and three retries', () async {
    var attempts = 0;
    final waits = <Duration>[];

    final client = await initializeMixpanelWithRetry<String>(
      loadToken: () async => 'project-token',
      initialize: (_) async {
        attempts++;
        throw StateError('initialization failed');
      },
      wait: (delay) async => waits.add(delay),
    );

    expect(client, isNull);
    expect(attempts, 4);
    expect(waits, mixpanelInitializationRetryDelays);
  });

  test('loads the public Mixpanel token from app config', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'))
      ..httpClientAdapter = _JsonAdapter({
        'success': true,
        'data': {'mixpanel_project_token': ' project-token '},
      });

    final token = await loadMixpanelProjectToken(dio: dio);

    expect(token, 'project-token');
  });

  test('returns null when app config omits the Mixpanel token', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'))
      ..httpClientAdapter = _JsonAdapter({
        'success': true,
        'data': {'mixpanel_project_token': null},
      });

    expect(await loadMixpanelProjectToken(dio: dio), isNull);
  });

  test('returns null when app config cannot be loaded', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'))
      ..httpClientAdapter = _FailingAdapter();

    expect(await loadMixpanelProjectToken(dio: dio), isNull);
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final Object body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}
