import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/search/set_detail_page.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';

void main() {
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
