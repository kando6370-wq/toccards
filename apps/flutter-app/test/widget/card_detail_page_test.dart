import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_page.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_card_detail_repository.dart';

void main() {
  testWidgets('uncollected CardDetail renders identity and price overview', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'squirtle'));
    await tester.pumpAndSettle();

    expect(find.text('Squirtle'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Basic information'), 300);
    expect(find.text('Pokemon'), findsOneWidget);
    expect(find.text('Mega Evolution Promos'), findsOneWidget);
    expect(find.text('Promo #039'), findsOneWidget);
    expect(find.text('Holofoil'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Add to Portfolio'), findsOneWidget);
    expect(find.text('Collect'), findsNothing);

    await tester.scrollUntilVisible(find.text('Price overview'), 400);

    expect(find.text('Price overview'), findsOneWidget);
    expect(find.text('Price range'), findsOneWidget);
    expect(find.text('1d'), findsOneWidget);
    expect(find.text('7d'), findsOneWidget);
    expect(find.text('15d'), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    expect(find.text('3m'), findsOneWidget);
    expect(find.text('6M'), findsNothing);
    expect(find.text('12M'), findsNothing);
    expect(find.text('MAX'), findsNothing);
    expect(find.text('30D'), findsNothing);
    expect(find.text('Price series'), findsOneWidget);
    expect(find.text('30 days ago'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('Sold listings'), findsOneWidget);
    expect(find.text('Raw Near Mint (NM)'), findsOneWidget);
    expect(find.text(r'$32.13'), findsWidgets);
    expect(find.text('7D +2.19%'), findsOneWidget);
    expect(find.text('Collection Item'), findsNothing);
    expect(find.text('Remove from Portfolio'), findsNothing);
  });

  testWidgets('Price Tab missing data renders fallback copy', (tester) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'mystery-promo'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Price overview'), 400);

    expect(find.text('Price series'), findsOneWidget);
    expect(find.text('No price data available.'), findsOneWidget);
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('Raw'), findsWidgets);
    expect(find.text('--'), findsWidgets);
    expect(find.text('7D -/-'), findsOneWidget);
    expect(find.text('Sold listings'), findsOneWidget);
    expect(find.text('No sold listings available.'), findsOneWidget);
    expect(find.text(noContentAvailableText), findsNothing);
  });

  testWidgets(
    'Add to Portfolio uses item form because details need explicit ownership fields',
    (tester) async {
      await tester.pumpWidget(
        const _CardDetailTestApp(cardId: 'one-piece-luffy'),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.favorite), findsOneWidget);

      await tester.tap(find.text('Add to Portfolio'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('card-detail-scroll')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.text('OWNERSHIP SUMMARY'), findsOneWidget);
      expect(find.text('Adding to Main'), findsOneWidget);
      expect(find.byKey(const Key('card-detail-item-portfolio')), findsNothing);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('Near Mint (NM)'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('card-detail-scroll')),
        const Offset(0, -240),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-item-condition')));
      await tester.pumpAndSettle();
      expect(find.text('Lightly Played (LP)'), findsOneWidget);
      expect(find.text('Nearly Mint (NM)'), findsNothing);
      await tester.tap(find.text('Near Mint (NM)').last);
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('card-detail-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-item-submit')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CardDetailPage)),
      );
      final savedState = container.read(
        cardDetailControllerProvider('one-piece-luffy'),
      );
      final savedDetail = savedState.detail;

      expect(savedDetail.isCollected, isTrue);
      expect(savedDetail.quantity, 1);
      expect(savedDetail.isWishlisted, isFalse);
      expect(find.text('OWNERSHIP SUMMARY'), findsNothing);
      expect(savedState.collectionItemRows.single.portfolioName, 'Main');
      expect(
        savedState.collectionItemRows.single.statusText,
        'Raw / Near Mint (NM)',
      );
      expect(savedState.collectionItemRows.single.purchasePriceText, '--');
    },
  );

  testWidgets('owned CardDetail defaults to Collection Item content', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Collected'), findsOneWidget);
    expect(find.text('Collect'), findsNothing);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.byIcon(Icons.ios_share_outlined), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);

    expect(find.text('Collection Item'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text('PSA 10'), findsOneWidget);
    expect(find.text('Purchase price'), findsOneWidget);
    expect(find.text(r'$650.00'), findsWidgets);
    expect(find.text('Language'), findsWidgets);
    expect(find.text('English'), findsWidgets);
    expect(find.text('Finish'), findsWidgets);
    expect(find.text('Holofoil'), findsWidgets);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text(r'$650.00'), findsWidgets);
    expect(find.text('Pulled from Obsidian Flames binder.'), findsOneWidget);
    expect(find.text('Price overview'), findsNothing);
  });

  testWidgets('owned CardDetail can switch to Price overview', (tester) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Price'), 400);
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();

    expect(find.text('Price overview'), findsOneWidget);
    expect(find.text('RAW'), findsOneWidget);
    expect(find.text('GRADED'), findsOneWidget);
    expect(find.text('Price range'), findsOneWidget);
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('Sold listings'), findsOneWidget);
    expect(find.text('PSA 10'), findsOneWidget);
    expect(find.text(r'$215.00'), findsWidgets);
  });

  testWidgets('owned Price Tab selectors update visible series rows', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Price'), 400);
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GRADED'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3m'));
    await tester.pumpAndSettle();

    expect(find.text('90 days ago'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text(r'$780.00'), findsWidgets);
    expect(find.text('Sold listings'), findsOneWidget);
  });

  testWidgets('owned Collection Item can be edited from CardDetail', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);
    await tester.ensureVisible(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('card-detail-scroll')),
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('card-detail-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('OWNERSHIP SUMMARY'), findsOneWidget);
    expect(find.byKey(const Key('card-detail-item-portfolio')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('card-detail-item-quantity')),
      '3',
    );
    await tester.ensureVisible(
      find.byKey(const Key('card-detail-item-grader')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-detail-item-grader')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Raw').last);
    await tester.pumpAndSettle();

    expect(find.text('Condition'), findsOneWidget);
    expect(find.text('Grade'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('card-detail-item-notes')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('card-detail-item-notes')),
      'Cracked slab for binder.',
    );
    await tester.drag(
      find.byKey(const Key('card-detail-collection-items')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('card-detail-item-submit')));
    await tester.pumpAndSettle();

    expect(find.text('OWNERSHIP SUMMARY'), findsNothing);
    expect(find.text('Qty: 3'), findsOneWidget);
    expect(find.text('Raw / Near Mint (NM)'), findsOneWidget);
    expect(find.text('Cracked slab for binder.'), findsOneWidget);
  });

  testWidgets('owned Collection Item shows validation without losing draft', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);
    await tester.ensureVisible(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit item'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('card-detail-scroll')),
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('card-detail-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('card-detail-item-quantity')),
      '0',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CardDetailPage)),
    );
    expect(
      await container
          .read(cardDetailControllerProvider('charizard-ex').notifier)
          .saveCollectionItemDraft(),
      isFalse,
    );
    await tester.pumpAndSettle();

    expect(find.text('Quantity must be at least 1.'), findsOneWidget);
    expect(find.text('OWNERSHIP SUMMARY'), findsOneWidget);
  });

  testWidgets('owned Collection Item can be removed after confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'charizard-ex'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);
    await tester.ensureVisible(find.text('Remove from Portfolio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from Portfolio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('card-detail-scroll')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add to Portfolio'), findsOneWidget);
    expect(find.text('Collection Item'), findsNothing);
    expect(find.text('Price overview'), findsOneWidget);
  });

  testWidgets('unknown CardDetail shows shared failure copy', (tester) async {
    await tester.pumpWidget(const _CardDetailTestApp(cardId: 'missing-card'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CardDetailPage)),
    );
    await container.read(authControllerProvider.notifier).startupComplete;
    await container
        .read(cardDetailControllerProvider('missing-card').notifier)
        .refresh();
    expect(
      container.read(cardDetailControllerProvider('missing-card')).loadStatus,
      KandoLoadStatus.failure,
    );
    await tester.pump();

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
  });

  testWidgets('CardDetail route reads cardId from path', (tester) async {
    await tester.pumpWidget(const _CardDetailRouteApp());
    await tester.pumpAndSettle();

    expect(find.text('Squirtle'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Price overview'), 400);
    expect(find.text('Price overview'), findsOneWidget);
  });
}

class _CardDetailTestApp extends StatelessWidget {
  const _CardDetailTestApp({required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: _cardDetailOverrides,
      child: MaterialApp(home: CardDetailPage(cardId: cardId)),
    );
  }
}

class _CardDetailRouteApp extends StatelessWidget {
  const _CardDetailRouteApp();

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: _cardDetailOverrides,
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/cards/squirtle',
          routes: [
            GoRoute(
              path: '/cards/:cardId',
              builder: (context, state) {
                return CardDetailPage(
                  cardId: state.pathParameters['cardId'] ?? '',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

final _cardDetailAuthStorage = InMemoryAuthStorage();
final _cardDetailAuthRepository = LocalPlaceholderAuthRepository(
  _cardDetailAuthStorage,
);

final _cardDetailOverrides = [
  authStorageProvider.overrideWithValue(_cardDetailAuthStorage),
  authRepositoryProvider.overrideWithValue(_cardDetailAuthRepository),
  cardDetailRepositoryProvider.overrideWithValue(
    const MockCardDetailRepository(),
  ),
];
