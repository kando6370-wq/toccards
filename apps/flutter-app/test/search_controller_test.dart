import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/search/search_controller.dart';
import 'package:kando_app/features/search/search_models.dart';
import 'package:kando_app/features/search/search_repository.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
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
            imageUrl: 'https://img.example/pikachu.jpg',
            rarity: 'Common',
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
            imageUrl: 'https://img.example/pikachu.jpg',
            rarity: 'Common',
          ),
        ],
        sets: const [
          CardDataSetDto(
            setCode: 'BS',
            setName: 'Base Set',
            imageUrl: null,
            cardCount: 102,
          ),
        ],
      );

      final catalog = await HttpSearchRepository(api).loadCatalog();

      expect(api.trendingCalls, 1);
      expect(api.searchSetQueries, ['pokemon']);
      expect(catalog.games.map((game) => game.id), ['tcg', 'sealed']);
      expect(catalog.defaultGame.label, 'TCG');
      expect(catalog.cards.first.id, 'catalog:pikachu-025');
      expect(catalog.cards.first.type, SearchCardType.tcg);
      expect(catalog.cards.first.gameId, 'tcg');
      expect(catalog.cards.first.metadataLine, 'Common #025');
      expect(catalog.cards.first.variantLine, 'Holofoil / English');
      expect(catalog.cards.first.priceText, '--');
      expect(catalog.cards.last.type, SearchCardType.sealed);
      expect(catalog.sets.single.id, 'BS');
      expect(catalog.sets.single.cardCountText, '102 cards');

      final cards = await HttpSearchRepository(api).searchCards('pikachu');
      final sets = await HttpSearchRepository(api).searchSets('base');

      expect(api.searchCardQueries, ['pikachu']);
      expect(api.searchSetQueries, ['pokemon', 'base']);
      expect(cards.single.name, 'Pikachu');
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
      expect(state.searchText, 'pikachu');
      expect(state.visibleCards.map((card) => card.name), ['Pikachu']);
      expect(
        state.catalog.sets.map((set) => set.name),
        containsAll(['Mega Evolution Promos', 'Obsidian Flames']),
      );
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

    controller.toggleWishlist('squirtle');
    expect(
      container
          .read(searchControllerProvider)
          .cardById('squirtle')
          .isWishlisted,
      isTrue,
    );

    expect(controller.toggleCollect('squirtle'), SearchCollectAction.updated);
    final collected = container
        .read(searchControllerProvider)
        .cardById('squirtle');

    expect(collected.quantity, 1);
    expect(collected.isCollected, isTrue);
    expect(collected.isWishlisted, isFalse);

    expect(controller.toggleCollect('squirtle'), SearchCollectAction.updated);
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

      final action = controller.toggleCollect('multi-owned');
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

    expect(card.priceText, '--');
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
  Future<List<SearchCard>> searchCards(String query) {
    return const MockSearchRepository().searchCards(query);
  }

  @override
  Future<List<SearchSet>> searchSets(String query) {
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
  Future<List<SearchCard>> searchCards(String query) async {
    return (await loadCatalog()).cards;
  }

  @override
  Future<List<SearchSet>> searchSets(String query) async {
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

class _RecordingSearchRepository implements SearchRepository {
  const _RecordingSearchRepository({
    this.cardResults = const [],
    this.setResults = const [],
  });

  final List<SearchCard> cardResults;
  final List<SearchSet> setResults;
  static final List<String> _cardQueries = [];
  static final List<String> _setQueries = [];

  List<String> get cardQueries => _cardQueries;
  List<String> get setQueries => _setQueries;

  @override
  Future<SearchCatalog> loadCatalog() {
    _cardQueries.clear();
    _setQueries.clear();
    return const MockSearchRepository().loadCatalog();
  }

  @override
  Future<List<SearchCard>> searchCards(String query) async {
    _cardQueries.add(query);
    return cardResults;
  }

  @override
  Future<List<SearchSet>> searchSets(String query) async {
    _setQueries.add(query);
    return setResults;
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

  @override
  Future<List<CardDataCardDto>> searchCards(String query) async {
    searchCardQueries.add(query);
    return searchCardRows;
  }

  @override
  Future<List<CardDataSetDto>> searchSets(String query) async {
    searchSetQueries.add(query);
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
