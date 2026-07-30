import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/analytics/mixpanel_bootstrap.dart';

void main() {
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
