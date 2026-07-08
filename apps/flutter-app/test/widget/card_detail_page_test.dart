import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/card_detail/card_detail_page.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  testWidgets('uncollected CardDetail renders identity and price overview', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CardDetailTestApp(cardId: 'squirtle')),
    );

    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text('Pokemon'), findsOneWidget);
    expect(find.text('Mega Evolution Promos'), findsOneWidget);
    expect(find.text('Promo #039'), findsOneWidget);
    expect(find.text('Holofoil'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Collect'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Price overview'), 400);

    expect(find.text('Price overview'), findsOneWidget);
    expect(find.text('Price range'), findsOneWidget);
    expect(find.text('30D'), findsOneWidget);
    expect(find.text('Price series'), findsOneWidget);
    expect(find.text('30 days ago'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('Sold listings'), findsOneWidget);
    expect(find.text('Raw Near Mint'), findsOneWidget);
    expect(find.text(r'$32.13'), findsWidgets);
    expect(find.text('7D +2.19%'), findsOneWidget);
    expect(find.text('Collection Item'), findsNothing);
    expect(find.text('Remove from Portfolio'), findsNothing);
  });

  testWidgets('quick Collect updates quantity and clears Wishlist state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CardDetailTestApp(cardId: 'one-piece-luffy')),
    );

    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.text('Collect'));
    await tester.pumpAndSettle();

    expect(find.text('Collected'), findsOneWidget);
    expect(find.text('Qty: 1'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.byIcon(Icons.ios_share_outlined), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Collection Item'), 400);

    expect(find.text('Collection Item'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text('Raw / Near Mint'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('owned CardDetail defaults to Collection Item content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CardDetailTestApp(cardId: 'charizard-ex')),
    );

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
    expect(find.text(r'$650.00'), findsOneWidget);
    expect(find.text('Pulled from Obsidian Flames binder.'), findsOneWidget);
    expect(find.text('Price overview'), findsNothing);
  });

  testWidgets('owned CardDetail can switch to Price overview', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CardDetailTestApp(cardId: 'charizard-ex')),
    );

    await tester.scrollUntilVisible(find.text('Price'), 400);
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();

    expect(find.text('Price overview'), findsOneWidget);
    expect(find.text('Price range'), findsOneWidget);
    expect(find.text('Market Prices'), findsOneWidget);
    expect(find.text('Sold listings'), findsOneWidget);
    expect(find.text('PSA 10'), findsOneWidget);
    expect(find.text(r'$780.00'), findsWidgets);
  });

  testWidgets('owned Price Tab range selector updates visible series rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CardDetailTestApp(cardId: 'charizard-ex')),
    );

    await tester.scrollUntilVisible(find.text('Price'), 400);
    await tester.tap(find.text('Price'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7D'));
    await tester.pumpAndSettle();

    expect(find.text('7 days ago'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Sold listings'), findsOneWidget);
  });

  testWidgets('unknown CardDetail shows shared failure copy', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CardDetailTestApp(cardId: 'missing-card')),
    );

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
  });

  testWidgets('CardDetail route reads cardId from path', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CardDetailRouteApp()));

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
    return MaterialApp(home: CardDetailPage(cardId: cardId));
  }
}

class _CardDetailRouteApp extends StatelessWidget {
  const _CardDetailRouteApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
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
    );
  }
}
