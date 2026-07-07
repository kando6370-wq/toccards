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

    await tester.scrollUntilVisible(find.text('Price overview'), 400);

    expect(find.text('Price overview'), findsOneWidget);
    expect(find.text('Raw Near Mint'), findsOneWidget);
    expect(find.text(r'$32.13'), findsOneWidget);
    expect(find.text('30D +4.76%'), findsWidgets);
    expect(find.text('Collect'), findsOneWidget);
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
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
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
