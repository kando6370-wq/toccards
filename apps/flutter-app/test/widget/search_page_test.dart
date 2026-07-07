import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/search/search_page.dart';

void main() {
  testWidgets('Search shows Cards tab with Pokemon results by default', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _SearchTestApp()));

    expect(find.text('Search'), findsWidgets);
    expect(find.text('Pokemon'), findsOneWidget);
    expect(find.text('Cards'), findsWidgets);
    expect(find.text('Sets'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text(r'$32.13'), findsOneWidget);
    expect(find.text('+4.76%'), findsOneWidget);
    expect(find.text('Qty: 0'), findsWidgets);
    expect(find.text('Collect'), findsWidgets);
  });

  testWidgets('search and clear update current tab results', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _SearchTestApp()));

    await tester.enterText(find.byType(TextFormField), 'charizard');
    await tester.pumpAndSettle();
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Squirtle'), findsNothing);

    await tester.tap(find.byKey(const Key('search-clear-button')));
    await tester.pumpAndSettle();
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets('Sets tab keeps its own search state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _SearchTestApp()));

    await tester.enterText(find.byType(TextFormField), 'charizard');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sets'));
    await tester.pumpAndSettle();

    expect(find.text('Mega Evolution Promos'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'flames');
    await tester.pumpAndSettle();
    expect(find.text('Obsidian Flames'), findsOneWidget);

    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.text('Charizard ex'), findsOneWidget);
  });

  testWidgets('Game selector refreshes cards', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _SearchTestApp()));

    await tester.tap(find.text('Pokemon'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lorcana').last);
    await tester.pumpAndSettle();

    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.text('Squirtle'), findsNothing);
  });

  testWidgets('Collect and Wishlist actions update local card state', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _SearchTestApp()));

    await tester.tap(find.byKey(const Key('search-wishlist-squirtle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Collect').first);
    await tester.pumpAndSettle();

    expect(find.text('Collected'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-card-squirtle')),
        matching: find.text('Qty: 1'),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('no matching results state is shown', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _SearchTestApp()));

    await tester.enterText(find.byType(TextFormField), 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No matching results found.'), findsOneWidget);
  });
}

class _SearchTestApp extends StatelessWidget {
  const _SearchTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SearchPage());
  }
}
