import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';

void main() {
  test(
    'searchCards maps Workers catalog rows because Search must read the real card catalog',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/cards/search');
        expect(request.queryParameters, {'q': 'pikachu', 'page_size': '40'});
        return _json(200, {
          'success': true,
          'data': {
            'items': [_cardJson(cardRef: 'catalog:pikachu-025')],
          },
        });
      });

      final cards = await CardDataApiClient(
        _dio(adapter),
      ).searchCards('pikachu');

      expect(cards.single.cardRef, 'catalog:pikachu-025');
      expect(cards.single.name, 'Pikachu');
      expect(cards.single.game, 'Pokemon');
      expect(cards.single.setName, 'Base Set');
      expect(cards.single.objectType, 'tcg');
    },
  );

  test(
    'getPriceSeries sends market qualifiers because Card Detail charts are condition specific',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/cards/catalog%3Apikachu-025/price-series');
        expect(request.queryParameters, {
          'days': '30',
          'grader': 'Raw',
          'condition': 'Near Mint',
        });
        return _json(200, {
          'success': true,
          'data': {
            'series': [
              {'date': '2026-06-10', 'price': 12.5},
              {'date': '2026-07-10', 'price': 15},
            ],
          },
        });
      });

      final series = await CardDataApiClient(
        _dio(adapter),
      ).getPriceSeries('catalog:pikachu-025', days: 30, condition: 'Near Mint');

      expect(series.first.date, '2026-06-10');
      expect(series.last.price, 15);
    },
  );

  test(
    'searchCards accepts an empty card number because the D1 catalog does not invent identifiers',
    () async {
      final adapter = _RecordingAdapter((request) {
        return _json(200, {
          'success': true,
          'data': {
            'items': [_cardJson(cardRef: '9359', cardNumber: '')],
          },
        });
      });

      final cards = await CardDataApiClient(
        _dio(adapter),
      ).searchCards('escape');

      expect(cards.single.cardNumber, isEmpty);
    },
  );

  test(
    'getMarketPrices rejects malformed rows because silently dropping prices would hide backend contract drift',
    () async {
      final adapter = _RecordingAdapter((request) {
        return _json(200, {
          'success': true,
          'data': {
            'prices': ['not-an-object'],
          },
        });
      });

      expect(
        CardDataApiClient(_dio(adapter)).getMarketPrices('catalog:pikachu-025'),
        throwsA(isA<CardDataApiException>()),
      );
    },
  );
}

Dio _dio(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Map<String, Object?> _cardJson({
  required String cardRef,
  String cardNumber = '025',
}) {
  return {
    'card_ref': cardRef,
    'name': 'Pikachu',
    'game': 'Pokemon',
    'set_name': 'Base Set',
    'set_code': 'BS',
    'card_number': cardNumber,
    'finish': 'Holofoil',
    'language': 'English',
    'object_type': 'tcg',
    'image_url': 'https://img.example/pikachu.jpg',
    'rarity': 'Common',
  };
}

ResponseBody _json(int statusCode, Map<String, Object?> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final ResponseBody Function(_RecordedRequest request) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(
      _RecordedRequest(
        method: options.method,
        path: options.path,
        queryParameters: options.queryParameters.map(
          (key, value) => MapEntry(key, value.toString()),
        ),
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
  });

  final String method;
  final String path;
  final Map<String, String> queryParameters;
}
