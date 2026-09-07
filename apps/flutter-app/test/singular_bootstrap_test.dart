import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/attribution/singular_bootstrap.dart';

void main() {
  test('loads Singular SDK credentials from app config', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'))
      ..httpClientAdapter = _JsonAdapter({
        'success': true,
        'data': {
          'singular_api_key': ' api-key ',
          'singular_secret_key': ' secret-key ',
        },
      });

    final credentials = await loadSingularCredentials(dio: dio);

    expect(credentials?.apiKey, 'api-key');
    expect(credentials?.secretKey, 'secret-key');
  });

  test('returns null when either Singular credential is missing', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'))
      ..httpClientAdapter = _JsonAdapter({
        'success': true,
        'data': {'singular_api_key': 'api-key', 'singular_secret_key': null},
      });

    expect(await loadSingularCredentials(dio: dio), isNull);
  });

  test('returns null when app config cannot be loaded', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'))
      ..httpClientAdapter = _FailingAdapter();

    expect(await loadSingularCredentials(dio: dio), isNull);
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
