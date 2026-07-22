import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'support/mock_search_repository.dart';

void main() {
  test(
    'http search repository builds catalog from card-data API because Search landing must read Workers catalog data',
    () async {
      final api = _FakeCardDataApi(
        trendingCardRows: const [
          CardDataCardDto(
            cardRef: 'catalog:pikachu-025',
            name: 'Pikachu',
            setName: 'Base Set',
            setCode: 'BS',
            cardNumber: '025',
            finish: 'Holofoil',
            language: 'English',
            objectType: 'tcg',
            game: 'Pokemon',
            imageUrl: 'https://img.example/pikachu.jpg',
            rarity: 'Common',
            priceUsd: 32.13,
            previous30dPriceUsd: 30.67,
          ),
          CardDataCardDto(
            cardRef: 'catalog:booster-box',
            name: 'Base Set Booster Box',
            setName: 'Base Set',
            setCode: 'BS',
            cardNumber: 'BOX',
            finish: null,
            language: null,
            objectType: 'sealed',
            game: 'Pokemon',
            imageUrl: null,
            rarity: null,
          ),
        ],
        searchCardRows: const [
          CardDataCardDto(
            cardRef: 'catalog:pikachu-025',
            name: 'Pikachu',
            setName: 'Base Set',
            setCode: 'BS',
            cardNumber: '025',
            finish: 'Holofoil',
            language: 'English',
            objectType: 'tcg',
            game: 'Pokemon',
            imageUrl: 'https://img.example/pikachu.jpg',
            rarity: 'Common',
            priceUsd: 32.13,
            previous30dPriceUsd: 30.67,
          ),
        ],
        sets: const [
          CardDataSetDto(
            setCode: 'BS',
            setName: 'Base Set',
            game: 'Pokemon',
            imageUrl: null,
            cardCount: 102,
          ),
        ],
      );

      final catalog = await HttpSearchRepository(api).loadCatalog();

      expect(api.trendingCalls, 1);
      expect(api.searchSetQueries, ['']);
      expect(api.searchSetGames, ['Pokemon']);
      expect(catalog.games.map((game) => game.id), ['pokemon']);
      expect(catalog.defaultGame.label, 'Pokemon');
      expect(catalog.cards.first.id, 'catalog:pikachu-025');
      expect(catalog.cards.first.type, SearchCardType.tcg);
      expect(catalog.cards.first.gameId, 'pokemon');
      expect(catalog.cards.first.metadataLine, 'Common #025');
      expect(catalog.cards.first.variantLine, 'Holofoil / English');
      expect(
        catalog.cards.first.imageUrl,
        'https://image.tcgcard.fun/cdn-cgi/image/width=360,height=504,fit=scale-down,quality=50,format=auto/cards/catalog%3Apikachu-025.jpg',
      );
      expect(catalog.cards.first.priceText(AppCurrency.usd), r'$32.13');
      expect(catalog.cards.first.changeText, '+4.76%');
      expect(catalog.cards.last.type, SearchCardType.sealed);
      expect(catalog.sets.single.id, 'BS');
      expect(catalog.sets.single.gameId, 'pokemon');
      expect(catalog.sets.single.subtitle, 'Pokemon');
      expect(catalog.sets.single.cardCountText, '102 cards');

      final cards = await HttpSearchRepository(
        api,
      ).searchCards('pikachu', game: 'Pokemon');
      final sets = await HttpSearchRepository(
        api,
      ).searchSets('base', game: 'Pokemon');

      expect(api.searchCardQueries, ['pikachu']);
      expect(api.searchCardGames, ['Pokemon']);
      expect(api.searchSetQueries, ['', 'base']);
      expect(api.searchSetGames, ['Pokemon', 'Pokemon']);
      expect(cards.single.name, 'Pikachu');
      expect(cards.single.priceText(AppCurrency.usd), r'$32.13');
      expect(cards.single.changeText, '+4.76%');
      expect(sets.single.name, 'Base Set');
    },
  );

  test(
    'Cards query replaces current card results after debounce because typed Search must ask Workers for matching cards',
    () async {
      final repository = _RecordingSearchRepository(
        cardResults: const [
          SearchCard(
            id: 'catalog:pikachu-025',
            gameId: 'pokemon',
            type: SearchCardType.tcg,
            name: 'Pikachu',
            priceUsd: null,
            previous30dPriceUsd: null,
            setName: 'Base Set',
            metadataLine: 'Common #025',
            variantLine: 'Holofoil / English',
            quantity: 0,
            isWishlisted: false,
          ),
        ],
      );
      final container = _searchContainer(repository: repository);
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      controller.updateSearch('pikachu');
      await Future<void>.delayed(searchDebounceDuration * 2);
      await controller.loadComplete;

      final state = container.read(searchControllerProvider);
      expect(repository.cardQueries, ['pikachu']);
      expect(repository.cardGames, ['Pokemon']);
      expect(state.searchText, 'pikachu');
      expect(state.visibleCards.map((card) => card.name), ['Pikachu']);
      expect(
        state.catalog.sets.map((set) => set.name),
        containsAll(['Mega Evolution Promos', 'Obsidian Flames']),
      );
    },
  );

  test(
    'changing Game performs a scoped browse and preserves every selector option because Game controls both tabs',
    () async {
      final repository = _RecordingSearchRepository();
      final container = _searchContainer(repository: repository);
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      controller.selectGame('one-piece');
      await Future<void>.delayed(searchDebounceDuration * 2);
      await controller.loadComplete;

      final state = container.read(searchControllerProvider);
      expect(repository.cardQueries, ['']);
      expect(repository.cardGames, ['One Piece']);
      expect(state.selectedGameId, 'one-piece');
      expect(state.catalog.games.map((game) => game.id), [
        'pokemon',
        'lorcana',
        'one-piece',
      ]);
    },
  );

  test(
    'initial Search loads one set page because Cards must not wait for the complete set catalog',
    () async {
      final setCatalogApi = _FakeSetCatalogApi();
      final api = _FakeCardDataApi(
        trendingCardRows: const [],
        searchCardRows: const [
          CardDataCardDto(
            cardRef: '664850',
            name: 'Bravo, Flattering Showman',
            setName: 'Silver Age Chapter 1',
            setCode: '',
            cardNumber: '',
            finish: 'Normal',
            language: 'English',
            objectType: 'tcg',
            game: 'Flesh and Blood TCG',
            imageUrl: null,
            rarity: 'Rare',
          ),
        ],
        sets: const [],
      );

      final catalog = await HttpSearchRepository(
        api,
        setCatalogApi: setCatalogApi,
      ).loadCatalog();

      expect(api.trendingCalls, 0);
      expect(api.searchCardQueries, ['']);
      expect(api.searchCardGames, ['Flesh and Blood TCG']);
      expect(api.searchSetQueries, ['']);
      expect(api.searchSetGames, ['Flesh and Blood TCG']);
      expect(setCatalogApi.searchCalls, 0);
      expect(catalog.defaultGame.label, 'Flesh and Blood TCG');
      expect(catalog.cards.single.id, '664850');
    },
  );

  test(
    'opening Sets loads the complete catalog because the initial page is intentionally partial',
    () async {
      final setCatalogApi = _FakeSetCatalogApi();
      final repository = HttpSearchRepository(
        _FakeCardDataApi(
          trendingCardRows: const [],
          searchCardRows: const [],
          sets: const [],
        ),
        setCatalogApi: setCatalogApi,
      );
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWithValue(_session),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      expect(setCatalogApi.searchCalls, 0);
      controller.selectTab(SearchTab.sets);
      await Future<void>.delayed(searchDebounceDuration * 2);
      await controller.loadComplete;

      expect(setCatalogApi.searchCalls, 1);
    },
  );

  test(
    'loading the next card page appends results because Search pages contain forty cards',
    () async {
      final repository = _PaginatedSearchRepository();
      final container = _searchContainer(repository: repository);
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      expect(
        container.read(searchControllerProvider).visibleCards,
        hasLength(40),
      );
      await controller.loadNextCardPage();

      final state = container.read(searchControllerProvider);
      expect(repository.requestedPages, [2]);
      expect(state.visibleCards, hasLength(41));
      expect(state.visibleCards.last.id, 'card-41');
      expect(state.cardPage, 2);
      expect(state.hasMoreCards, isFalse);
    },
  );

  test(
    'catalog renders before slow asset enrichment because ownership is supplemental',
    () async {
      const catalogCard = CardDataCardDto(
        cardRef: 'catalog:fast-card',
        name: 'Fast Catalog Card',
        setName: 'Fast Set',
        setCode: 'FAST',
        cardNumber: '1',
        finish: 'Normal',
        language: 'English',
        objectType: 'tcg',
        imageUrl: null,
        rarity: 'Rare',
      );
      final gate = Completer<void>();
      final repository = HttpSearchRepository(
        _FakeCardDataApi(trendingCardRows: const [catalogCard], sets: const []),
        portfolioApi: _FakePortfolioApi(assetLoadGate: gate),
      );
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWithValue(_session),
        ],
      );
      addTearDown(container.dispose);

      container.read(searchControllerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      var state = container.read(searchControllerProvider);
      expect(state.isLoading, isFalse);
      expect(state.visibleCards.single.name, catalogCard.name);
      expect(state.assetStatus, KandoLoadStatus.loading);

      gate.complete();
      await container.read(searchControllerProvider.notifier).loadComplete;
      state = container.read(searchControllerProvider);
      expect(state.assetStatus, KandoLoadStatus.content);
    },
  );

  test(
    'collect and wishlist update immediately while backend mutations are pending',
    () async {
      final wishlistGate = Completer<void>();
      final collectionGate = Completer<void>();
      final portfolioApi = _FakePortfolioApi(
        wishlistMutationGate: wishlistGate,
        collectionMutationGate: collectionGate,
      );
      final repository = HttpSearchRepository(
        _FakeCardDataApi(
          trendingCardRows: const [
            CardDataCardDto(
              cardRef: '9359',
              name: 'Escape Artist',
              setName: 'Odyssey',
              setCode: 'ODY',
              cardNumber: '1',
              finish: 'Normal',
              language: 'English',
              objectType: 'tcg',
              imageUrl: null,
              rarity: 'Common',
            ),
          ],
          sets: const [],
        ),
        portfolioApi: portfolioApi,
      );
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWithValue(_session),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      final wishlist = controller.toggleWishlist('9359');
      expect(
        container.read(searchControllerProvider).cardById('9359').isWishlisted,
        isTrue,
      );
      wishlistGate.complete();
      expect(await wishlist, isTrue);

      final collect = controller.toggleCollect('9359');
      final optimistic = container
          .read(searchControllerProvider)
          .cardById('9359');
      expect(optimistic.quantity, 1);
      expect(optimistic.isWishlisted, isFalse);
      collectionGate.complete();
      expect(await collect, SearchCollectAction.updated);
    },
  );

  test(
    'Search loads and mutates backend asset state because Qty Collect and Wishlist must survive page refresh',
    () async {
      final portfolioApi = _FakePortfolioApi(
        items: [_portfolioItem(id: 'item-1', quantity: 2)],
      );
      final repository = HttpSearchRepository(
        _FakeCardDataApi(
          trendingCardRows: const [
            CardDataCardDto(
              cardRef: '9359',
              name: 'Escape Artist',
              setName: 'Odyssey',
              setCode: 'ODY',
              cardNumber: '',
              finish: 'Normal',
              language: 'English',
              objectType: 'tcg',
              imageUrl: null,
              rarity: 'Common',
              priceUsd: 0.21,
              previous30dPriceUsd: 0.17,
            ),
          ],
          sets: const [],
        ),
        portfolioApi: portfolioApi,
      );
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWithValue(_session),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      var card = container.read(searchControllerProvider).cardById('9359');
      expect(card.quantity, 2);
      expect(card.collectionItemId, 'item-1');

      controller.updateSearch('escape');
      await Future<void>.delayed(searchDebounceDuration * 2);
      await controller.loadComplete;
      controller.updateSearch('');
      await controller.loadComplete;
      card = container.read(searchControllerProvider).cardById('9359');
      expect(card.quantity, 2);
      expect(card.collectionItemId, 'item-1');

      final collect = controller.toggleCollect('9359');
      expect(
        await controller.toggleCollect('9359'),
        SearchCollectAction.ignored,
      );
      expect(await collect, SearchCollectAction.updated);
      expect(portfolioApi.deletedCollectionItemIds, ['item-1']);

      expect(await controller.toggleWishlist('9359'), isTrue);
      card = container.read(searchControllerProvider).cardById('9359');
      expect(card.wishlistItemId, 'wishlist-1');

      controller.updateSearch('escape');
      await Future<void>.delayed(searchDebounceDuration * 2);
      await controller.loadComplete;
      controller.updateSearch('');
      await controller.loadComplete;
      card = container.read(searchControllerProvider).cardById('9359');
      expect(card.wishlistItemId, 'wishlist-1');
      expect(card.isWishlisted, isTrue);

      expect(
        await controller.toggleCollect('9359'),
        SearchCollectAction.updated,
      );
      final draft = portfolioApi.lastCollectedDraft!;
      expect(draft.folderId, 'folder-main');
      expect(draft.condition, 'Near Mint (NM)');
      expect(draft.language, 'English');
      expect(draft.finish, 'Normal');
      expect(portfolioApi.wishlistItems, isEmpty);
      card = container.read(searchControllerProvider).cardById('9359');
      expect(card.quantity, 1);
      expect(card.isWishlisted, isFalse);
    },
  );

  test(
    'asset enrichment failure keeps primary card results visible because collection state is supplemental',
    () async {
      final repository = HttpSearchRepository(
        _FakeCardDataApi(
          trendingCardRows: const [
            CardDataCardDto(
              cardRef: '9359',
              name: 'Escape Artist',
              setName: 'Odyssey',
              setCode: 'ODY',
              cardNumber: '',
              finish: 'Normal',
              language: 'English',
              objectType: 'tcg',
              game: 'Magic: The Gathering',
              imageUrl: null,
              rarity: 'Common',
            ),
          ],
          sets: const [],
        ),
        portfolioApi: _FakePortfolioApi(failAssetLoad: true),
      );
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWithValue(_session),
        ],
      );
      addTearDown(container.dispose);

      final state = await _loadedSearchState(container);

      expect(state.isUnavailable, isFalse);
      expect(state.visibleCards.single.name, 'Escape Artist');
    },
  );

  test(
    'Sets query replaces current set results after debounce because set search has a separate Workers endpoint',
    () async {
      final repository = _RecordingSearchRepository(
        setResults: const [
          SearchSet(
            id: 'base-set',
            gameId: 'pokemon',
            name: 'Base Set',
            subtitle: 'Pokemon catalog set',
            releaseText: 'BS',
            cardCountText: '102 cards',
          ),
        ],
      );
      final container = _searchContainer(repository: repository);
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      controller.selectTab(SearchTab.sets);
      controller.updateSearch('base');
      await Future<void>.delayed(searchDebounceDuration * 2);
      await controller.loadComplete;

      final state = container.read(searchControllerProvider);
      expect(repository.setQueries, ['base']);
      expect(state.searchText, 'base');
      expect(state.visibleSets.map((set) => set.name), ['Base Set']);
    },
  );

  test(
    'mutation conflicts reload backend assets because stale Search icons must reflect existing ownership',
    () async {
      final portfolioApi = _FakePortfolioApi(
        conflictOnWishlist: true,
        conflictOnCollect: true,
      );
      final repository = HttpSearchRepository(
        _FakeCardDataApi(
          trendingCardRows: const [
            CardDataCardDto(
              cardRef: '9359',
              name: 'Escape Artist',
              setName: 'Odyssey',
              setCode: 'ODY',
              cardNumber: '',
              finish: 'Normal',
              language: 'English',
              objectType: 'tcg',
              imageUrl: null,
              rarity: 'Common',
              priceUsd: 0.21,
              previous30dPriceUsd: 0.17,
            ),
          ],
          sets: const [],
        ),
        portfolioApi: portfolioApi,
      );
      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repository),
          searchSessionProvider.overrideWithValue(_session),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      expect(await controller.toggleWishlist('9359'), isTrue);
      expect(
        container.read(searchControllerProvider).cardById('9359').isWishlisted,
        isTrue,
      );
      expect(
        await controller.toggleCollect('9359'),
        SearchCollectAction.updated,
      );
      final card = container.read(searchControllerProvider).cardById('9359');
      expect(card.isCollected, isTrue);
      expect(card.isWishlisted, isFalse);
    },
  );

  test('defaults to Cards tab and Pokemon results', () async {
    final container = _searchContainer();
    addTearDown(container.dispose);

    final state = await _loadedSearchState(container);

    expect(state.selectedTab, SearchTab.cards);
    expect(state.selectedGame.label, 'Pokemon');
    expect(state.visibleCards.map((card) => card.name), [
      'Squirtle',
      'Charizard ex',
      'Mystery Promo',
    ]);
    expect(state.cardById('squirtle').previous30dPriceUsd, 30.67);
    expect(state.cardById('squirtle').changeText, '+4.76%');
    expect(state.cardById('charizard-ex').previous30dPriceUsd, 721.58);
    expect(state.cardById('charizard-ex').changeText, '+8.10%');
    expect(state.visibleSets.map((set) => set.name), [
      'Mega Evolution Promos',
      'Obsidian Flames',
    ]);
  });

  test(
    'repository failure shows page failure and refresh restores search',
    () async {
      final repository = _FailingThenSuccessfulSearchRepository();
      final container = _searchContainer(repository: repository);
      addTearDown(container.dispose);

      final failed = await _loadedSearchState(container);

      expect(failed.loadStatus, KandoLoadStatus.failure);
      expect(failed.isUnavailable, isTrue);
      expect(repository.calls, 1);

      await container.read(searchControllerProvider.notifier).refresh();
      final restored = container.read(searchControllerProvider);

      expect(restored.loadStatus, KandoLoadStatus.content);
      expect(restored.isUnavailable, isFalse);
      expect(
        restored.visibleCards.map((card) => card.name),
        contains('Squirtle'),
      );
      expect(repository.calls, 2);
    },
  );

  test(
    'Cards query failure stays in Cards because Sets must remain usable and the failed query must be retryable',
    () async {
      final repository = _FailingCardSearchRepository();
      final container = _searchContainer(repository: repository);
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      controller.updateSearch('squirtle');
      await Future<void>.delayed(searchDebounceDuration * 2);
      await controller.loadComplete;

      var state = container.read(searchControllerProvider);
      expect(state.isUnavailable, isFalse);
      expect(state.isCurrentSearchUnavailable, isTrue);

      controller.selectTab(SearchTab.sets);
      state = container.read(searchControllerProvider);
      expect(state.isCurrentSearchUnavailable, isFalse);
      expect(state.visibleSets, isNotEmpty);

      controller.selectTab(SearchTab.cards);
      controller.retrySearch();
      await Future<void>.delayed(searchDebounceDuration * 2);
      await controller.loadComplete;

      state = container.read(searchControllerProvider);
      expect(repository.cardCalls, 2);
      expect(state.isCurrentSearchUnavailable, isFalse);
      expect(state.visibleCards.map((card) => card.name), ['Squirtle']);
    },
  );

  test('Cards and Sets search state stays independent', () async {
    final container = _searchContainer();
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);
    await controller.loadComplete;

    controller.updateSearch('charizard');
    expect(
      container.read(searchControllerProvider).visibleCards.single.name,
      'Charizard ex',
    );

    controller.selectTab(SearchTab.sets);
    expect(container.read(searchControllerProvider).searchText, '');

    controller.updateSearch('mega');
    expect(
      container.read(searchControllerProvider).visibleSets.single.name,
      'Mega Evolution Promos',
    );

    controller.selectTab(SearchTab.cards);
    expect(container.read(searchControllerProvider).searchText, 'charizard');
  });

  test('clear search only affects the current tab', () async {
    final container = _searchContainer();
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);
    await controller.loadComplete;

    controller.updateSearch('squirtle');
    controller.selectTab(SearchTab.sets);
    controller.updateSearch('flames');
    controller.clearSearch();

    expect(container.read(searchControllerProvider).searchText, '');
    controller.selectTab(SearchTab.cards);
    expect(container.read(searchControllerProvider).searchText, 'squirtle');
  });

  test(
    'switching game clears current tab search and refreshes results',
    () async {
      final container = _searchContainer();
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      controller.updateSearch('squirtle');
      controller.selectGame('lorcana');
      final state = container.read(searchControllerProvider);

      expect(state.selectedGame.label, 'Lorcana');
      expect(state.searchText, '');
      expect(state.visibleCards.map((card) => card.name), ['Lorcana Elsa']);
    },
  );

  test('Collect updates Qty and removes Wishlist state', () async {
    final container = _searchContainer();
    addTearDown(container.dispose);
    final controller = container.read(searchControllerProvider.notifier);
    await controller.loadComplete;

    await controller.toggleWishlist('squirtle');
    expect(
      container
          .read(searchControllerProvider)
          .cardById('squirtle')
          .isWishlisted,
      isTrue,
    );

    expect(
      await controller.toggleCollect('squirtle'),
      SearchCollectAction.updated,
    );
    final collected = container
        .read(searchControllerProvider)
        .cardById('squirtle');

    expect(collected.quantity, 1);
    expect(collected.isCollected, isTrue);
    expect(collected.isWishlisted, isFalse);

    expect(
      await controller.toggleCollect('squirtle'),
      SearchCollectAction.updated,
    );
    expect(
      container.read(searchControllerProvider).cardById('squirtle').quantity,
      0,
    );
  });

  test(
    'Collect on a card with multiple collection items requests detail management',
    () async {
      final container = _searchContainer(
        repository: const _MultiCollectionSearchRepository(),
      );
      addTearDown(container.dispose);
      final controller = container.read(searchControllerProvider.notifier);
      await controller.loadComplete;

      final action = await controller.toggleCollect('multi-owned');
      final card = container
          .read(searchControllerProvider)
          .cardById('multi-owned');

      expect(action, SearchCollectAction.openDetail);
      expect(card.quantity, 2);
      expect(card.collectionItemCount, 2);
    },
  );

  test('missing price and change use PRD fallback text', () async {
    final container = _searchContainer();
    addTearDown(container.dispose);

    final card = (await _loadedSearchState(
      container,
    )).cardById('mystery-promo');

    expect(card.priceText(AppCurrency.usd), '--');
    expect(card.previous30dPriceUsd, isNull);
    expect(card.changeText, '-/-');
  });
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

class _MultiCollectionSearchRepository implements SearchRepository {
  const _MultiCollectionSearchRepository();

  @override
  Future<SearchCatalog> loadCatalog() async {
    return const SearchCatalog(
      games: [SearchGame(id: 'pokemon', label: 'Pokemon')],
      cards: [
        SearchCard(
          id: 'multi-owned',
          gameId: 'pokemon',
          type: SearchCardType.tcg,
          name: 'Multi Owned',
          priceUsd: 10,
          previous30dPriceUsd: 9,
          setName: 'Test Set',
          metadataLine: 'Promo 001',
          variantLine: 'Raw Near Mint (NM)',
          quantity: 2,
          collectionItemCount: 2,
          isWishlisted: false,
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
  Future<List<SearchSet>> searchSets(String query, {String? game}) async {
    return const [];
  }
}

ProviderContainer _searchContainer({
  SearchRepository repository = const MockSearchRepository(),
}) {
  return ProviderContainer(
    overrides: [searchRepositoryProvider.overrideWithValue(repository)],
  );
}

Future<SearchState> _loadedSearchState(ProviderContainer container) async {
  await container.read(searchControllerProvider.notifier).loadComplete;
  return container.read(searchControllerProvider);
}

class _PaginatedSearchRepository
    implements SearchRepository, PaginatedSearchRepository {
  final requestedPages = <int>[];

  @override
  Future<SearchCatalog> loadCatalog() async {
    return SearchCatalog(
      games: const [SearchGame(id: 'pokemon', label: 'Pokemon')],
      cards: List.generate(40, (index) => _card(index + 1)),
      sets: const [],
    );
  }

  @override
  Future<List<SearchCard>> searchCardPage(
    String query, {
    String? game,
    required int page,
  }) async {
    requestedPages.add(page);
    return page == 2 ? [_card(41)] : const [];
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) async {
    return (await loadCatalog()).cards;
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) async {
    return const [];
  }

  static SearchCard _card(int index) {
    return SearchCard(
      id: 'card-$index',
      gameId: 'pokemon',
      type: SearchCardType.tcg,
      name: 'Card $index',
      priceUsd: index.toDouble(),
      previous30dPriceUsd: index.toDouble(),
      setName: 'Test Set',
      metadataLine: '#$index',
      variantLine: 'Normal',
      quantity: 0,
      isWishlisted: false,
    );
  }
}

class _RecordingSearchRepository implements SearchRepository {
  const _RecordingSearchRepository({
    this.cardResults = const [],
    this.setResults = const [],
  });

  final List<SearchCard> cardResults;
  final List<SearchSet> setResults;
  static final List<String> _cardQueries = [];
  static final List<String> _setQueries = [];
  static final List<String?> _cardGames = [];
  static final List<String?> _setGames = [];

  List<String> get cardQueries => _cardQueries;
  List<String> get setQueries => _setQueries;
  List<String?> get cardGames => _cardGames;
  List<String?> get setGames => _setGames;

  @override
  Future<SearchCatalog> loadCatalog() {
    _cardQueries.clear();
    _setQueries.clear();
    _cardGames.clear();
    _setGames.clear();
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) async {
    _cardQueries.add(query);
    _cardGames.add(game);
    return cardResults;
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) async {
    _setQueries.add(query);
    _setGames.add(game);
    return setResults;
  }
}

class _FakeSetCatalogApi implements SetCatalogApi {
  var searchCalls = 0;

  @override
  Future<List<CardDataGameDto>> listGames() async {
    return const [
      CardDataGameDto(id: 'fab', name: 'Flesh and Blood TCG'),
      CardDataGameDto(id: 'pokemon', name: 'Pokemon'),
    ];
  }

  @override
  Future<List<CardDataSetDto>> searchCatalogSets(
    String query, {
    String? game,
  }) async {
    searchCalls += 1;
    return const [];
  }

  @override
  Future<List<CardDataCardDto>> cardsForSet(
    String setCode, {
    required String game,
    int page = 1,
  }) async {
    return const [];
  }
}

class _FakeCardDataApi implements CardDataApi {
  _FakeCardDataApi({
    required this.trendingCardRows,
    required this.sets,
    this.searchCardRows = const [],
  });

  final List<CardDataCardDto> trendingCardRows;
  final List<CardDataCardDto> searchCardRows;
  final List<CardDataSetDto> sets;
  var trendingCalls = 0;
  final List<String> searchCardQueries = [];
  final List<String> searchSetQueries = [];
  final List<String?> searchCardGames = [];
  final List<String?> searchSetGames = [];

  @override
  Future<List<CardDataCardDto>> searchCards(
    String query, {
    String? game,
  }) async {
    searchCardQueries.add(query);
    searchCardGames.add(game);
    return searchCardRows;
  }

  @override
  Future<List<CardDataSetDto>> searchSets(String query, {String? game}) async {
    searchSetQueries.add(query);
    searchSetGames.add(game);
    return sets;
  }

  @override
  Future<List<CardDataCardDto>> trendingCards() async {
    trendingCalls += 1;
    return trendingCardRows;
  }

  @override
  Future<CardDataCardDto> getCard(String cardRef) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataMarketPriceDto>> getMarketPrices(String cardRef) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataPricePointDto>> getPriceSeries(
    String cardRef, {
    required int days,
    String grader = 'Raw',
    double? grade,
    String? condition,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<CardDataSoldListingDto>> getSoldListings(String cardRef) async {
    throw UnimplementedError();
  }
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  anonymousId: 'anonymous-search',
  accessToken: 'access-search',
  refreshToken: 'refresh-search',
);

class _FakePortfolioApi extends Fake implements PortfolioApi {
  _FakePortfolioApi({
    List<PortfolioItemDto> items = const [],
    this.conflictOnWishlist = false,
    this.conflictOnCollect = false,
    this.failAssetLoad = false,
    this.assetLoadGate,
    this.wishlistMutationGate,
    this.collectionMutationGate,
  }) : collectionItems = [...items];

  final List<PortfolioItemDto> collectionItems;
  final List<WishlistItemDto> wishlistItems = [];
  final List<String> deletedCollectionItemIds = [];
  PortfolioItemDraftDto? lastCollectedDraft;
  final bool conflictOnWishlist;
  final bool conflictOnCollect;
  final bool failAssetLoad;
  final Completer<void>? assetLoadGate;
  final Completer<void>? wishlistMutationGate;
  final Completer<void>? collectionMutationGate;

  @override
  Future<List<PortfolioFolderDto>> listFolders(AuthSession session) async {
    return const [
      PortfolioFolderDto(
        id: 'folder-main',
        name: 'Main',
        isDefault: true,
        sortOrder: 100,
      ),
    ];
  }

  @override
  Future<List<PortfolioItemDto>> listCollectionItems(
    AuthSession session,
  ) async {
    await assetLoadGate?.future;
    if (failAssetLoad) throw StateError('asset state unavailable');
    return [...collectionItems];
  }

  @override
  Future<List<WishlistItemDto>> listWishlistItems(AuthSession session) async {
    return [...wishlistItems];
  }

  @override
  Future<PortfolioItemDto> quickCollect(
    AuthSession session, {
    required String cardRef,
    required PortfolioItemDraftDto draft,
  }) async {
    await collectionMutationGate?.future;
    lastCollectedDraft = draft;
    wishlistItems.removeWhere((item) => item.cardRef == cardRef);
    final item = _portfolioItem(id: 'item-created', quantity: draft.quantity);
    collectionItems.add(item);
    if (conflictOnCollect) throw StateError('already collected');
    return item;
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) async {
    await collectionMutationGate?.future;
    deletedCollectionItemIds.add(itemId);
    collectionItems.removeWhere((item) => item.id == itemId);
  }

  @override
  Future<WishlistItemDto> addWishlist(
    AuthSession session,
    String cardRef,
  ) async {
    await wishlistMutationGate?.future;
    final item = WishlistItemDto(
      id: 'wishlist-1',
      cardRef: cardRef,
      createdAt: DateTime.utc(2026, 7, 15),
    );
    wishlistItems.add(item);
    if (conflictOnWishlist) throw StateError('already wishlisted');
    return item;
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) async {
    await wishlistMutationGate?.future;
    wishlistItems.removeWhere((item) => item.id == itemId);
  }
}

PortfolioItemDto _portfolioItem({required String id, required int quantity}) {
  return PortfolioItemDto(
    id: id,
    folderId: 'folder-main',
    cardRef: '9359',
    objectType: 'tcg',
    grader: 'Raw',
    condition: 'Near Mint (NM)',
    grade: null,
    language: 'English',
    finish: 'Normal',
    quantity: quantity,
    purchasePrice: null,
    purchaseCurrency: null,
    notes: null,
    createdAt: DateTime.utc(2026, 7, 15),
    updatedAt: DateTime.utc(2026, 7, 15),
  );
}
