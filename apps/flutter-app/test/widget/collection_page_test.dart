import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  testWidgets('Collection shows Portfolio summary and rows by default', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    expect(find.text('Collection'), findsWidgets);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(find.text('3 cards'), findsOneWidget);
    expect(find.text('2 graded'), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text(r'$780.00'), findsOneWidget);
    expect(find.text('Qty: 1'), findsWidgets);
  });

  testWidgets('Collection renders money in the shared selected currency', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedCurrencyProvider.overrideWith(
            () => _TestSelectedCurrencyController(AppCurrency.eur),
          ),
        ],
        child: const _CollectionTestApp(),
      ),
    );

    expect(find.textContaining('1,132.95'), findsOneWidget);
    expect(find.textContaining('709.80'), findsOneWidget);
    expect(find.text('+8.10%'), findsOneWidget);
  });

  testWidgets('page failure shows Refresh and restores collection content', (
    tester,
  ) async {
    final repository = _FailingThenSuccessfulCollectionRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectionRepositoryProvider.overrideWithValue(repository)],
        child: const _CollectionTestApp(),
      ),
    );

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
    expect(find.text('Collection'), findsWidgets);
    expect(repository.calls, 1);

    await tester.tap(find.text(refreshText));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(repository.calls, 2);
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

    expect(find.text(hiddenMoneyText), findsWidgets);
    expect(find.text(r'$1,245.00'), findsNothing);
    expect(find.text('+8.10%'), findsOneWidget);
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

  testWidgets('Collection bottom navigation can return Home and Profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CollectionTestAppWithRoutes()),
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.text('Collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Guest session'), findsOneWidget);
  });

  testWidgets('Collection bottom navigation can open Search', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CollectionTestAppWithRoutes()),
    );

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets(
    'Portfolio empty state actions open Scan and Search because empty collections must have recovery paths',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: _CollectionTestAppWithRoutes()),
      );

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      expect(find.text('No cards in this portfolio yet.'), findsOneWidget);

      await tester.tap(find.text('Scan a Card'));
      await tester.pumpAndSettle();

      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Review Your Matches'), findsOneWidget);

      await tester.tap(find.text('Collection'));
      await tester.pumpAndSettle();

      expect(find.text('No cards in this portfolio yet.'), findsOneWidget);

      await tester.tap(find.text('Search Cards'));
      await tester.pumpAndSettle();

      expect(find.text('Search cards, sets, or characters'), findsOneWidget);
      expect(find.text('Squirtle'), findsOneWidget);
    },
  );

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _CollectionTestAppWithRoutes()),
    );

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Review Your Matches'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });
}

class _CollectionTestApp extends StatelessWidget {
  const _CollectionTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CollectionPage());
  }
}

class _CollectionTestAppWithRoutes extends StatelessWidget {
  const _CollectionTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/collection',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(
            path: '/collection',
            builder: (context, state) => const CollectionPage(),
          ),
          GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
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

class _TestSelectedCurrencyController extends SelectedCurrencyController {
  _TestSelectedCurrencyController(this.initialCurrency);

  final AppCurrency initialCurrency;

  @override
  AppCurrency build() {
    return initialCurrency;
  }
}

class _FailingThenSuccessfulCollectionRepository
    implements CollectionRepository {
  var calls = 0;

  @override
  CollectionDashboard loadDashboard() {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock collection unavailable');
    }
    return const MockCollectionRepository().loadDashboard();
  }
}
