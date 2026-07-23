import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/collection/collection_repository.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_collection_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  testWidgets('Collection filter matches the 390x884 Figma viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 884);
    addTearDown(tester.view.reset);

    await _pumpCollection(tester);
    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();

    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('Price: High to Low'), findsOneWidget);
    expect(find.text('Price: Low to High'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Pokemon'), findsOneWidget);
    expect(find.byKey(const Key('collection-filter-apply')), findsOneWidget);
    expect(
      tester
          .getBottomRight(find.byKey(const Key('collection-filter-apply')))
          .dy,
      lessThanOrEqualTo(884),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Collection shows Portfolio summary and rows by default', (
    tester,
  ) async {
    await _pumpCollection(tester);

    expect(find.byKey(const Key('collection-pull-to-refresh')), findsOneWidget);
    expect(find.text('collection'), findsOneWidget);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(find.text('4 cards'), findsOneWidget);
    expect(find.text('2 graded'), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text(r'$780.00'), findsOneWidget);
    expect(find.text('Qty: 1'), findsWidgets);
  });

  testWidgets('Collection restores the server currency preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const _PreferenceCollectionRepository(),
          ),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

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
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(repository),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.text(refreshText), findsOneWidget);
    expect(find.text('collection'), findsOneWidget);
    expect(repository.calls, 1);

    await tester.tap(find.text(refreshText));
    await tester.pumpAndSettle();

    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text(r'$1,245.00'), findsOneWidget);
    expect(repository.calls, 2);
  });

  testWidgets('folder picker changes Portfolio list', (tester) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sealed').last);
    await tester.pumpAndSettle();

    expect(find.text('Sealed'), findsOneWidget);
    expect(find.text('Evolving Skies Booster Box'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });

  testWidgets(
    'folder manager exposes Figma actions and creates a backend folder',
    (tester) async {
      await _pumpCollection(tester);

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();

      expect(find.text('Select Portfolio'), findsOneWidget);
      expect(find.text('DRAG AND DROP TO CHANGE ORDER'), findsOneWidget);
      expect(find.byKey(const Key('collection-folder-add')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('collection-folder-delete-main')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.byKey(const Key('collection-folder-edit-sealed')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('collection-folder-add')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('collection-folder-name-sheet')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      await tester.enterText(
        find.byKey(const Key('collection-folder-name')),
        'Trade',
      );
      await tester.tap(find.byKey(const Key('collection-folder-name-save')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trade'), findsOneWidget);
      expect(
        find.byKey(const Key('collection-folder-default-folder-trade')),
        findsOneWidget,
      );
    },
  );

  testWidgets('folder delete confirmation opens as a bottom sheet', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-folder-delete-sealed')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-folder-delete-sheet')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byKey(const Key('collection-folder-delete-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-folder-delete-sealed')),
      findsNothing,
    );
  });

  testWidgets('Wishlist tab uses wishlist copy and hides quantity', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.text('One Piece Manga Luffy'), findsOneWidget);
    expect(find.textContaining('Qty:'), findsNothing);
  });

  testWidgets('search no-match state is distinct from empty state', (
    tester,
  ) async {
    await _pumpCollection(tester);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No matching cards found.'), findsOneWidget);
    expect(find.text('Try adjusting your search or filters.'), findsOneWidget);
    expect(find.byKey(const Key('collection-no-match-state')), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
    expect(find.text('0 cards'), findsOneWidget);
    expect(find.text('0 graded'), findsOneWidget);
    expect(find.text('No cards in this portfolio yet.'), findsNothing);
  });

  testWidgets('amount toggle masks collection money', (tester) async {
    await _pumpCollection(tester);

    await tester.tap(find.byKey(const Key('collection-hide-amount')));
    await tester.pumpAndSettle();

    expect(find.text(hiddenMoneyText), findsWidgets);
    expect(find.text(r'$1,245.00'), findsNothing);
    expect(find.text('+8.10%'), findsOneWidget);
  });

  testWidgets(
    'amount toggle failure restores money and shows shared Toast because the server preference is authoritative',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const _FailingPreferenceCollectionRepository(),
            ),
          ],
          child: const _CollectionTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('collection-hide-amount')));
      await tester.pump();
      await tester.pump();

      expect(find.text(genericFailureToastText), findsOneWidget);
      expect(find.text(r'$1,245.00'), findsOneWidget);
      expect(find.text(hiddenMoneyText), findsNothing);
    },
  );

  testWidgets('filter sheet applies Game and Language filters', (tester) async {
    await _pumpCollection(tester);

    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Price: High to Low'), findsOneWidget);
    expect(find.text('Price: Low to High'), findsOneWidget);
    expect(find.text('LANGUAGE'), findsOneWidget);
    expect(find.text('GAME / IP'), findsOneWidget);
    await tester.tap(find.text('Japanese').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Pokemon'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Pokemon'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('collection-filter-apply')),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('collection-filter-apply')));
    await tester.pumpAndSettle();

    expect(find.text('Pikachu Promo'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });

  testWidgets('Collection bottom navigation can return Home and Profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kando-tab-collection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in / Sign up'), findsOneWidget);
  });

  testWidgets('Collection bottom navigation can open Search', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          ..._searchOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Search cards, sets, or characters'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets('Collection cards open the detail for their backend card ref', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.text('Charizard ex');
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('Detail charizard-ex'), findsOneWidget);
  });

  testWidgets(
    'Portfolio empty state actions open Scan and Search because empty collections must have recovery paths',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            ..._searchOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
          ],
          child: const _CollectionTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      expect(find.text('Start your portfolio'), findsOneWidget);
      expect(find.text('Scan or search cards to track value'), findsOneWidget);
      expect(
        find.byKey(const Key('collection-portfolio-empty-illustration')),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('SCAN A CARD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SCAN A CARD'));
      await tester.pumpAndSettle();

      expect(find.text('ALIGN CARD HERE'), findsOneWidget);
      expect(find.byTooltip('Take Photo'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._localAuthOverrides(),
            ..._searchOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
          ],
          child: const _CollectionTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();

      expect(find.text('Start your portfolio'), findsOneWidget);

      await tester.ensureVisible(find.text('SEARCH A CARD'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SEARCH A CARD'));
      await tester.pumpAndSettle();

      expect(find.text('Search cards, sets, or characters'), findsOneWidget);
      expect(find.text('Squirtle'), findsOneWidget);
    },
  );

  testWidgets('Wishlist empty state matches the Figma recovery layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const _EmptyWishlistCollectionRepository(),
          ),
        ],
        child: const _CollectionTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('Your wishlist is empty'), findsOneWidget);
    expect(find.text('Add cards you want to collect later'), findsOneWidget);
    expect(find.text('SEARCH CARDS'), findsOneWidget);
    expect(
      find.byKey(const Key('collection-wishlist-empty-illustration')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('collection-portfolio-summary')), findsNothing);
  });

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          collectionRepositoryProvider.overrideWithValue(
            const MockCollectionRepository(),
          ),
        ],
        child: const _CollectionTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kando-tab-scan')));
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });
}

Future<void> _pumpCollection(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._localAuthOverrides(),
        collectionRepositoryProvider.overrideWithValue(
          const MockCollectionRepository(),
        ),
      ],
      child: const _CollectionTestApp(),
    ),
  );
  await tester.pumpAndSettle();
}

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}

_localAuthOverrides() {
  final storage = InMemoryAuthStorage();
  return [
    authStorageProvider.overrideWithValue(storage),
    authRepositoryProvider.overrideWithValue(
      LocalPlaceholderAuthRepository(storage),
    ),
    currencyRateApiProvider.overrideWithValue(const _TestCurrencyRateApi()),
  ];
}

class _TestCurrencyRateApi implements CurrencyRateApi {
  const _TestCurrencyRateApi();

  @override
  Future<double> loadUsdRate(String targetCurrency) async => 0.91;
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
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
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
          GoRoute(
            path: '/cards/:cardId',
            builder: (context, state) => Scaffold(
              body: Text('Detail ${state.pathParameters['cardId']}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailingThenSuccessfulCollectionRepository
    implements CollectionRepository {
  var calls = 0;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock collection unavailable');
    }
    return const MockCollectionRepository().loadDashboard(session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreferenceCollectionRepository extends MockCollectionRepository {
  const _PreferenceCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(currencyCode: 'EUR');
  }
}

class _FailingPreferenceCollectionRepository extends MockCollectionRepository {
  const _FailingPreferenceCollectionRepository();

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) {
    throw StateError('Preference backend rejected the mutation.');
  }
}

class _EmptyWishlistCollectionRepository extends MockCollectionRepository {
  const _EmptyWishlistCollectionRepository();

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final dashboard = await super.loadDashboard(session);
    return dashboard.copyWith(wishlistItems: const []);
  }
}
