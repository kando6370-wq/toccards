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
    'folder mutations use Workers routes because Portfolio management must persist for the current owner',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) {
        expect(request.authorization, 'Bearer owner-access');
        switch (call++) {
          case 0:
            expect(request.method, 'POST');
            expect(request.path, '/portfolio/folders');
            expect(request.body, {'name': 'Trade'});
            return _json(201, {
              'success': true,
              'data': _folderJson(id: 'trade', name: 'Trade', sortOrder: 200),
            });
          case 1:
            expect(request.method, 'PATCH');
            expect(request.path, '/portfolio/folders/trade');
            expect(request.body, {'name': 'Trade Binder'});
            return _json(200, {
              'success': true,
              'data': _folderJson(
                id: 'trade',
                name: 'Trade Binder',
                sortOrder: 200,
              ),
            });
          case 2:
            expect(request.method, 'PATCH');
            expect(request.path, '/portfolio/folders/trade/set-default');
            return _json(200, {
              'success': true,
              'data': _folderJson(
                id: 'trade',
                name: 'Trade Binder',
                isDefault: true,
                sortOrder: 200,
              ),
            });
          case 3:
            expect(request.method, 'PATCH');
            expect(request.path, '/portfolio/folders/reorder');
            expect(request.body, {
              'orders': [
                {'folder_id': 'trade', 'sort_order': 100},
                {'folder_id': 'main', 'sort_order': 200},
              ],
            });
            return _json(200, {'success': true, 'data': <String, Object?>{}});
          case 4:
            expect(request.method, 'DELETE');
            expect(request.path, '/portfolio/folders/trade');
            return _json(200, {'success': true, 'data': <String, Object?>{}});
          default:
            throw StateError('unexpected request');
        }
      });
      final api = PortfolioApiClient(_dio(adapter));

      final created = await api.createFolder(
        _session,
        'Trade',
        localPremiumVerified: true,
      );
      final renamed = await api.renameFolder(_session, 'trade', 'Trade Binder');
      final defaultFolder = await api.setDefaultFolder(_session, 'trade');
      await api.reorderFolders(_session, const ['trade', 'main']);
      await api.deleteFolder(_session, 'trade');

      expect(created.name, 'Trade');
      expect(adapter.requests.first.localPremiumState, 'verified');
      expect(renamed.name, 'Trade Binder');
      expect(defaultFolder.isDefault, isTrue);
      expect(adapter.requests, hasLength(5));
    },
  );

  test(
    'preferences round-trip currency visibility and selected folder because Home and Collection share owner settings',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) {
        expect(request.authorization, 'Bearer owner-access');
        if (call++ == 0) {
          expect(request.method, 'GET');
          expect(request.path, '/preferences');
          return _json(200, {
            'success': true,
            'data': {
              'currency': 'USD',
              'amount_hidden': false,
              'last_selected_folder_id': 'main',
            },
          });
        }
        expect(request.method, 'PATCH');
        expect(request.path, '/preferences');
        expect(request.body, {
          'currency': 'NZD',
          'amount_hidden': true,
          'last_selected_folder_id': 'trade',
        });
        return _json(200, {
          'success': true,
          'data': {
            'currency': 'NZD',
            'amount_hidden': true,
            'last_selected_folder_id': 'trade',
          },
        });
      });
      final api = PortfolioApiClient(_dio(adapter));

      final initial = await api.getPreferences(_session);
      final updated = await api.updatePreferences(
        _session,
        currency: 'NZD',
        amountHidden: true,
        lastSelectedFolderId: 'trade',
      );

      expect(initial.currency, 'USD');
      expect(initial.amountHidden, isFalse);
      expect(initial.lastSelectedFolderId, 'main');
      expect(updated.currency, 'NZD');
      expect(updated.amountHidden, isTrue);
      expect(updated.lastSelectedFolderId, 'trade');
    },
  );

  test(
    'collection dashboard maps all display data in one request because Collection must not issue per-card calls',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/collection/dashboard');
        expect(request.queryParameters, isEmpty);
        return _json(200, {
          'success': true,
          'data': {
            'folders': [
              _folderJson(
                id: 'main',
                name: 'Main',
                isDefault: true,
                sortOrder: 100,
              ),
            ],
            'preference': {
              'currency': 'NZD',
              'amount_hidden': true,
              'last_selected_folder_id': 'main',
            },
            'portfolio_items': [
              {
                'id': 'item-1',
                'folder_id': 'main',
                'card_ref': '100',
                'name': 'Pikachu',
                'set_name': 'Base Set',
                'card_number': '25',
                'rarity': 'Rare Holo',
                'game': 'Pokemon',
                'language': 'English',
                'finish': 'Normal',
                'grader': 'Raw',
                'condition': 'Near Mint (NM)',
                'grade': null,
                'quantity': 2,
                'market_price_usd': 20,
                'previous_30d_price_usd': 10,
                'increase_percent': 8.97,
                'folder_joined_at': '2026-07-05T00:00:00.000Z',
                'created_at': '2026-07-01T00:00:00.000Z',
                'image_url': 'https://img.example/100.jpg',
              },
            ],
            'wishlist_items': <Object?>[],
          },
        });
      });

      final dashboard = await PortfolioApiClient(
        _dio(adapter),
      ).getCollectionDashboard(_session);

      expect(dashboard.folders.single.id, 'main');
      expect(dashboard.preference.currency, 'NZD');
      expect(dashboard.portfolioItems.single.marketPriceUsd, 20);
      expect(dashboard.portfolioItems.single.previous30dPriceUsd, 10);
      expect(dashboard.portfolioItems.single.increasePercent, 8.97);
      expect(dashboard.portfolioItems.single.rarity, 'Rare Holo');
      expect(
        dashboard.portfolioItems.single.folderJoinedAt,
        DateTime.parse('2026-07-05T00:00:00.000Z'),
      );
      expect(adapter.requests, hasLength(1));
    },
  );

  test(
    'listCollectionItems maps backend rows because Collection reads Workers asset state',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/portfolio/items');
        expect(request.queryParameters, {'page': '1', 'page_size': '40'});
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
    'asset lists request every 40-row page because pagination must not truncate ownership state',
    () async {
      final adapter = _RecordingAdapter((request) {
        final page = request.queryParameters['page'];
        final items = page == '1'
            ? List.generate(
                40,
                (index) => _portfolioItemJson(
                  id: 'item-$index',
                  cardRef: 'card-$index',
                ),
              )
            : [_portfolioItemJson(id: 'item-40', cardRef: 'card-40')];
        return _json(200, {
          'success': true,
          'data': {'items': items},
        });
      });

      final items = await PortfolioApiClient(
        _dio(adapter),
      ).listCollectionItems(_session);

      expect(items, hasLength(41));
      expect(adapter.requests.map((request) => request.queryParameters), [
        {'page': '1', 'page_size': '40'},
        {'page': '2', 'page_size': '40'},
      ]);
    },
  );

  test(
    'listWishlistItems maps backend rows because wishlist deletions need row ids',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/wishlist');
        expect(request.queryParameters, {'page': '1', 'page_size': '40'});
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
    'getValuationHistory maps the single portfolio curve response because Home must not rebuild history per card',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/portfolio/valuation-history');
        expect(request.queryParameters, {'days': '90'});
        return _json(200, {
          'success': true,
          'data': {
            'items': [
              {
                'folder_id': 'main',
                'item_count': 1,
                'market_price_status': 'available',
                'current_value_usd': 42.5,
                'series': [
                  {'date': '2026-07-15', 'value_usd': 40},
                  {'date': '2026-07-16', 'value_usd': 42.5},
                ],
                'most_valuable': [
                  {
                    'item_id': 'item-1',
                    'card_ref': '9359',
                    'name': 'Escape Artist',
                    'set_name': 'Odyssey',
                    'card_number': '',
                    'finish': 'Normal',
                    'image_url': 'https://img.example/9359.jpg',
                    'price_usd': 0.21,
                    'previous_30d_price_usd': null,
                  },
                ],
              },
            ],
          },
        });
      });

      final history = await PortfolioApiClient(
        _dio(adapter),
      ).getValuationHistory(_session);

      expect(history.single.folderId, 'main');
      expect(history.single.itemCount, 1);
      expect(history.single.marketPriceStatus, MarketPriceStatus.available);
      expect(history.single.currentValueUsd, 42.5);
      expect(history.single.series.first.valueUsd, 40);
      expect(history.single.series.last.date, '2026-07-16');
      expect(history.single.mostValuable.single.name, 'Escape Artist');
      expect(history.single.mostValuable.single.previous30dPriceUsd, isNull);
    },
  );

  test(
    'extended valuation history sends local verified only as a sync hint because the server grant remains authoritative',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.path, '/portfolio/valuation-history');
        expect(request.queryParameters, {'days': '365', 'folder_id': 'main'});
        expect(request.localPremiumState, 'verified');
        return _json(200, {
          'success': true,
          'data': {'items': <Object>[]},
        });
      });

      final history = await PortfolioApiClient(_dio(adapter))
          .getValuationHistory(
            _session,
            days: 365,
            folderId: 'main',
            localPremiumVerified: true,
          );

      expect(history, isEmpty);
    },
  );

  test(
    'Performance requests preserve scope and server truth while mapping partial cost history',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'GET');
        expect(request.authorization, 'Bearer owner-access');
        expect(request.localPremiumState, 'verified');
        if (call++ == 0) {
          expect(request.path, '/portfolio/performance');
          expect(request.queryParameters, {'range': '1M', 'folder_id': 'main'});
        } else {
          expect(request.path, '/portfolio/items/item%2F1/performance');
          expect(request.queryParameters, {'range': '1Y'});
        }
        return _json(200, {
          'success': true,
          'data': {
            'range': call == 1 ? '1M' : '1Y',
            'range_start': '2026-07-12',
            'range_end': '2026-08-12',
            'history_available_from': '2026-08-01',
            'partial_history': true,
            'item_count': 2,
            'market_price_status': 'available',
            'purchase_price_status': 'partial',
            'purchase_price_item_count': 1,
            if (call == 1) 'top_performer_count': 6,
            if (call == 1)
              'top_performer_item_ids': ['item-top', 'item-second'],
            if (call == 1)
              'top_performers': [
                {
                  'item_id': 'item-top',
                  'card_ref': 'card-top',
                  'name': 'Pikachu',
                  'set_name': 'Diamond & Pearl',
                  'card_number': '95',
                  'image_url': 'https://example.com/pikachu.png',
                  'profit_loss_usd': 40,
                  'return_percent': 200,
                  'market_value_usd': 60,
                },
              ],
            'current': {
              'market_value_usd': 60,
              'market_value_change_usd': 30,
              'market_change_usd': 20,
              'portfolio_change_usd': 10,
              'paid_market_value_usd': 40,
              'total_paid_usd': 30,
              'profit_loss_usd': 10,
              'profit_loss_change_usd': 5,
              'return_percent': 33.33,
              'quantity': 3,
              'quantity_change': 1,
            },
            'series': [
              {
                'date': '2026-08-12',
                'market_value_usd': 60,
                'market_value_change_usd': 30,
                'market_change_usd': 20,
                'portfolio_change_usd': 10,
                'paid_market_value_usd': 40,
                'total_paid_usd': 30,
                'profit_loss_usd': 10,
                'profit_loss_change_usd': 5,
                'return_percent': 33.33,
                'quantity': 3,
                'quantity_change': 1,
              },
            ],
          },
        });
      });
      final api = PortfolioApiClient(_dio(adapter));

      final home = await api.getPortfolioPerformance(
        _session,
        range: PerformanceRange.oneMonth,
        folderId: 'main',
        localPremiumVerified: true,
      );
      final item = await api.getItemPerformance(
        _session,
        itemId: 'item/1',
        range: PerformanceRange.oneYear,
        localPremiumVerified: true,
      );

      expect(home.partialHistory, isTrue);
      expect(home.itemCount, 2);
      expect(home.marketPriceStatus, MarketPriceStatus.available);
      expect(home.purchasePriceStatus, PurchasePriceStatus.partial);
      expect(home.purchasePriceItemCount, 1);
      expect(home.current.totalPaidUsd, 30);
      expect(home.current.marketChangeUsd, 20);
      expect(home.current.marketValueChangeUsd, 30);
      expect(home.current.profitLossChangeUsd, 5);
      expect(home.current.portfolioChangeUsd, 10);
      expect(home.series.single.quantity, 3);
      expect(home.series.single.quantityChange, 1);
      expect(home.topPerformerCount, 6);
      expect(home.topPerformerItemIds, ['item-top', 'item-second']);
      expect(home.topPerformers.single.itemId, 'item-top');
      expect(home.topPerformers.single.cardRef, 'card-top');
      expect(home.topPerformers.single.profitLossUsd, 40);
      expect(home.topPerformers.single.returnPercent, 200);
      expect(item.range, PerformanceRange.oneYear);
      expect(item.topPerformers, isEmpty);
      expect(adapter.requests, hasLength(2));
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
    'createCollectionItem posts bearer payload and maps response because manual adds create backend rows',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'POST');
        expect(request.path, '/portfolio/items');
        expect(request.authorization, 'Bearer owner-access');
        expect(request.body, {
          'card_ref': 'squirtle',
          'folder_id': 'main',
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
        });
        return _json(201, {
          'success': true,
          'data': _portfolioItemJson(id: 'item-squirtle', cardRef: 'squirtle'),
        });
      });

      final item = await PortfolioApiClient(_dio(adapter)).createCollectionItem(
        _session,
        const PortfolioItemDraftDto(
          folderId: 'main',
          cardRef: 'squirtle',
          objectType: 'tcg',
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          language: 'English',
          finish: 'Holofoil',
          quantity: 1,
          purchasePrice: 12.5,
          purchaseCurrency: 'USD',
          notes: 'binder copy',
        ),
      );

      expect(item.id, 'item-squirtle');
      expect(item.folderId, 'main');
      expect(item.cardRef, 'squirtle');
      expect(item.purchasePrice, 12.5);
    },
  );

  test(
    'timed out item creates reuse their idempotency key across token refresh and clear it after success',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) async {
        call += 1;
        if (call == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        return _json(200, {
          'success': true,
          'data': _portfolioItemJson(id: 'item-$call', cardRef: 'squirtle'),
        });
      });
      final api = PortfolioApiClient(
        _dio(adapter),
        requestDeadline: const Duration(milliseconds: 20),
      );
      const draft = PortfolioItemDraftDto(
        folderId: 'main',
        cardRef: 'squirtle',
        objectType: 'tcg',
        grader: 'Raw',
        condition: 'Near Mint (NM)',
        grade: null,
        language: 'English',
        finish: 'Holofoil',
        quantity: 1,
        purchasePrice: 12.5,
        purchaseCurrency: 'USD',
        notes: 'binder copy',
      );

      await expectLater(
        api.createCollectionItem(_session, draft),
        throwsA(isA<PortfolioApiException>()),
      );
      final refreshedSession = AuthSession(
        ownerType: _session.ownerType,
        accessToken: 'refreshed-owner-access',
        refreshToken: _session.refreshToken,
        userId: _session.userId,
      );
      await api.createCollectionItem(refreshedSession, draft);
      await api.createCollectionItem(refreshedSession, draft);

      expect(adapter.requests[0].idempotencyKey, isNotEmpty);
      expect(
        adapter.requests[1].idempotencyKey,
        adapter.requests[0].idempotencyKey,
      );
      expect(
        adapter.requests[2].idempotencyKey,
        isNot(adapter.requests[1].idempotencyKey),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test(
    'distinct pending Items keep distinct explicit idempotency keys even when their drafts match',
    () async {
      var responseIndex = 0;
      final adapter = _RecordingAdapter((request) {
        responseIndex += 1;
        return _json(201, {
          'success': true,
          'data': _portfolioItemJson(
            id: 'item-$responseIndex',
            cardRef: 'squirtle',
          ),
        });
      });
      final api = PortfolioApiClient(_dio(adapter));
      const draft = PortfolioItemDraftDto(
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
        notes: '',
      );

      await api.createCollectionItem(
        _session,
        draft,
        idempotencyKey: 'pending-item-a',
      );
      await api.createCollectionItem(
        _session,
        draft,
        idempotencyKey: 'pending-item-b',
      );

      expect(adapter.requests.map((request) => request.idempotencyKey), [
        'pending-item-a',
        'pending-item-b',
      ]);
    },
  );

  const retryDraft = PortfolioItemDraftDto(
    folderId: 'main',
    cardRef: 'squirtle',
    objectType: 'tcg',
    grader: 'Raw',
    condition: 'Near Mint (NM)',
    grade: null,
    language: 'English',
    finish: 'Holofoil',
    quantity: 1,
    purchasePrice: 12.5,
    purchaseCurrency: 'USD',
    notes: 'binder copy',
  );
  final itemCreateOperations = {
    'Quick Collect': (PortfolioApiClient api) =>
        api.quickCollect(_session, cardRef: 'squirtle', draft: retryDraft),
    'Collection Item Create': (PortfolioApiClient api) =>
        api.createCollectionItem(_session, retryDraft),
  };
  for (final operation in itemCreateOperations.entries) {
    test(
      'HTTP 500 ${operation.key} retry reuses its key because the write may already have committed',
      () async {
        var call = 0;
        final adapter = _RecordingAdapter((request) {
          call += 1;
          if (call == 1) {
            return _json(500, {
              'success': false,
              'error': {
                'code': 'INTERNAL_ERROR',
                'message': 'Internal server error.',
              },
            });
          }
          return _json(200, {
            'success': true,
            'data': _portfolioItemJson(id: 'item-$call', cardRef: 'squirtle'),
          });
        });
        final api = PortfolioApiClient(_dio(adapter));

        await expectLater(
          operation.value(api),
          throwsA(
            isA<PortfolioApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              500,
            ),
          ),
        );
        await operation.value(api);
        await operation.value(api);

        expect(
          adapter.requests[1].idempotencyKey,
          adapter.requests[0].idempotencyKey,
        );
        expect(
          adapter.requests[2].idempotencyKey,
          isNot(adapter.requests[1].idempotencyKey),
        );
      },
    );
  }

  test(
    'updateCollectionItem sends folder with fields because edited moves must complete atomically',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'PATCH');
        expect(request.path, '/portfolio/items/item-squirtle');
        expect(request.authorization, 'Bearer owner-access');
        expect(request.body, {
          'folder_id': 'trade',
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
        expect(body.containsKey('card_ref'), isFalse);
        expect(body.containsKey('object_type'), isFalse);
        return _json(200, {
          'success': true,
          'data': _portfolioItemJson(
            id: 'item-squirtle',
            cardRef: 'squirtle',
            folderId: 'trade',
          ),
        });
      });

      final item = await PortfolioApiClient(_dio(adapter)).updateCollectionItem(
        _session,
        itemId: 'item-squirtle',
        draft: const PortfolioItemDraftDto(
          folderId: 'trade',
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
      expect(item.folderId, 'trade');
    },
  );

  test(
    'deleteCollectionItem sends backend item id because portfolio deletes are row scoped',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'DELETE');
        expect(request.path, '/portfolio/items/item-squirtle');
        expect(request.authorization, 'Bearer owner-access');
        return _json(200, {'success': true, 'data': <String, Object?>{}});
      });

      await PortfolioApiClient(
        _dio(adapter),
      ).deleteCollectionItem(_session, 'item-squirtle');

      expect(adapter.requests.single.path, '/portfolio/items/item-squirtle');
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
        expect(request.idempotencyKey, isNotEmpty);
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
    'timed out Wishlist Add reuses its key after token refresh and success clears it',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) async {
        call += 1;
        if (call == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        return _json(200, {
          'success': true,
          'data': {
            'id': 'wish-$call',
            'card_ref': 'squirtle',
            'created_at': '2026-01-03T00:00:00.000Z',
          },
        });
      });
      final api = PortfolioApiClient(
        _dio(adapter),
        requestDeadline: const Duration(milliseconds: 20),
      );

      await expectLater(
        api.addWishlist(_session, 'squirtle'),
        throwsA(isA<PortfolioApiException>()),
      );
      final refreshedSession = AuthSession(
        ownerType: _session.ownerType,
        accessToken: 'refreshed-owner-access',
        refreshToken: _session.refreshToken,
        userId: _session.userId,
      );
      await api.addWishlist(refreshedSession, 'squirtle');
      await api.addWishlist(refreshedSession, 'squirtle');

      expect(
        adapter.requests[1].idempotencyKey,
        adapter.requests[0].idempotencyKey,
      );
      expect(
        adapter.requests[2].idempotencyKey,
        isNot(adapter.requests[1].idempotencyKey),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test(
    'HTTP 500 Wishlist Add retry reuses its key because the row may already exist',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) {
        call += 1;
        if (call == 1) {
          return _json(500, {
            'success': false,
            'error': {
              'code': 'INTERNAL_ERROR',
              'message': 'Internal server error.',
            },
          });
        }
        return _json(200, {
          'success': true,
          'data': {
            'id': 'wish-$call',
            'card_ref': 'squirtle',
            'created_at': '2026-01-03T00:00:00.000Z',
          },
        });
      });
      final api = PortfolioApiClient(_dio(adapter));

      await expectLater(
        api.addWishlist(_session, 'squirtle'),
        throwsA(
          isA<PortfolioApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            500,
          ),
        ),
      );
      await api.addWishlist(_session, 'squirtle');
      await api.addWishlist(_session, 'squirtle');

      expect(
        adapter.requests[1].idempotencyKey,
        adapter.requests[0].idempotencyKey,
      );
      expect(
        adapter.requests[2].idempotencyKey,
        isNot(adapter.requests[1].idempotencyKey),
      );
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

  test(
    'portfolio writes share one total deadline so a late response cannot complete an expired save',
    () async {
      final adapter = _RecordingAdapter((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return _json(201, {
          'success': true,
          'data': _folderJson(id: 'late', name: 'Late', sortOrder: 200),
        });
      });

      await expectLater(
        PortfolioApiClient(
          _dio(adapter),
          requestDeadline: const Duration(milliseconds: 20),
        ).createFolder(_session, 'Late'),
        throwsA(
          isA<PortfolioApiException>()
              .having(
                (error) => error.code,
                'code',
                portfolioRequestTimeoutCode,
              )
              .having(
                (error) => error.message,
                'message',
                portfolioRequestTimeoutMessage,
              ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test(
    'a timed out Folder retry reuses its idempotency key and success clears it for a later independent create',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) async {
        call += 1;
        if (call == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        return _json(200, {
          'success': true,
          'data': _folderJson(
            id: 'folder-$call',
            name: 'Trade',
            sortOrder: 200,
          ),
        });
      });
      final api = PortfolioApiClient(
        _dio(adapter),
        requestDeadline: const Duration(milliseconds: 20),
      );

      await expectLater(
        api.createFolder(_session, 'Trade'),
        throwsA(isA<PortfolioApiException>()),
      );
      final refreshedSession = AuthSession(
        ownerType: _session.ownerType,
        accessToken: 'refreshed-owner-access',
        refreshToken: _session.refreshToken,
        userId: _session.userId,
      );
      final retried = await api.createFolder(refreshedSession, 'Trade');
      final independent = await api.createFolder(refreshedSession, 'Trade');

      expect(retried.id, 'folder-2');
      expect(independent.id, 'folder-3');
      expect(adapter.requests[0].idempotencyKey, isNotEmpty);
      expect(
        adapter.requests[1].idempotencyKey,
        adapter.requests[0].idempotencyKey,
      );
      expect(
        adapter.requests[2].idempotencyKey,
        isNot(adapter.requests[1].idempotencyKey),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  for (final statusCode in const [408, 500]) {
    test(
      'HTTP $statusCode Folder retry reuses its key because commit status is ambiguous',
      () async {
        var call = 0;
        final adapter = _RecordingAdapter((request) {
          call += 1;
          if (call == 1) {
            return _json(statusCode, {
              'success': false,
              'error': {
                'code': statusCode == 408
                    ? 'REQUEST_TIMEOUT'
                    : 'INTERNAL_ERROR',
                'message': 'Create result is unknown.',
              },
            });
          }
          return _json(200, {
            'success': true,
            'data': _folderJson(
              id: 'folder-$call',
              name: 'Trade',
              sortOrder: 200,
            ),
          });
        });
        final api = PortfolioApiClient(_dio(adapter));

        await expectLater(
          api.createFolder(_session, 'Trade'),
          throwsA(
            isA<PortfolioApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              statusCode,
            ),
          ),
        );
        await api.createFolder(_session, 'Trade');
        await api.createFolder(_session, 'Trade');

        expect(
          adapter.requests[1].idempotencyKey,
          adapter.requests[0].idempotencyKey,
        );
        expect(
          adapter.requests[2].idempotencyKey,
          isNot(adapter.requests[1].idempotencyKey),
        );
      },
    );
  }

  test(
    'malformed Folder success keeps its key because parsing cannot prove whether the create committed',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) {
        call += 1;
        if (call == 1) {
          return _json(201, {
            'success': true,
            'data': {'name': 'Trade', 'is_default': false, 'sort_order': 200},
          });
        }
        return _json(200, {
          'success': true,
          'data': _folderJson(
            id: 'folder-$call',
            name: 'Trade',
            sortOrder: 200,
          ),
        });
      });
      final api = PortfolioApiClient(_dio(adapter));

      await expectLater(
        api.createFolder(_session, 'Trade'),
        throwsA(
          isA<PortfolioApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            isNull,
          ),
        ),
      );
      await api.createFolder(_session, 'Trade');
      await api.createFolder(_session, 'Trade');

      expect(
        adapter.requests[1].idempotencyKey,
        adapter.requests[0].idempotencyKey,
      );
      expect(
        adapter.requests[2].idempotencyKey,
        isNot(adapter.requests[1].idempotencyKey),
      );
    },
  );

  test(
    'HTTP 409 Folder response clears its key because the server rejected the create conclusively',
    () async {
      var call = 0;
      final adapter = _RecordingAdapter((request) {
        call += 1;
        if (call == 1) {
          return _json(409, {
            'success': false,
            'error': {'code': 'CONFLICT', 'message': 'Conflict.'},
          });
        }
        return _json(200, {
          'success': true,
          'data': _folderJson(
            id: 'folder-$call',
            name: 'Trade',
            sortOrder: 200,
          ),
        });
      });
      final api = PortfolioApiClient(_dio(adapter));

      await expectLater(
        api.createFolder(_session, 'Trade'),
        throwsA(
          isA<PortfolioApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            409,
          ),
        ),
      );
      await api.createFolder(_session, 'Trade');

      expect(
        adapter.requests[1].idempotencyKey,
        isNot(adapter.requests[0].idempotencyKey),
      );
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
  String folderId = 'main',
}) {
  return {
    'id': id,
    'folder_id': folderId,
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

Map<String, Object?> _folderJson({
  required String id,
  required String name,
  bool isDefault = false,
  required int sortOrder,
}) {
  return {
    'id': id,
    'name': name,
    'is_default': isDefault,
    'sort_order': sortOrder,
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
      queryParameters: options.queryParameters.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      authorization: options.headers['Authorization']?.toString(),
      idempotencyKey: options.headers['Idempotency-Key']?.toString(),
      localPremiumState: options.headers['X-Local-Premium-State']?.toString(),
      body: await _decodeBody(requestStream) ?? options.data,
    );
    requests.add(request);
    return await handler(request);
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
    required this.idempotencyKey,
    required this.localPremiumState,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> queryParameters;
  final String? authorization;
  final String? idempotencyKey;
  final String? localPremiumState;
  final Object? body;
}
