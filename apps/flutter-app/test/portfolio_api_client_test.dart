import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

void main() {
  test(
    'listFolders attaches bearer token because portfolio rows are owner scoped',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/portfolio/folders');
        expect(request.authorization, 'Bearer owner-access');
        return _json(200, {
          'success': true,
          'data': {
            'items': [
              {
                'id': 'main',
                'name': 'Main',
                'is_default': true,
                'sort_order': 100,
                'created_at': '2026-01-01T00:00:00.000Z',
                'updated_at': '2026-01-01T00:00:00.000Z',
              },
            ],
          },
        });
      });

      final folders = await PortfolioApiClient(
        _dio(adapter),
      ).listFolders(_session);

      expect(folders.single.id, 'main');
      expect(folders.single.name, 'Main');
      expect(folders.single.isDefault, isTrue);
      expect(folders.single.sortOrder, 100);
    },
  );

  test(
    'listCollectionItems maps backend rows because Collection reads Workers asset state',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/portfolio/items');
        expect(request.queryParameters, {'page_size': '100'});
        expect(request.authorization, 'Bearer owner-access');
        return _json(200, {
          'success': true,
          'data': {
            'items': [_portfolioItemJson(id: 'item-1', cardRef: 'squirtle')],
          },
        });
      });

      final items = await PortfolioApiClient(
        _dio(adapter),
      ).listCollectionItems(_session);

      expect(items.single.id, 'item-1');
      expect(items.single.folderId, 'main');
      expect(items.single.cardRef, 'squirtle');
      expect(items.single.objectType, 'tcg');
      expect(items.single.grader, 'Raw');
      expect(items.single.condition, 'Near Mint (NM)');
      expect(items.single.grade, isNull);
      expect(items.single.language, 'English');
      expect(items.single.finish, 'Holofoil');
      expect(items.single.quantity, 1);
      expect(items.single.purchasePrice, 12.5);
      expect(items.single.purchaseCurrency, 'USD');
      expect(items.single.notes, 'binder copy');
      expect(
        items.single.createdAt,
        DateTime.parse('2026-01-01T00:00:00.000Z'),
      );
      expect(
        items.single.updatedAt,
        DateTime.parse('2026-01-02T00:00:00.000Z'),
      );
    },
  );

  test(
    'listWishlistItems maps backend rows because wishlist deletions need row ids',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/wishlist');
        expect(request.queryParameters, {'page_size': '100'});
        expect(request.authorization, 'Bearer owner-access');
        return _json(200, {
          'success': true,
          'data': {
            'items': [
              {
                'id': 'wish-1',
                'card_ref': 'one-piece-luffy',
                'created_at': '2026-01-03T00:00:00.000Z',
              },
            ],
          },
        });
      });

      final wishlist = await PortfolioApiClient(
        _dio(adapter),
      ).listWishlistItems(_session);

      expect(wishlist.single.id, 'wish-1');
      expect(wishlist.single.cardRef, 'one-piece-luffy');
      expect(
        wishlist.single.createdAt,
        DateTime.parse('2026-01-03T00:00:00.000Z'),
      );
    },
  );

  test(
    'quickCollect posts path card ref and body fields required by Workers',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'POST');
        expect(request.path, '/cards/squirtle/collect');
        expect(request.authorization, 'Bearer owner-access');
        expect(request.body, {
          'folder_id': 'main',
          'object_type': 'tcg',
          'grader': 'Raw',
          'condition': 'Near Mint (NM)',
          'grade': null,
          'language': 'English',
          'finish': 'Holofoil',
          'quantity': 1,
          'purchase_price': null,
          'purchase_currency': null,
          'notes': 'Quick collected from CardDetail.',
        });
        return _json(201, {
          'success': true,
          'data': _portfolioItemJson(id: 'item-squirtle', cardRef: 'squirtle'),
        });
      });

      final item = await PortfolioApiClient(_dio(adapter)).quickCollect(
        _session,
        cardRef: 'squirtle',
        draft: const PortfolioItemDraftDto(
          folderId: 'main',
          cardRef: 'squirtle',
          objectType: 'tcg',
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          language: 'English',
          finish: 'Holofoil',
          quantity: 1,
          purchasePrice: null,
          purchaseCurrency: null,
          notes: 'Quick collected from CardDetail.',
        ),
      );

      expect(item.id, 'item-squirtle');
      expect(item.cardRef, 'squirtle');
    },
  );

  test(
    'updateCollectionItem sends only mutable fields because Workers PATCH rejects identity fields',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'PATCH');
        expect(request.path, '/portfolio/items/item-squirtle');
        expect(request.authorization, 'Bearer owner-access');
        expect(request.body, {
          'grader': 'Raw',
          'condition': 'Near Mint (NM)',
          'grade': null,
          'language': 'English',
          'finish': 'Holofoil',
          'quantity': 1,
          'purchase_price': null,
          'purchase_currency': null,
          'notes': 'Edited from CardDetail.',
        });
        final body = request.body as Map;
        expect(body.containsKey('folder_id'), isFalse);
        expect(body.containsKey('card_ref'), isFalse);
        return _json(200, {
          'success': true,
          'data': _portfolioItemJson(id: 'item-squirtle', cardRef: 'squirtle'),
        });
      });

      final item = await PortfolioApiClient(_dio(adapter)).updateCollectionItem(
        _session,
        itemId: 'item-squirtle',
        draft: const PortfolioItemDraftDto(
          folderId: 'main',
          cardRef: 'squirtle',
          objectType: 'tcg',
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          language: 'English',
          finish: 'Holofoil',
          quantity: 1,
          purchasePrice: null,
          purchaseCurrency: null,
          notes: 'Edited from CardDetail.',
        ),
      );

      expect(item.id, 'item-squirtle');
    },
  );

  test(
    'listCollectionItems rejects malformed list items because dropped rows hide backend contract bugs',
    () async {
      final adapter = _RecordingAdapter((request) {
        return _json(200, {
          'success': true,
          'data': {
            'items': [
              _portfolioItemJson(id: 'item-1', cardRef: 'squirtle'),
              'not-an-object',
            ],
          },
        });
      });

      expect(
        PortfolioApiClient(_dio(adapter)).listCollectionItems(_session),
        throwsA(isA<PortfolioApiException>()),
      );
    },
  );

  test(
    'addWishlist posts card ref because Workers creates the wishlist row id',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'POST');
        expect(request.path, '/wishlist');
        expect(request.authorization, 'Bearer owner-access');
        expect(request.body, {'card_ref': 'squirtle'});
        return _json(201, {
          'success': true,
          'data': {
            'id': 'wish-squirtle',
            'card_ref': 'squirtle',
            'created_at': '2026-01-03T00:00:00.000Z',
          },
        });
      });

      final item = await PortfolioApiClient(
        _dio(adapter),
      ).addWishlist(_session, 'squirtle');

      expect(item.id, 'wish-squirtle');
      expect(item.cardRef, 'squirtle');
    },
  );

  test(
    'deleteWishlist sends backend wishlist item id because card refs are not row ids',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'DELETE');
        expect(request.path, '/wishlist/wish-squirtle');
        expect(request.authorization, 'Bearer owner-access');
        return _json(200, {'success': true, 'data': <String, Object?>{}});
      });

      await PortfolioApiClient(
        _dio(adapter),
      ).deleteWishlist(_session, 'wish-squirtle');

      expect(adapter.requests.single.path, '/wishlist/wish-squirtle');
    },
  );
}

final _session = AuthSession(
  ownerType: OwnerType.user,
  accessToken: 'owner-access',
  refreshToken: 'owner-refresh',
  userId: 'owner-1',
);

Dio _dio(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
  dio.httpClientAdapter = adapter;
  return dio;
}

Map<String, Object?> _portfolioItemJson({
  required String id,
  required String cardRef,
}) {
  return {
    'id': id,
    'folder_id': 'main',
    'card_ref': cardRef,
    'object_type': 'tcg',
    'grader': 'Raw',
    'condition': 'Near Mint (NM)',
    'grade': null,
    'language': 'English',
    'finish': 'Holofoil',
    'quantity': 1,
    'purchase_price': 12.5,
    'purchase_currency': 'USD',
    'notes': 'binder copy',
    'created_at': '2026-01-01T00:00:00.000Z',
    'updated_at': '2026-01-02T00:00:00.000Z',
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
      queryParameters: options.queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      authorization: options.headers['Authorization']?.toString(),
      body: await _decodeBody(requestStream) ?? options.data,
    );
    requests.add(request);
    return handler(request);
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

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> queryParameters;
  final String? authorization;
  final Object? body;
}
