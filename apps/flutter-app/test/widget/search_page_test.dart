import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/card_detail/card_detail_page.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/ui/load_state.dart';

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
    expect(find.text('+8.10%'), findsOneWidget);
    expect(find.text('Qty: 0'), findsWidgets);
    expect(find.text('Collect'), findsWidgets);
  });

  testWidgets('page failure shows Refresh and restores search content', (
    tester,
  ) async {
    final repository = _FailingThenSuccessfulSearchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [searchRepositoryProvider.overrideWithValue(repository)],
        child: const _SearchTestApp(),
      ),
    );

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
    expect(find.text('Search'), findsWidgets);
    expect(repository.calls, 1);

    await tester.tap(find.text(refreshText));
    await tester.pumpAndSettle();

    expect(find.text('Squirtle'), findsOneWidget);
    expect(repository.calls, 2);
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

  testWidgets('scanner action shows the shared coming-soon Toast', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _SearchTestApp()));

    await tester.tap(
      find.byWidgetPredicate((widget) {
        return widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.qr_code_scanner_outlined;
      }),
    );
    await tester.pump();

    expect(find.text('This section is coming soon.'), findsOneWidget);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, SnackBarBehavior.floating);
  });

  testWidgets(
    'Search bottom navigation can open Home, Collection, and Profile',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: _SearchTestAppWithRoutes()),
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collection'));
      await tester.pumpAndSettle();
      expect(find.text('Portfolio'), findsWidgets);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Guest session'), findsOneWidget);
    },
  );

  testWidgets('Scan bottom tab opens the Scan placeholder page', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _SearchTestAppWithRoutes()),
    );

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('扫描功能即将上线'), findsOneWidget);
    expect(find.text('Search Cards'), findsOneWidget);
  });

  testWidgets('tapping a Search card opens CardDetail', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _SearchTestAppWithRoutes()),
    );

    await tester.tap(find.byKey(const Key('search-card-squirtle')));
    await tester.pumpAndSettle();

    expect(find.text('Card Detail'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text('Mega Evolution Promos'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Price overview'),
      400,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Price overview'), findsOneWidget);
    expect(find.text('Collect'), findsOneWidget);
  });

  testWidgets('tapping an owned Search card opens owned CardDetail', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _SearchTestAppWithRoutes()),
    );

    await tester.tap(find.byKey(const Key('search-card-charizard-ex')));
    await tester.pumpAndSettle();

    expect(find.text('Card Detail'), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Collection Item'),
      400,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Collection Item'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text('PSA 10'), findsOneWidget);
  });
}

class _SearchTestApp extends StatelessWidget {
  const _SearchTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SearchPage());
  }
}

class _SearchTestAppWithRoutes extends StatelessWidget {
  const _SearchTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => const CollectionPage(),
          ),
          GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
          GoRoute(
            path: '/cards/:cardId',
            builder: (context, state) {
              return CardDetailPage(
                cardId: state.pathParameters['cardId'] ?? '',
              );
            },
          ),
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),
    );
  }
}

class _FailingThenSuccessfulSearchRepository implements SearchRepository {
  var calls = 0;

  @override
  SearchCatalog loadCatalog() {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock search unavailable');
    }
    return const MockSearchRepository().loadCatalog();
  }
}
