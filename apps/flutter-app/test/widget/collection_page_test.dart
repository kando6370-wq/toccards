import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/collection/collection_page.dart';

void main() {
  testWidgets('Collection shows Portfolio summary and rows by default', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    expect(find.text('Collection'), findsWidgets);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text(r'$1,245'), findsOneWidget);
    expect(find.text('3 cards'), findsOneWidget);
    expect(find.text('2 graded'), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Qty: 1'), findsWidgets);
  });

  testWidgets('folder picker changes Portfolio list', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sealed').last);
    await tester.pumpAndSettle();

    expect(find.text('Sealed'), findsOneWidget);
    expect(find.text('Evolving Skies Booster Box'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });

  testWidgets('Wishlist tab uses wishlist copy and hides quantity', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.text('One Piece Manga Luffy'), findsOneWidget);
    expect(find.textContaining('Qty:'), findsNothing);
  });

  testWidgets('search no-match state is distinct from empty state', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No matching cards found.'), findsOneWidget);
    expect(find.text('No cards in this portfolio yet.'), findsNothing);
  });

  testWidgets('amount toggle masks collection money', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.tap(find.byKey(const Key('collection-hide-amount')));
    await tester.pumpAndSettle();

    expect(find.text('••••••'), findsWidgets);
    expect(find.text(r'$1,245'), findsNothing);
    expect(find.text('+8.1%'), findsOneWidget);
  });

  testWidgets('filter sheet applies Game and Language filters', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japanese').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Pikachu Promo'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });
}

class _CollectionTestApp extends StatelessWidget {
  const _CollectionTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CollectionPage());
  }
}
