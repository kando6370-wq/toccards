import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/api/api_request_executor.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';

const _immediateReadRetryPolicy = ApiRetryPolicy(
  maxAttempts: 2,
  baseDelay: Duration.zero,
  maxDelay: Duration.zero,
  jitterRatio: 0,
);

void main() {
  test(
    'trendingCardPage sends unified pagination because View all must load beyond the Home preview',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/cards/trending');
        expect(request.queryParameters, {'page': '2', 'page_size': '40'});
        return _json(200, {
          'success': true,
          'data': {
            'items': [_cardJson(cardRef: 'trending-page-2')],
          },
        });
      });

      final cards = await CardDataApiClient(
        _dio(adapter),
      ).trendingCardPage(page: 2);

      expect(cards.single.cardRef, 'trending-page-2');
    },
  );

  test(
    'searchCards maps Workers catalog rows because Search must read the real card catalog',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/cards/search');
        expect(request.queryParameters, {
          'q': 'pikachu',
          'game': 'Pokemon',
          'page': '1',
          'page_size': '40',
        });
        return _json(200, {
          'success': true,
          'data': {
            'items': [_cardJson(cardRef: 'catalog:pikachu-025')],
          },
        });
      });

      final cards = await CardDataApiClient(
        _dio(adapter),
      ).searchCards('pikachu', game: 'Pokemon');

      expect(cards.single.cardRef, 'catalog:pikachu-025');
      expect(cards.single.name, 'Pikachu');
      expect(cards.single.game, 'Pokemon');
      expect(cards.single.setName, 'Base Set');
      expect(cards.single.objectType, 'tcg');
      expect(cards.single.priceUsd, 32.13);
      expect(cards.single.previous30dPriceUsd, 30.67);
      expect(cards.single.previous7dPriceUsd, 31.05);
      expect(cards.single.previous1dPriceUsd, 31.25);
      expect(cards.single.priceChange30dPercent, 4.761);
      expect(cards.single.priceChange7dPercent, 3.478);
      expect(cards.single.priceChange1dPercent, 2.816);
      expect(cards.single.priceAsOf, '2026-07-15');
      expect(cards.single.previousPriceAsOf, '2026-07-14');
      expect(cards.single.availableLanguages, ['English', 'Japanese']);
      expect(cards.single.availableFinishes, ['Holofoil', 'Normal']);
    },
  );

  test(
    'search has one total deadline so a late catalog response cannot overwrite the current query',
    () async {
      final adapter = _RecordingAdapter((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return _json(200, {
          'success': true,
          'data': {
            'items': [_cardJson(cardRef: 'late-result')],
          },
        });
      });

      await expectLater(
        CardDataApiClient(
          _dio(adapter),
          requestDeadline: const Duration(milliseconds: 20),
        ).searchCards('old query'),
        throwsA(
          isA<CardDataApiException>()
              .having((error) => error.code, 'code', cardDataRequestTimeoutCode)
              .having(
                (error) => error.message,
                'message',
                cardDataRequestTimeoutMessage,
              ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test(
    'a transient GET failure retries once within the same operation',
    () async {
      var calls = 0;
      final adapter = _RecordingAdapter((_) {
        calls += 1;
        if (calls == 1) {
          return _json(503, {
            'success': false,
            'error': {'code': 'SERVICE_UNAVAILABLE'},
          });
        }
        return _json(200, {
          'success': true,
          'data': {
            'items': [_cardJson(cardRef: 'retry-result')],
          },
        });
      });

      final cards = await CardDataApiClient(
        _dio(adapter),
        readRetryPolicy: _immediateReadRetryPolicy,
      ).searchCards('retry');

      expect(calls, 2);
      expect(adapter.requests.map((request) => request.attempt), [1, 2]);
      expect(cards.single.cardRef, 'retry-result');
    },
  );

  for (final statusCode in [409, 422]) {
    test(
      '$statusCode is not retried because it is a business response',
      () async {
        var calls = 0;
        final adapter = _RecordingAdapter((_) {
          calls += 1;
          return _json(statusCode, {
            'success': false,
            'error': {
              'code': statusCode == 409
                  ? 'ENTITLEMENT_SYNC_REQUIRED'
                  : 'INVALID_REQUEST',
            },
          });
        });

        await expectLater(
          CardDataApiClient(
            _dio(adapter),
            readRetryPolicy: _immediateReadRetryPolicy,
          ).searchCards('business-error'),
          throwsA(
            isA<CardDataApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              statusCode,
            ),
          ),
        );

        expect(calls, 1);
      },
    );
  }

  test(
    'POST is not retried after 503 because writes require explicit policy',
    () async {
      var calls = 0;
      final adapter = _RecordingAdapter((_) {
        calls += 1;
        return _json(503, {
          'success': false,
          'error': {'code': 'SERVICE_UNAVAILABLE'},
        });
      });

      await expectLater(
        CardDataApiClient(
          _dio(adapter),
          readRetryPolicy: _immediateReadRetryPolicy,
        ).getPriceSeriesBatch('card-1', const [
          CardDataPriceSeriesQuery(days: 30, grader: 'Raw'),
        ]),
        throwsA(
          isA<CardDataApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );

      expect(calls, 1);
    },
  );

  test('a retried GET shares the original total deadline', () async {
    var calls = 0;
    final adapter = _RecordingAdapter((_) async {
      calls += 1;
      if (calls == 1) {
        return _json(503, {
          'success': false,
          'error': {'code': 'SERVICE_UNAVAILABLE'},
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return _json(200, {
        'success': true,
        'data': {
          'items': [_cardJson(cardRef: 'too-late')],
        },
      });
    });

    await expectLater(
      CardDataApiClient(
        _dio(adapter),
        requestDeadline: const Duration(milliseconds: 20),
        readRetryPolicy: _immediateReadRetryPolicy,
      ).searchCards('deadline'),
      throwsA(
        isA<CardDataApiException>().having(
          (error) => error.code,
          'code',
          cardDataRequestTimeoutCode,
        ),
      ),
    );

    expect(calls, 2);
  });

  test('identical in-flight GETs share one transport request', () async {
    final response = Completer<ResponseBody>();
    final requestStarted = Completer<void>();
    var calls = 0;
    final adapter = _RecordingAdapter((_) {
      calls += 1;
      if (!requestStarted.isCompleted) requestStarted.complete();
      return response.future;
    });
    final client = CardDataApiClient(
      _dio(adapter),
      readRetryPolicy: ApiRetryPolicy.none,
    );

    final first = client.searchCards('pikachu', game: 'Pokemon');
    final second = client.searchCards('pikachu', game: 'Pokemon');
    await requestStarted.future;

    expect(calls, 1);
    response.complete(
      _json(200, {
        'success': true,
        'data': {
          'items': [_cardJson(cardRef: 'shared-result')],
        },
      }),
    );

    expect((await first).single.cardRef, 'shared-result');
    expect((await second).single.cardRef, 'shared-result');
  });

  test('different GET query parameters are never coalesced', () async {
    var calls = 0;
    final adapter = _RecordingAdapter((request) {
      calls += 1;
      return _json(200, {
        'success': true,
        'data': {
          'items': [
            _cardJson(cardRef: request.queryParameters['q'] ?? 'missing'),
          ],
        },
      });
    });
    final client = CardDataApiClient(
      _dio(adapter),
      readRetryPolicy: ApiRetryPolicy.none,
    );

    final results = await Future.wait([
      client.searchCards('pikachu'),
      client.searchCards('charizard'),
    ]);

    expect(calls, 2);
    expect(results.map((cards) => cards.single.cardRef), [
      'pikachu',
      'charizard',
    ]);
  });

  test('a failed coalesced GET is removed before the next request', () async {
    var calls = 0;
    final adapter = _RecordingAdapter((_) {
      calls += 1;
      if (calls == 1) {
        return _json(422, {
          'success': false,
          'error': {'code': 'INVALID_REQUEST'},
        });
      }
      return _json(200, {
        'success': true,
        'data': {
          'items': [_cardJson(cardRef: 'recovered')],
        },
      });
    });
    final client = CardDataApiClient(
      _dio(adapter),
      readRetryPolicy: ApiRetryPolicy.none,
    );

    await expectLater(
      client.searchCards('retry-later'),
      throwsA(isA<CardDataApiException>()),
    );
    final cards = await client.searchCards('retry-later');

    expect(calls, 2);
    expect(cards.single.cardRef, 'recovered');
  });

  for (final testCase in <(String, String?)>[
    ('an empty string', ''),
    ('null', null),
  ]) {
    test(
      'getCard accepts ${testCase.$1} set code because catalog cards may not have one',
      () async {
        final adapter = _RecordingAdapter((request) {
          expect(request.method, 'GET');
          expect(request.path, '/cards/592463');
          final card = _cardJson(cardRef: '592463');
          card['set_code'] = testCase.$2;
          return _json(200, {'success': true, 'data': card});
        });

        final card = await CardDataApiClient(_dio(adapter)).getCard('592463');

        expect(card.setCode, isEmpty);
      },
    );
  }

  test(
    'getPriceSeries sends market qualifiers because Card Detail charts are condition specific',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/cards/catalog%3Apikachu-025/price-series');
        expect(request.queryParameters, {
          'response_version': '2',
          'days': '30',
          'grader': 'Raw',
          'condition': 'Near Mint',
          'finish': 'Normal',
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

      final series = await CardDataApiClient(_dio(adapter)).getPriceSeries(
        'catalog:pikachu-025',
        days: 30,
        condition: 'Near Mint',
        finish: 'Normal',
      );

      expect(series.first.date, '2026-06-10');
      expect(series.last.price, 15);
    },
  );

  test(
    'getPriceSeriesBatch sends one structured request because Card Detail must not fan out HTTP calls',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'POST');
        expect(request.path, '/cards/catalog%3Apikachu-025/price-series/batch');
        expect(request.queryParameters, {'response_version': '2'});
        expect(request.data, {
          'requests': [
            {
              'days': 30,
              'grader': 'Raw',
              'grade': null,
              'condition': 'Near Mint',
              'finish': 'Normal',
            },
          ],
        });
        return _json(200, {
          'success': true,
          'data': {
            'results': [
              {
                'series': [
                  {'date': '2026-07-10', 'price': 15},
                ],
              },
            ],
          },
        });
      });

      final results = await CardDataApiClient(_dio(adapter))
          .getPriceSeriesBatch('catalog:pikachu-025', const [
            CardDataPriceSeriesQuery(
              days: 30,
              grader: 'Raw',
              condition: 'Near Mint',
              finish: 'Normal',
            ),
          ]);

      expect(results.single.single.price, 15);
    },
  );

  test(
    'Premium 1Y batch carries the live session because client state alone must not unlock history',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.headers['Authorization'], 'Bearer access-token');
        expect(request.headers['X-Local-Premium-State'], 'verified');
        return _json(200, {
          'success': true,
          'data': {
            'results': [
              {
                'series': [
                  {'date': '2026-08-12', 'price': 20.0},
                ],
              },
            ],
          },
        });
      });
      const session = AuthSession(
        ownerType: OwnerType.user,
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        userId: 'user-1',
      );

      final results = await CardDataApiClient(_dio(adapter))
          .getPremiumPriceSeriesBatch(session, '100', const [
            CardDataPriceSeriesQuery(days: 365, grader: 'PSA', grade: 10),
          ], localPremiumVerified: true);

      expect(results.single.single.price, 20);
    },
  );

  test(
    'searchSets maps game because Search must keep real sets visible under the selected game',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/sets/search');
        expect(request.queryParameters, {
          'q': '',
          'game': 'Magic: The Gathering',
          'page_size': '40',
        });
        return _json(200, {
          'success': true,
          'data': {
            'items': [
              {
                'set_id': 'odyssey-id',
                'set_code': 'ODY',
                'set_name': 'Odyssey',
                'game': 'Magic: The Gathering',
                'image_url': null,
                'card_count': 350,
              },
            ],
          },
        });
      });

      final sets = await CardDataApiClient(
        _dio(adapter),
      ).searchSets('', game: 'Magic: The Gathering');

      expect(sets.single.setCode, 'ODY');
      expect(sets.single.setId, 'odyssey-id');
      expect(sets.single.game, 'Magic: The Gathering');
      expect(sets.single.cardCount, 350);
    },
  );

  test(
    'listGames reads the database catalog because Search filters must not be inferred from Trending cards',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/games');
        expect(request.queryParameters, isEmpty);
        return _json(200, {
          'success': true,
          'data': {
            'items': [
              {'id': '1', 'name': 'Magic: The Gathering'},
              {'id': '3', 'name': 'Pokemon'},
            ],
          },
        });
      });

      final games = await CardDataApiClient(_dio(adapter)).listGames();

      expect(games.map((game) => game.name), [
        'Magic: The Gathering',
        'Pokemon',
      ]);
    },
  );

  test(
    'searchCatalogSets requests the complete selected game because the Sets tab has no hidden 40-row cutoff',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.path, '/sets/search');
        expect(request.queryParameters, {
          'q': '',
          'game': 'Magic: The Gathering',
          'page': '1',
          'page_size': '40',
        });
        return _json(200, {
          'success': true,
          'data': {
            'items': [
              {
                'set_id': 'tmnt-id',
                'set_code': 'TMC',
                'set_name': 'Commander: Teenage Mutant Ninja Turtles',
                'game': 'Magic: The Gathering',
                'image_url': 'https://image.tcgcard.fun/cards/679068.jpg',
                'card_count': 277,
              },
            ],
          },
        });
      });

      final sets = await CardDataApiClient(
        _dio(adapter),
      ).searchCatalogSets('', game: 'Magic: The Gathering');

      expect(sets.single.setCode, 'TMC');
      expect(
        sets.single.imageUrl,
        'https://image.tcgcard.fun/cards/679068.jpg',
      );
    },
  );

  test(
    'cardsForSet sends the unique set id because one game can reuse a set code',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.path, '/cards/search');
        expect(request.queryParameters, {
          'game': 'Pokemon',
          'set_id': 'base-set-id',
          'page': '2',
          'page_size': '40',
        });
        return _json(200, {
          'success': true,
          'data': {
            'items': [_cardJson(cardRef: 'catalog:base-2')],
          },
        });
      });

      final cards = await CardDataApiClient(
        _dio(adapter),
      ).cardsForSet('base-set-id', game: 'Pokemon', page: 2);

      expect(cards.single.cardRef, 'catalog:base-2');
    },
  );

  test(
    'searchCards accepts an empty card number because the PostgreSQL catalog does not invent identifiers',
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
    'getMarketPrices preserves graded identity and history because duplicate product subtypes are not unique',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.queryParameters['finish'], 'Foil');
        return _json(200, {
          'success': true,
          'data': {
            'prices': [
              {
                'grader': 'PSA',
                'grade': 10,
                'grade_label': '10',
                'condition': null,
                'price': 360.0,
                'pricecharting_id': 'pc-100-foil',
                'product_sub_type': 'Foil',
                'previous_7d_price_usd': 300.0,
                'increase_percent': 20.0,
                'history': [
                  {'date': '2026-07-29', 'price': 300.0},
                  {'date': '2026-07-30', 'price': 360.0},
                ],
              },
            ],
          },
        });
      });

      final price = (await CardDataApiClient(
        _dio(adapter),
      ).getMarketPrices('100', finish: 'Foil')).single;

      expect(price.pricechartingId, 'pc-100-foil');
      expect(price.productSubType, 'Foil');
      expect(price.previous7dPriceUsd, 300);
      expect(price.increasePercent, 20);
      expect(price.history.last.price, 360);
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
    'available_languages': ['English', 'Japanese'],
    'available_finishes': ['Holofoil', 'Normal'],
    'object_type': 'tcg',
    'image_url': 'https://img.example/pikachu.jpg',
    'rarity': 'Common',
    'price_usd': 32.13,
    'previous_30d_price_usd': 30.67,
    'previous_7d_price_usd': 31.05,
    'previous_1d_price_usd': 31.25,
    'price_change_30d_percent': 4.761,
    'price_change_7d_percent': 3.478,
    'price_change_1d_percent': 2.816,
    'price_as_of': '2026-07-15',
    'previous_price_as_of': '2026-07-14',
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

  final FutureOr<ResponseBody> Function(_RecordedRequest request) handler;
  final List<_RecordedRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = _RecordedRequest(
      method: options.method,
      path: options.path,
      data: options.data,
      headers: Map<String, Object?>.from(options.headers),
      queryParameters: options.queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      attempt: options.extra[apiRequestAttemptKey] as int?,
    );
    requests.add(request);
    return await handler(request);
  }

  @override
  void close({bool force = false}) {}
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.data,
    required this.headers,
    required this.queryParameters,
    required this.attempt,
  });

  final String method;
  final String path;
  final Object? data;
  final Map<String, Object?> headers;
  final Map<String, String> queryParameters;
  final int? attempt;
}
