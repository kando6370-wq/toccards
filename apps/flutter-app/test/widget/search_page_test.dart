import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_page.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_page.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
import 'package:kando_app/features/scan/scan_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_page.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/in_memory_auth_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_card_detail_repository.dart';
import '../support/mock_collection_repository.dart';
import '../support/mock_search_repository.dart';

void main() {
  testWidgets('Search shows Cards tab with Pokemon results by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Search'), findsWidgets);
    expect(find.byKey(const Key('search-pull-to-refresh')), findsOneWidget);
    expect(find.text('Pokemon'), findsOneWidget);
    expect(find.text('Cards'), findsWidgets);
    expect(find.text('Sets'), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Squirtle')).style?.fontFamily,
      'Fraunces',
    );
    expect(find.text(r'$32.13'), findsOneWidget);
    expect(find.text('+4.76%'), findsOneWidget);
    expect(find.text('+8.10%'), findsOneWidget);
    expect(find.text('Qty: 0'), findsWidgets);
    expect(find.byKey(const Key('search-collect-squirtle')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-collect-squirtle')),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('search-wishlist-charizard-ex')), findsNothing);
    expect(find.text('Collect'), findsNothing);

    ProviderScope.containerOf(tester.element(find.byType(SearchPage)))
        .read(selectedCurrencyProvider.notifier)
        .select(AppCurrency.eur.withUsdRate(0.91));
    await tester.pump();

    expect(find.text('€29.24'), findsOneWidget);
    expect(find.text(r'$32.13'), findsNothing);
  });

  testWidgets(
    'Search renders backend card art because Figma cards are not placeholders',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchRepositoryProvider.overrideWithValue(
              const _ImageSearchRepository(),
            ),
          ],
          child: const _SearchTestApp(),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is NetworkImage,
        ),
        findsOneWidget,
      );
      final imageContainer = find.byKey(
        const Key('search-card-image-container-9359'),
      );
      final cardTile = find.byKey(const Key('search-card-9359'));
      final imageClip = find.byKey(const Key('search-card-image-clip-9359'));
      final actionButton = find.byKey(const Key('search-collect-9359'));
      final imageDecoration =
          tester.widget<Container>(imageContainer).decoration as BoxDecoration;
      expect(imageDecoration.border, isNull);
      expect(
        tester.getRect(imageContainer).top,
        tester.getRect(cardTile).top + 14,
      );
      expect(
        tester.getRect(actionButton).top,
        tester.getRect(imageContainer).top - 10,
      );
      expect(
        tester.widget<ClipRRect>(imageClip).borderRadius,
        BorderRadius.circular(6),
      );
      expect(
        tester.getRect(imageClip).top,
        greaterThan(tester.getRect(imageContainer).top),
        reason: 'The image must not cover the card frame top edge.',
      );
      expect(
        tester.getRect(imageClip).bottom,
        lessThan(tester.getRect(imageContainer).bottom),
        reason: 'The image must not cover the card frame bottom edge.',
      );
    },
  );

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
    await tester.pumpAndSettle();

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
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'charizard');
    await tester.pumpAndSettle();
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Squirtle'), findsNothing);

    await tester.tap(find.byKey(const Key('search-clear-button')));
    await tester.pumpAndSettle();
    expect(find.text('Squirtle'), findsOneWidget);
  });

  testWidgets('search field waits for debounce before updating results', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextFormField));
    await tester.enterText(find.byType(TextFormField), 'charizard');
    await tester.pump(
      Duration(milliseconds: searchDebounceDuration.inMilliseconds ~/ 2),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SearchPage)),
    );
    expect(container.read(searchControllerProvider).searchText, '');
    expect(find.text('Squirtle'), findsOneWidget);

    await tester.pump(searchDebounceDuration);
    await tester.pump();

    expect(container.read(searchControllerProvider).searchText, 'charizard');
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Squirtle'), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets(
    'Cards query failure keeps Sets available and Refresh retries Cards',
    (tester) async {
      final repository = _FailingCardSearchRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [searchRepositoryProvider.overrideWithValue(repository)],
          child: const _SearchTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'squirtle');
      await tester.pump(searchDebounceDuration * 2);
      await tester.pump();
      expect(find.text(noContentAvailableText), findsOneWidget);
      expect(find.text(refreshText), findsOneWidget);
      expect(find.text('Sets'), findsOneWidget);

      await tester.tap(find.text('Sets'));
      await tester.pumpAndSettle();
      expect(find.text('Mega Evolution Promos'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);

      await tester.tap(find.text('Cards').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(refreshText));
      await tester.pump(searchDebounceDuration * 2);
      await tester.pump();

      expect(repository.cardCalls, 2);
      expect(find.text('Squirtle'), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);
    },
  );

  testWidgets('Sets tab keeps its own search state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'charizard');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sets'));
    await tester.pumpAndSettle();

    expect(find.text('Mega Evolution Promos'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Mega Evolution Promos')).style?.fontFamily,
      'Fraunces',
    );
    await tester.enterText(find.byType(TextFormField), 'flames');
    await tester.pumpAndSettle();
    expect(find.text('Obsidian Flames'), findsOneWidget);

    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.text('Charizard ex'), findsOneWidget);
  });

  testWidgets('Game selector refreshes cards', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pokemon'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search-game-filter-sheet')), findsOneWidget);
    expect(find.text('GAME / IP'), findsOneWidget);
    expect(find.text('APPLY FILTERS'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-game-filter-lorcana')));
    await tester.pump();
    expect(find.text('Squirtle'), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-game-apply-filter')));
    await tester.pumpAndSettle();

    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.text('Squirtle'), findsNothing);
  });

  testWidgets(
    'switching game shows loading instead of empty state because results are still in flight',
    (tester) async {
      final repository = _BlockingGameSearchRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [searchRepositoryProvider.overrideWithValue(repository)],
          child: const _SearchTestApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pokemon'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search-game-filter-lorcana')));
      await tester.tap(find.byKey(const Key('search-game-apply-filter')));
      await tester.pump();

      expect(find.byKey(const Key('search-results-loading')), findsOneWidget);
      expect(find.text(noContentAvailableText), findsNothing);
      expect(find.byKey(const Key('search-empty-refresh')), findsNothing);

      await repository.completeCardSearch();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-results-loading')), findsNothing);
      expect(find.text('Lorcana Elsa'), findsOneWidget);
    },
  );

  testWidgets('Collect and Wishlist actions update local card state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-wishlist-squirtle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('assets/search/wishlist_on.svg')),
      findsOneWidget,
    );

    final collectButton = find.byKey(const Key('search-collect-squirtle'));
    await tester.ensureVisible(collectButton);
    await tester.pumpAndSettle();
    await tester.tap(collectButton);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('search-card-squirtle')),
        matching: find.byTooltip('Collected'),
      ),
      findsOneWidget,
    );
    expect(find.text('Collected'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('search-card-squirtle')),
        matching: find.byKey(const ValueKey('assets/search/collection_on.svg')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('search-card-squirtle')),
        matching: find.text('Qty: 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assets/search/wishlist_on.svg')),
      findsNothing,
    );
    expect(find.byKey(const Key('search-wishlist-squirtle')), findsNothing);
  });

  testWidgets('Search card action buttons do not open CardDetail', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-wishlist-squirtle')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byKey(const Key('card-detail-hero')), findsNothing);
    expect(
      find.byKey(const ValueKey('assets/search/wishlist_on.svg')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('search-collect-squirtle')));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byKey(const Key('card-detail-hero')), findsNothing);
    expect(find.byKey(const Key('search-wishlist-squirtle')), findsNothing);
  });

  testWidgets('Search card action failures use the top toast', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._localAuthOverrides(),
          searchRepositoryProvider.overrideWithValue(
            const _FailingActionSearchRepository(),
          ),
        ],
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('search-wishlist-squirtle')));
    await tester.pump();

    expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
    expect(find.byKey(const Key('kando-floating-toast')), findsNothing);
    expect(find.text(genericFailureToastText), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();

    await tester.tap(find.byKey(const Key('search-collect-squirtle')));
    await tester.pump();

    expect(find.byKey(const Key('kando-top-toast')), findsOneWidget);
    expect(find.byKey(const Key('kando-floating-toast')), findsNothing);
    expect(find.text(genericFailureToastText), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
  });

  testWidgets('no matching results state is shown', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'missing');
    await tester.pumpAndSettle();

    expect(find.text(noContentAvailableText), findsOneWidget);
    expect(find.byKey(const Key('search-empty-refresh')), findsOneWidget);
    expect(find.text('No matching results found.'), findsNothing);
  });

  testWidgets('scanner action opens Scan workflow', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate((widget) {
        return widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == Icons.photo_camera_outlined;
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
    expect(find.text('This section is coming soon.'), findsNothing);
  });

  testWidgets(
    'Search bottom navigation can open Home, Collection, and Profile',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._searchOverrides(),
            ..._localAuthOverrides(),
            collectionRepositoryProvider.overrideWithValue(
              const MockCollectionRepository(),
            ),
          ],
          child: const _SearchTestAppWithRoutes(),
        ),
      );

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kando-tab-collection')));
      await tester.pumpAndSettle();
      expect(find.text('Portfolio'), findsWidgets);

      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in / Sign up'), findsOneWidget);
    },
  );

  testWidgets('Scan bottom tab opens the Scan workflow page', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _searchOverrides(),
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('kando-tab-scan')));
    await tester.pumpAndSettle();

    expect(find.text('ALIGN CARD HERE'), findsOneWidget);
    expect(find.byTooltip('Take Photo'), findsOneWidget);
  });

  testWidgets('tapping a Search card opens CardDetail', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final squirtleCard = find.byKey(const Key('search-card-squirtle'));
    await tester.ensureVisible(squirtleCard);
    await tester.pumpAndSettle();
    await tester.tap(squirtleCard);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-detail-hero')), findsOneWidget);
    expect(find.text('Squirtle'), findsOneWidget);
    expect(find.text('Add to Portfolio'), findsOneWidget);
    expect(find.text('Collect'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Mega Evolution Promos'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Mega Evolution Promos'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('card-detail-price-chart')),
      400,
      scrollable: find.byType(Scrollable).last,
    );

    expect(find.text('Price'), findsOneWidget);
    expect(find.byKey(const Key('card-detail-price-chart')), findsOneWidget);
  });

  testWidgets(
    'returning from CardDetail restores the selected Search card position',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
          child: const _SearchTestAppWithRoutes(),
        ),
      );
      await tester.pumpAndSettle();

      final searchScroll = find
          .descendant(
            of: find.byType(SearchPage),
            matching: find.byType(Scrollable),
          )
          .first;
      final selectedCard = find.byKey(const Key('search-card-mystery-promo'));
      await tester.scrollUntilVisible(
        selectedCard,
        300,
        scrollable: searchScroll,
      );
      final offsetBeforeOpening = tester
          .state<ScrollableState>(searchScroll)
          .position
          .pixels;
      expect(offsetBeforeOpening, greaterThan(0));

      await tester.tap(selectedCard);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('card-detail-back')));
      await tester.pumpAndSettle();

      final restoredSearchScroll = find
          .descendant(
            of: find.byType(SearchPage),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(
        tester.state<ScrollableState>(restoredSearchScroll).position.pixels,
        closeTo(offsetBeforeOpening, 0.01),
      );
      expect(selectedCard, findsOneWidget);
    },
  );

  testWidgets('tapping an owned Search card opens owned CardDetail', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [..._searchOverrides(), ..._cardDetailOverrides()],
        child: const _SearchTestAppWithRoutes(),
      ),
    );
    await tester.pumpAndSettle();

    final charizardCard = find.byKey(const Key('search-card-charizard-ex'));
    await tester.ensureVisible(charizardCard);
    await tester.pumpAndSettle();
    await tester.tap(charizardCard);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('card-detail-hero')), findsOneWidget);
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

_localAuthOverrides() {
  final storage = InMemoryAuthStorage();
  return [
    authStorageProvider.overrideWithValue(storage),
    authRepositoryProvider.overrideWithValue(
      LocalPlaceholderAuthRepository(storage),
    ),
  ];
}

_cardDetailOverrides() {
  return [
    ..._localAuthOverrides(),
    cardDetailRepositoryProvider.overrideWithValue(
      const MockCardDetailRepository(),
    ),
  ];
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
          GoRoute(path: '/home', builder: (context, state) => const HomePage()),
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
  Future<SearchCatalog> loadCatalog() async {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock search unavailable');
    }
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    return const MockSearchRepository().searchCards(query);
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query);
  }
}

class _BlockingGameSearchRepository implements SearchRepository {
  final _cards = Completer<List<SearchCard>>();

  @override
  Future<SearchCatalog> loadCatalog() {
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    return _cards.future;
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query, game: game);
  }

  Future<void> completeCardSearch() async {
    _cards.complete(
      await const MockSearchRepository().searchCards('', game: 'Lorcana'),
    );
  }
}

class _FailingCardSearchRepository implements SearchRepository {
  var cardCalls = 0;

  @override
  Future<SearchCatalog> loadCatalog() {
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) async {
    cardCalls += 1;
    if (cardCalls == 1) {
      throw StateError('mock card search unavailable');
    }
    return const MockSearchRepository().searchCards(query);
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query);
  }
}

class _ImageSearchRepository implements SearchRepository {
  const _ImageSearchRepository();

  @override
  Future<SearchCatalog> loadCatalog() async {
    return const SearchCatalog(
      games: [SearchGame(id: 'tcg', label: 'TCG')],
      cards: [
        SearchCard(
          id: '9359',
          gameId: 'tcg',
          type: SearchCardType.tcg,
          name: 'Escape Artist',
          priceUsd: 0.21,
          previous30dPriceUsd: 0.17,
          setName: 'Odyssey',
          metadataLine: 'Common',
          variantLine: 'Normal / English',
          quantity: 0,
          isWishlisted: false,
          imageUrl: 'https://api.tcgcard.fun/api/v1/cards/9359/image',
        ),
      ],
      sets: [],
    );
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) async {
    return (await loadCatalog()).cards;
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) async =>
      const [];
}

class _FailingActionSearchRepository implements SearchAssetRepository {
  const _FailingActionSearchRepository();

  @override
  Future<SearchCatalog> loadCatalog() {
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) {
    return const MockSearchRepository().searchCards(query, game: game);
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) {
    return const MockSearchRepository().searchSets(query, game: game);
  }

  @override
  Future<SearchAssetSnapshot> loadAssets(
    AuthSession session, {
    String? selectedFolderId,
  }) async {
    return const SearchAssetSnapshot(
      folderId: 'folder-main',
      statesByCardRef: {},
    );
  }

  @override
  Future<PortfolioItemDto> collect(
    AuthSession session, {
    required SearchCard card,
    required String folderId,
  }) {
    throw StateError('mock collect unavailable');
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) async {}

  @override
  Future<WishlistItemDto> addWishlist(AuthSession session, String cardRef) {
    throw StateError('mock wishlist unavailable');
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) async {}
}

_searchOverrides() {
  return [
    searchRepositoryProvider.overrideWithValue(const MockSearchRepository()),
  ];
}
