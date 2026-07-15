import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';

void main() {
  test(
    'loads the requested USD rate because currency changes require server proof',
    () async {
      final adapter = _RateAdapter(
        statusCode: 200,
        body: {
          'success': true,
          'data': {
            'base': 'USD',
            'rates': {'EUR': 0.87681},
            'updated_at': '2026-07-14T00:00:00.000Z',
            'stale': false,
          },
        },
      );
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'))
        ..httpClientAdapter = adapter;

      final rate = await HttpCurrencyRateApi(dio).loadUsdRate('EUR');

      expect(rate, 0.87681);
      expect(adapter.path, '/rates');
      expect(adapter.query, {'base': 'USD', 'targets': 'EUR'});
    },
  );

  test(
    'rejects an error envelope because the app must keep its old currency',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'))
        ..httpClientAdapter = _RateAdapter(
          statusCode: 502,
          body: {
            'success': false,
            'error': {
              'code': 'UPSTREAM_ERROR',
              'message': 'Exchange rates are unavailable.',
            },
          },
        );

      await expectLater(
        HttpCurrencyRateApi(dio).loadUsdRate('EUR'),
        throwsA(isA<CurrencyRateApiException>()),
      );
    },
  );
}

class _RateAdapter implements HttpClientAdapter {
  _RateAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;
  String? path;
  Map<String, dynamic>? query;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    query = options.queryParameters;
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
