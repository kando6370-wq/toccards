import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/set_detail_page.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';

import '../support/mock_search_repository.dart';

void main() {
  testWidgets(
    'set cards show the Cards result details because users need the same collection context from either entry point',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            setCatalogApiClientProvider.overrideWithValue(
              const _PresentationSetCatalogApi(),
            ),
            searchRepositoryProvider.overrideWithValue(
              const MockSearchRepository(),
            ),
          ],
          child: const MaterialApp(
            home: SetDetailPage(
              setCode: 'BS',
              game: 'Pokemon',
              setName: 'Base Set',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('search-card-featured'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Pikachu')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Base Set')),
        findsOneWidget,
      );
      expect(find.text('Rare #025/102'), findsOneWidget);
      expect(find.text('Holo / English'), findsOneWidget);
      expect(find.text('Qty: 0'), findsOneWidget);
      expect(find.text(r'$12.50'), findsOneWidget);
      expect(find.text('+25.00%'), findsOneWidget);
      expect(find.byKey(const Key('search-collect-featured')), findsOneWidget);
      expect(find.byKey(const Key('search-wishlist-featured')), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Pikachu')).style?.fontFamily,
        'Fraunces',
      );

      await tester.tap(find.byKey(const Key('search-collect-featured')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: card, matching: find.text('Qty: 1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'failed pagination retries the same page because a transient error must not skip set cards',
    (tester) async {
      final api = _RetrySetCatalogApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [setCatalogApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: SetDetailPage(
              setCode: 'BS',
              game: 'Pokemon',
              setName: 'Base Set',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('set-detail-pull-to-refresh')),
        findsOneWidget,
      );
      await tester.fling(
        find.byKey(const Key('set-detail-card-grid')),
        const Offset(0, -5000),
        10000,
      );
      await tester.pumpAndSettle();

      expect(api.requestedPages, [1, 2]);
      expect(find.text('Load more'), findsNothing);
      expect(find.byTooltip('Retry loading cards'), findsOneWidget);

      await tester.tap(find.byTooltip('Retry loading cards'));
      await tester.pumpAndSettle();

      expect(api.requestedPages, [1, 2, 2]);
      expect(find.text('Recovered card'), findsOneWidget);
    },
  );
}

class _PresentationSetCatalogApi implements SetCatalogApi {
  const _PresentationSetCatalogApi();

  @override
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page = 1,
  }) async {
    return const [
      CardDataCardDto(
        cardRef: 'featured',
        name: 'Pikachu',
        setName: 'Base Set',
        setCode: 'BS',
        cardNumber: '025/102',
        finish: 'Holo',
        language: 'English',
        objectType: 'tcg',
        game: 'Pokemon',
        imageUrl: null,
        rarity: 'Rare',
        priceUsd: 12.5,
        previous30dPriceUsd: 10,
      ),
    ];
  }

  @override
  Future<List<CardDataGameDto>> listGames() async => const [];

  @override
  Future<List<CardDataSetDto>> searchCatalogSets(
    String query, {
    String? game,
  }) async => const [];
}

class _RetrySetCatalogApi implements SetCatalogApi {
  final requestedPages = <int>[];
  var _pageTwoAttempts = 0;

  @override
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page = 1,
  }) async {
    requestedPages.add(page);
    if (page == 1) {
      return List.generate(40, (index) => _card('card-$index', 'Card $index'));
    }
    _pageTwoAttempts += 1;
    if (_pageTwoAttempts == 1) {
      throw StateError('transient failure');
    }
    return [_card('recovered', 'Recovered card')];
  }

  @override
  Future<List<CardDataGameDto>> listGames() async => const [];

  @override
  Future<List<CardDataSetDto>> searchCatalogSets(
    String query, {
    String? game,
  }) async => const [];
}

CardDataCardDto _card(String cardRef, String name) {
  return CardDataCardDto(
    cardRef: cardRef,
    name: name,
    setName: 'Base Set',
    setCode: 'BS',
    cardNumber: '',
    finish: null,
    language: null,
    objectType: 'tcg',
    imageUrl: null,
    rarity: 'Common',
  );
}
