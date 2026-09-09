import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_page.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/features/search/set_detail_page.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/portfolio/pending_collection.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/toast.dart';

import '../support/mock_search_repository.dart';
import '../support/in_memory_auth_storage.dart';
import '../support/local_placeholder_auth_repository.dart';
import '../support/mock_card_detail_repository.dart';

void main() {
  testWidgets(
    'set cards show the Cards result details because users need the same collection context from either entry point',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            setCatalogApiClientProvider.overrideWithValue(
              const _PresentationSetCatalogApi(),
            ),
            searchRepositoryProvider.overrideWithValue(
              const MockSearchRepository(),
            ),
          ],
          child: const MaterialApp(
            home: SetDetailPage(
              setId: 'base-set-id',
              game: 'Pokemon',
              setName: 'Base Set',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('search-card-featured'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Pikachu')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Pokemon · Base Set')),
        findsOneWidget,
      );
      expect(find.text('Rare · 025/102'), findsOneWidget);
      expect(find.text('Holo'), findsOneWidget);
      expect(find.text('Qty: 0'), findsOneWidget);
      expect(find.text(r'$12.50'), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('+25.00%')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('search-collect-featured')), findsOneWidget);
      expect(find.byKey(const Key('search-wishlist-featured')), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Pikachu')).style?.fontFamily,
        'Fraunces',
      );
      expect(tester.getSize(card), const Size(170, 378));
      expect(
        tester
            .getSize(
              find.byKey(const Key('search-card-image-container-featured')),
            )
            .height,
        186,
      );

      await tester.tap(find.byKey(const Key('search-collect-featured')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SetDetailPage)),
      );
      expect(
        find.descendant(of: card, matching: find.text('Qty: 0')),
        findsOneWidget,
      );
      expect(container.read(pendingCollectionProvider), hasLength(1));
      expect(
        find.byKey(const Key('pending-collection-notice')),
        findsOneWidget,
      );
      expect(find.text('1 card waiting for details'), findsOneWidget);

      await tester.tap(find.byKey(const Key('search-collect-featured')));
      await tester.pumpAndSettle();

      expect(container.read(pendingCollectionProvider), hasLength(2));
      expect(
        container.read(pendingCollectionProvider).map((item) => item.quantity),
        everyElement(1),
      );
      expect(find.byKey(const Key('search-wishlist-featured')), findsNothing);
      expect(find.text('2 cards waiting for details'), findsOneWidget);
    },
  );

  testWidgets(
    'Set Add All returns to the Set and shows the saved count after the response succeeds',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._setAuthOverrides(),
            setCatalogApiClientProvider.overrideWithValue(
              const _QuickCollectSetCatalogApi(),
            ),
            searchRepositoryProvider.overrideWithValue(
              const MockSearchRepository(),
            ),
            cardDetailRepositoryProvider.overrideWithValue(
              const MockCardDetailRepository(),
            ),
          ],
          child: const _SetQuickCollectRouteApp(),
        ),
      );
      await tester.pumpAndSettle();

      final collect = find.byKey(const Key('search-collect-squirtle'));
      await tester.tap(collect);
      await tester.tap(collect);
      await tester.pumpAndSettle();

      expect(find.text('2 cards waiting for details'), findsOneWidget);
      final setScrollable = find.descendant(
        of: find.byKey(const Key('set-detail-card-grid')),
        matching: find.byType(Scrollable),
      );
      final setPosition = tester
          .state<ScrollableState>(setScrollable.first)
          .position;
      setPosition.jumpTo(setPosition.maxScrollExtent);
      await tester.pump();
      expect(setPosition.pixels, greaterThan(0));
      final router = GoRouter.of(tester.element(find.byType(SetDetailPage)));
      expect(
        router.routeInformationProvider.value.uri.path,
        '/sets/base-set-id',
      );
      await tester.tap(find.byKey(const Key('pending-collection-notice')));
      await tester.pumpAndSettle();

      expect(find.byType(QuickCollectionReviewPage), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/sets/base-set-id',
      );
      await tester.tap(find.byKey(const Key('pending-collection-add-all')));
      await tester.pumpAndSettle();

      expect(find.byType(SetDetailPage), findsOneWidget);
      expect(
        find.byKey(const Key('kando-centered-success-toast')),
        findsOneWidget,
      );
      expect(find.text('2 cards added to your portfolio'), findsOneWidget);
      expect(setPosition.pixels, 0);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SetDetailPage)),
      );
      expect(container.read(pendingCollectionProvider), isEmpty);
      await tester.pump(kandoCenteredSuccessToastDuration);
      await tester.pump();
    },
  );

  testWidgets(
    'Set quick collect uses the Set game because deep links must not inherit an unrelated Search selection',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            setCatalogApiClientProvider.overrideWithValue(
              const _PresentationSetCatalogApi(),
            ),
            searchRepositoryProvider.overrideWithValue(
              const MockSearchRepository(),
            ),
          ],
          child: const MaterialApp(
            home: SetDetailPage(
              setId: 'magic-set-id',
              game: 'Magic: The Gathering',
              setName: 'Magic Set',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('search-collect-featured')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SetDetailPage)),
      );
      expect(
        container.read(pendingCollectionProvider).single.card.game,
        'Magic: The Gathering',
      );
    },
  );

  testWidgets(
    'Set refresh reloads collection assets because Qty and Wishlist must match Search Cards',
    (tester) async {
      final repository = _RefreshingSetSearchRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            setCatalogApiClientProvider.overrideWithValue(
              const _PresentationSetCatalogApi(),
            ),
            searchRepositoryProvider.overrideWithValue(repository),
            searchSessionProvider.overrideWithValue(_setSession),
          ],
          child: const MaterialApp(
            home: SetDetailPage(
              setId: 'base-set-id',
              game: 'Pokemon',
              setName: 'Base Set',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.assetLoads, 1);
      expect(find.text('Qty: 0'), findsOneWidget);
      expect(find.byKey(const Key('search-wishlist-featured')), findsOneWidget);

      final refresh = tester
          .state<RefreshIndicatorState>(
            find.byKey(const Key('set-detail-pull-to-refresh')),
          )
          .show();
      await tester.pumpAndSettle();
      await refresh;

      expect(repository.assetLoads, 2);
      expect(find.text('Qty: 2'), findsOneWidget);
      expect(find.byKey(const Key('search-wishlist-featured')), findsNothing);
    },
  );

  testWidgets('Set quick collect enforces the shared twenty Item limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          setCatalogApiClientProvider.overrideWithValue(
            const _PresentationSetCatalogApi(),
          ),
          searchRepositoryProvider.overrideWithValue(
            const MockSearchRepository(),
          ),
        ],
        child: const MaterialApp(
          home: SetDetailPage(
            setId: 'base-set-id',
            game: 'Pokemon',
            setName: 'Base Set',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SetDetailPage)),
    );
    for (var index = 0; index < pendingCollectionItemLimit; index++) {
      container
          .read(pendingCollectionProvider.notifier)
          .add(
            PendingCollectionCard(
              id: 'queued-$index',
              name: 'Queued $index',
              game: 'Pokemon',
              setName: 'Set',
              metadataLine: '#$index',
              variantLine: 'Normal',
            ),
          );
    }
    await tester.pump();

    await tester.tap(find.byKey(const Key('search-collect-featured')));
    await tester.pump();

    expect(container.read(pendingCollectionProvider), hasLength(20));
    expect(find.text('You can add up to 20 cards at a time.'), findsOneWidget);
    await tester.pump(kandoTopToastDuration);
    await tester.pump();
  });

  testWidgets(
    'failed pagination retries the same page because a transient error must not skip set cards',
    (tester) async {
      final api = _RetrySetCatalogApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [setCatalogApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: SetDetailPage(
              setId: 'base-set-id',
              game: 'Pokemon',
              setName: 'Base Set',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('set-detail-pull-to-refresh')),
        findsOneWidget,
      );
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

  testWidgets(
    'initial failure stays retryable because a PostgreSQL error must not look like an empty set',
    (tester) async {
      final api = _FailingThenSuccessfulSetCatalogApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [setCatalogApiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(
            home: SetDetailPage(
              setId: 'base-set-id',
              game: 'Pokemon',
              setName: 'Base Set',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No content available'), findsOneWidget);
      expect(find.text('No cards available'), findsNothing);

      await tester.tap(find.text('REFRESH'));
      await tester.pumpAndSettle();

      expect(api.requestedPages, [1, 1]);
      expect(find.text('Recovered card'), findsOneWidget);
      expect(find.text('No content available'), findsNothing);
    },
  );

  testWidgets(
    'successful zero rows show the imported-data empty state because an empty set is not a query failure',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            setCatalogApiClientProvider.overrideWithValue(
              const _EmptySetCatalogApi(),
            ),
          ],
          child: const MaterialApp(
            home: SetDetailPage(
              setId: 'base-set-id',
              game: 'Pokemon',
              setName: 'Base Set',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No cards available'), findsOneWidget);
      expect(
        find.text('Cards for this set have not been imported yet.'),
        findsOneWidget,
      );
      expect(find.text('No content available'), findsNothing);
    },
  );
}

class _PresentationSetCatalogApi implements SetCatalogApi {
  const _PresentationSetCatalogApi();

  @override
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page = 1,
  }) async {
    return const [
      CardDataCardDto(
        cardRef: 'featured',
        name: 'Pikachu',
        setName: 'Base Set',
        setCode: 'BS',
        cardNumber: '025/102',
        finish: 'Holo',
        language: 'English',
        objectType: 'tcg',
        game: 'Pokemon',
        imageUrl: null,
        rarity: 'Rare',
        priceUsd: 12.5,
        previous30dPriceUsd: 10,
        priceChange30dPercent: 25,
      ),
    ];
  }

  @override
  Future<List<CardDataGameDto>> listGames() async => const [];

  @override
  Future<List<CardDataSetDto>> searchCatalogSets(
    String query, {
    String? game,
  }) async => const [];
}

class _QuickCollectSetCatalogApi implements SetCatalogApi {
  const _QuickCollectSetCatalogApi();

  @override
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page = 1,
  }) async => [
    const CardDataCardDto(
      cardRef: 'squirtle',
      name: 'Squirtle',
      setName: 'Base Set',
      setCode: 'BS',
      cardNumber: '063/102',
      finish: 'Normal',
      language: 'English',
      objectType: 'tcg',
      game: 'Pokemon',
      imageUrl: null,
      rarity: 'Common',
      priceUsd: 12.5,
      previous30dPriceUsd: 10,
      priceChange30dPercent: 25,
    ),
    ...List.generate(7, (index) => _card('set-card-$index', 'Set Card $index')),
  ];

  @override
  Future<List<CardDataGameDto>> listGames() async => const [];

  @override
  Future<List<CardDataSetDto>> searchCatalogSets(
    String query, {
    String? game,
  }) async => const [];
}

class _SetQuickCollectRouteApp extends StatelessWidget {
  const _SetQuickCollectRouteApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/sets/base-set-id',
        routes: [
          GoRoute(
            path: '/sets/:setId',
            builder: (context, state) => const SetDetailPage(
              setId: 'base-set-id',
              game: 'Pokemon',
              setName: 'Base Set',
            ),
          ),
        ],
      ),
    );
  }
}

_setAuthOverrides() {
  final storage = InMemoryAuthStorage();
  return [
    authStorageProvider.overrideWithValue(storage),
    authRepositoryProvider.overrideWithValue(
      LocalPlaceholderAuthRepository(storage),
    ),
  ];
}

class _RefreshingSetSearchRepository implements SearchAssetRepository {
  var assetLoads = 0;

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
    assetLoads += 1;
    return SearchAssetSnapshot(
      folderId: 'main',
      statesByCardRef: {
        'featured': SearchCardAssetState(
          quantity: assetLoads == 1 ? 0 : 2,
          collectionItemIds: assetLoads == 1 ? const [] : const ['item-1'],
          wishlistItemId: assetLoads == 1 ? 'wish-1' : null,
          collectionInfo: assetLoads == 1 ? null : 'Near Mint (NM)',
        ),
      },
    );
  }

  @override
  Future<WishlistItemDto> addWishlist(AuthSession session, String cardRef) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) {
    throw UnimplementedError();
  }
}

const _setSession = AuthSession(
  ownerType: OwnerType.anonymous,
  anonymousId: 'anonymous-set',
  accessToken: 'access-set',
  refreshToken: 'refresh-set',
);

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

class _FailingThenSuccessfulSetCatalogApi implements SetCatalogApi {
  final requestedPages = <int>[];

  @override
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page = 1,
  }) async {
    requestedPages.add(page);
    if (requestedPages.length == 1) {
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

class _EmptySetCatalogApi implements SetCatalogApi {
  const _EmptySetCatalogApi();

  @override
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page = 1,
  }) async => const [];

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
