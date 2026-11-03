import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/card_detail/card_detail_models.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/portfolio/pending_collection.dart';
import 'package:kando_app/shared/pagination/pagination.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'search_models.dart';
import 'search_repository.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return HttpSearchRepository(
    ref.watch(cardDataApiClientProvider),
    setCatalogApi: ref.watch(setCatalogApiClientProvider),
    portfolioApi: ref.watch(portfolioApiClientProvider),
  );
});

final searchSessionProvider = Provider<AuthSession?>((ref) {
  return ref.watch(authControllerProvider).session;
});

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

const searchDebounceDuration = Duration(milliseconds: 300);

enum SearchCollectAction { updated, limitReached, ignored }

class SearchState {
  const SearchState({
    required SearchCatalog catalog,
    required this.selectedTab,
    required this.selectedGameId,
    required this.searchByTab,
    required this.cardOverrides,
    this.failedSearchTabs = const {},
    this.cardPage = 1,
    this.hasMoreCards = false,
    this.setPage = 1,
    this.hasMoreSets = false,
    this.isLoadingSets = false,
    this.isSearching = false,
    this.isLoadingMoreCards = false,
    this.hasCardPageFailure = false,
    this.isLoadingMoreSets = false,
    this.hasSetPageFailure = false,
    this.assetStatus = KandoLoadStatus.content,
    this.readyAssetCardRefs,
  }) : _catalog = catalog,
       loadStatus = KandoLoadStatus.content;

  const SearchState.unavailable()
    : _catalog = null,
      selectedTab = SearchTab.cards,
      selectedGameId = '',
      searchByTab = const {SearchTab.cards: '', SearchTab.sets: ''},
      cardOverrides = const {},
      failedSearchTabs = const {},
      cardPage = 1,
      hasMoreCards = false,
      setPage = 1,
      hasMoreSets = false,
      isLoadingSets = false,
      isSearching = false,
      isLoadingMoreCards = false,
      hasCardPageFailure = false,
      isLoadingMoreSets = false,
      hasSetPageFailure = false,
      assetStatus = KandoLoadStatus.failure,
      readyAssetCardRefs = null,
      loadStatus = KandoLoadStatus.failure;

  const SearchState.loading()
    : _catalog = null,
      selectedTab = SearchTab.cards,
      selectedGameId = '',
      searchByTab = const {SearchTab.cards: '', SearchTab.sets: ''},
      cardOverrides = const {},
      failedSearchTabs = const {},
      cardPage = 1,
      hasMoreCards = false,
      setPage = 1,
      hasMoreSets = false,
      isLoadingSets = false,
      isSearching = false,
      isLoadingMoreCards = false,
      hasCardPageFailure = false,
      isLoadingMoreSets = false,
      hasSetPageFailure = false,
      assetStatus = KandoLoadStatus.loading,
      readyAssetCardRefs = null,
      loadStatus = KandoLoadStatus.loading;

  const SearchState._({
    required SearchCatalog? catalog,
    required this.selectedTab,
    required this.selectedGameId,
    required this.searchByTab,
    required this.cardOverrides,
    required this.failedSearchTabs,
    required this.cardPage,
    required this.hasMoreCards,
    required this.setPage,
    required this.hasMoreSets,
    required this.isLoadingSets,
    required this.isSearching,
    required this.isLoadingMoreCards,
    required this.hasCardPageFailure,
    required this.isLoadingMoreSets,
    required this.hasSetPageFailure,
    required this.assetStatus,
    required this.readyAssetCardRefs,
    required this.loadStatus,
  }) : _catalog = catalog;

  final SearchCatalog? _catalog;
  final SearchTab selectedTab;
  final String selectedGameId;
  final Map<SearchTab, String> searchByTab;
  final Map<String, SearchCard> cardOverrides;
  final Set<SearchTab> failedSearchTabs;
  final int cardPage;
  final bool hasMoreCards;
  final int setPage;
  final bool hasMoreSets;
  final bool isLoadingSets;
  final bool isSearching;
  final bool isLoadingMoreCards;
  final bool hasCardPageFailure;
  final bool isLoadingMoreSets;
  final bool hasSetPageFailure;
  final KandoLoadStatus assetStatus;
  final Set<String>? readyAssetCardRefs;
  final KandoLoadStatus loadStatus;

  bool isAssetReady(String cardRef) =>
      readyAssetCardRefs?.contains(cardRef) ??
      assetStatus == KandoLoadStatus.content;

  SearchCatalog get catalog {
    final catalog = _catalog;
    if (catalog == null) {
      throw StateError('Search catalog is unavailable.');
    }
    return catalog;
  }

  bool get isUnavailable => loadStatus == KandoLoadStatus.failure;
  bool get isLoading => loadStatus == KandoLoadStatus.loading;
  bool get isCurrentSearchUnavailable => failedSearchTabs.contains(selectedTab);

  SearchGame get selectedGame {
    return catalog.games.firstWhere(
      (game) => game.id == selectedGameId,
      orElse: () => catalog.defaultGame,
    );
  }

  String get searchText => searchByTab[selectedTab] ?? '';

  bool get hasQuery => searchText.trim().isNotEmpty;

  List<SearchCard> get visibleCards {
    return catalog.cards
        .map((card) => cardOverrides[card.id] ?? card)
        .where(_matchesCard)
        .toList();
  }

  List<SearchSet> get visibleSets {
    return catalog.sets.where(_matchesSet).toList();
  }

  bool get isNoMatch {
    if (selectedTab == SearchTab.cards) {
      return visibleCards.isEmpty;
    }

    return visibleSets.isEmpty;
  }

  SearchCard cardById(String id) {
    return cardOverrides[id] ??
        catalog.cards.firstWhere((card) => card.id == id);
  }

  SearchState copyWith({
    SearchTab? selectedTab,
    String? selectedGameId,
    Map<SearchTab, String>? searchByTab,
    Map<String, SearchCard>? cardOverrides,
    Set<SearchTab>? failedSearchTabs,
    int? cardPage,
    bool? hasMoreCards,
    int? setPage,
    bool? hasMoreSets,
    bool? isLoadingSets,
    bool? isSearching,
    bool? isLoadingMoreCards,
    bool? hasCardPageFailure,
    bool? isLoadingMoreSets,
    bool? hasSetPageFailure,
    KandoLoadStatus? assetStatus,
    Set<String>? readyAssetCardRefs,
  }) {
    return SearchState._(
      catalog: _catalog,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedGameId: selectedGameId ?? this.selectedGameId,
      searchByTab: searchByTab ?? this.searchByTab,
      cardOverrides: cardOverrides ?? this.cardOverrides,
      failedSearchTabs: failedSearchTabs ?? this.failedSearchTabs,
      cardPage: cardPage ?? this.cardPage,
      hasMoreCards: hasMoreCards ?? this.hasMoreCards,
      setPage: setPage ?? this.setPage,
      hasMoreSets: hasMoreSets ?? this.hasMoreSets,
      isLoadingSets: isLoadingSets ?? this.isLoadingSets,
      isSearching: isSearching ?? this.isSearching,
      isLoadingMoreCards: isLoadingMoreCards ?? this.isLoadingMoreCards,
      hasCardPageFailure: hasCardPageFailure ?? this.hasCardPageFailure,
      isLoadingMoreSets: isLoadingMoreSets ?? this.isLoadingMoreSets,
      hasSetPageFailure: hasSetPageFailure ?? this.hasSetPageFailure,
      assetStatus: assetStatus ?? this.assetStatus,
      readyAssetCardRefs: readyAssetCardRefs ?? this.readyAssetCardRefs,
      loadStatus: loadStatus,
    );
  }

  bool _matchesCard(SearchCard card) {
    if (card.gameId != selectedGame.id) {
      return false;
    }

    return _matchesSearchTerms(card.searchableText, searchText);
  }

  bool _matchesSet(SearchSet set) {
    if (set.gameId != selectedGame.id) {
      return false;
    }

    return _matchesSearchTerms(set.searchableText, searchText);
  }
}

bool _matchesSearchTerms(String searchableText, String query) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty);
  return terms.every(searchableText.contains);
}

class SearchController extends Notifier<SearchState> {
  Completer<void>? _loadCompleter;
  Timer? _searchDebounce;
  var _loadGeneration = 0;
  SearchAssetSnapshot? _assetSnapshot;
  Future<SearchAssetSnapshot>? _assetLoad;
  var _assetGeneration = 0;
  Object? _assetOwnerKey;
  final _loadedAssetCardRefs = <String>{};
  final _loadedGameByTab = <SearchTab, String>{};
  final _pendingCardMutations = <String>{};

  Future<void> get loadComplete {
    return _loadCompleter?.future ?? Future<void>.value();
  }

  @override
  SearchState build() {
    ref.onDispose(() {
      _searchDebounce?.cancel();
    });
    ref.listen<String?>(selectedPortfolioFolderProvider, (previous, next) {
      if (previous == null || previous == next || state.isLoading) return;
      final repository = ref.read(searchRepositoryProvider);
      if (repository is SearchAssetRepository) {
        _resetAssets();
        _startLoad(
          preserveState: state,
          session: ref.read(searchSessionProvider),
        );
      }
    });
    final repository = ref.watch(searchRepositoryProvider);
    final session = repository is SearchAssetRepository
        ? ref.watch(searchSessionProvider)
        : null;
    final ownerKey = _searchOwnerKey(session);
    if (_assetOwnerKey != ownerKey) _pendingCardMutations.clear();
    _resetAssets();
    _assetOwnerKey = ownerKey;
    if (repository is SearchAssetRepository && session == null) {
      return const SearchState.loading();
    }
    _startLoad(session: session);
    return const SearchState.loading();
  }

  Future<void> refresh() {
    state = const SearchState.loading();
    _resetAssets();
    _startLoad(session: _assetSession);
    return loadComplete;
  }

  Future<void> refreshPreservingContent() {
    if (state.isLoading || state.isUnavailable) return refresh();
    _searchDebounce?.cancel();
    _resetAssets();
    if (state.isLoadingSets) state = state.copyWith(isLoadingSets: false);
    final completer = Completer<void>();
    final generation = ++_loadGeneration;
    _loadCompleter = completer;
    unawaited(
      _loadSearch(
        state.selectedTab,
        state.searchText.trim(),
        generation,
        completer,
      ),
    );
    return loadComplete;
  }

  void _startLoad({SearchState? preserveState, AuthSession? session}) {
    _searchDebounce?.cancel();
    _loadedGameByTab.clear();
    final completer = Completer<void>();
    final generation = ++_loadGeneration;
    _loadCompleter = completer;
    unawaited(_loadCatalog(generation, completer, preserveState, session));
  }

  Future<void> _loadCatalog(
    int generation,
    Completer<void> completer,
    SearchState? preserveState,
    AuthSession? session,
  ) async {
    try {
      final repository = ref.read(searchRepositoryProvider);
      final loadsAssets =
          repository is SearchAssetRepository && session != null;
      final Future<SearchAssetSnapshot?>? earlyAssetsFuture =
          loadsAssets && repository is! SearchVisibleAssetRepository
          ? _loadAssetSnapshot(repository, session).then<SearchAssetSnapshot?>(
              (snapshot) => snapshot,
              onError: (Object error, StackTrace stackTrace) => null,
            )
          : null;
      final catalogLoad = repository is SearchCatalogLoadRepository
          ? await repository.loadCatalogResult()
          : SearchCatalogLoadResult(catalog: await repository.loadCatalog());
      var catalog = catalogLoad.catalog;
      if (!ref.mounted) return;
      final Future<SearchAssetSnapshot?>? assetsFuture =
          loadsAssets && repository is SearchVisibleAssetRepository
          ? _loadAssetSnapshot(
              repository,
              session,
              cardRefs: catalog.cards.map((card) => card.id),
            ).then<SearchAssetSnapshot?>(
              (snapshot) => snapshot,
              onError: (Object error, StackTrace stackTrace) => null,
            )
          : earlyAssetsFuture;
      if (catalog.games.isEmpty) {
        throw StateError('Search catalog needs at least one game.');
      }
      if (generation == _loadGeneration) {
        state = _stateForCatalog(
          catalog,
          preserveState: preserveState ?? state,
          clearOverrides: repository is SearchAssetRepository,
          failedSearchTabs: catalogLoad.failedSearchTabs,
          assetStatus: loadsAssets
              ? KandoLoadStatus.loading
              : KandoLoadStatus.content,
          isLoadingSets: catalogLoad.pendingSets != null,
          hasMoreSets:
              catalogLoad.pendingSets == null &&
              repository is PaginatedSetSearchRepository &&
              catalog.sets.length == kandoPageSize,
        );
        for (final tab in SearchTab.values) {
          if (!catalogLoad.failedSearchTabs.contains(tab) &&
              (tab != SearchTab.sets || catalogLoad.pendingSets == null)) {
            _loadedGameByTab[tab] = state.selectedGame.id;
          }
        }
      }
      final pendingSets = catalogLoad.pendingSets;
      final pendingSetsLoad = pendingSets == null
          ? null
          : () async {
              try {
                final sets = await pendingSets;
                if (!ref.mounted || generation != _loadGeneration) return;
                if (sets == null) {
                  state = state.copyWith(
                    isLoadingSets: false,
                    failedSearchTabs: {
                      ...state.failedSearchTabs,
                      SearchTab.sets,
                    },
                  );
                  return;
                }
                _loadedGameByTab[SearchTab.sets] = state.selectedGame.id;
                state = _stateForCatalog(
                  _catalogWithSets(state.catalog, sets),
                  preserveState: state,
                  failedSearchTabs: state.failedSearchTabs,
                  setPage: 1,
                  hasMoreSets: sets.length == kandoPageSize,
                  isLoadingSets: false,
                );
              } catch (_) {
                if (ref.mounted && generation == _loadGeneration) {
                  state = state.copyWith(
                    isLoadingSets: false,
                    failedSearchTabs: {
                      ...state.failedSearchTabs,
                      SearchTab.sets,
                    },
                  );
                }
              }
            }();
      if (assetsFuture != null) {
        final snapshot = await assetsFuture;
        if (snapshot != null) {
          if (ref.mounted && generation == _loadGeneration) {
            state = _stateForCatalog(
              _catalogWithAssets(state.catalog, snapshot),
              preserveState: state,
              clearOverrides: true,
              failedSearchTabs: state.failedSearchTabs,
              assetStatus: KandoLoadStatus.content,
            );
          }
        } else {
          if (ref.mounted && generation == _loadGeneration) {
            state = state.copyWith(assetStatus: KandoLoadStatus.failure);
          }
        }
      }
      if (pendingSetsLoad != null) await pendingSetsLoad;
    } catch (_) {
      if (ref.mounted && generation == _loadGeneration) {
        state = const SearchState.unavailable();
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  void selectTab(SearchTab tab) {
    if (state.isUnavailable) {
      return;
    }

    if (state.isLoading) {
      state = state.copyWith(selectedTab: tab);
      return;
    }

    state = state.copyWith(selectedTab: tab);
    if (tab == SearchTab.sets && state.isLoadingSets) return;
    final needsCurrentGame = _loadedGameByTab[tab] != state.selectedGame.id;
    if (needsCurrentGame) {
      _scheduleSearch(tab: tab, query: state.searchText, allowEmpty: true);
    }
  }

  void updateSearch(String value) {
    _updateSearch(value, debounce: true);
  }

  void submitSearch(String value) {
    _updateSearch(value, debounce: false);
  }

  void _updateSearch(String value, {required bool debounce}) {
    if (state.isUnavailable) {
      return;
    }

    final tab = state.selectedTab;
    state = state.copyWith(searchByTab: {...state.searchByTab, tab: value});
    if (state.isLoading) return;
    _scheduleSearch(
      tab: tab,
      query: value,
      allowEmpty: true,
      debounce: debounce,
    );
  }

  void clearSearch() {
    if (state.isUnavailable) {
      return;
    }

    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: ''},
    );
    if (state.isLoading) return;
    _scheduleSearch(tab: state.selectedTab, query: '', allowEmpty: true);
  }

  void selectGame(String gameId) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    final exists = state.catalog.games.any((game) => game.id == gameId);
    if (!exists) {
      return;
    }

    state = state.copyWith(
      selectedGameId: gameId,
      searchByTab: {...state.searchByTab, state.selectedTab: ''},
    );
    _scheduleSearch(tab: state.selectedTab, query: '', allowEmpty: true);
  }

  void retrySearch() {
    if (state.isUnavailable || state.isLoading) return;
    _scheduleSearch(
      tab: state.selectedTab,
      query: state.searchText,
      allowEmpty: true,
    );
  }

  Future<void> loadNextCardPage() async {
    if (state.isUnavailable ||
        state.isLoading ||
        state.selectedTab != SearchTab.cards ||
        state.isCurrentSearchUnavailable ||
        state.isSearching ||
        state.isLoadingMoreCards ||
        state.hasCardPageFailure ||
        !state.hasMoreCards) {
      return;
    }
    final repository = ref.read(searchRepositoryProvider);
    if (repository is! PaginatedSearchRepository) return;
    final paginatedRepository = repository as PaginatedSearchRepository;

    final generation = ++_loadGeneration;
    final requestedPage = state.cardPage + 1;
    state = state.copyWith(
      isLoadingMoreCards: true,
      hasCardPageFailure: false,
      isLoadingSets: false,
    );
    try {
      final items = await paginatedRepository.searchCardPage(
        state.searchText.trim(),
        game: state.selectedGame.label,
        page: requestedPage,
      );
      if (!ref.mounted || generation != _loadGeneration) return;
      final cardsById = {
        for (final card in state.catalog.cards) card.id: card,
        for (final card in items) card.id: card,
      };
      var catalog = _catalogWithCards(state.catalog, cardsById.values.toList());
      final assetResult = await _withAssets(
        repository,
        catalog,
        _assetSession,
        cardRefs: items.map((item) => item.id),
      );
      if (!ref.mounted || generation != _loadGeneration) return;
      if (!assetResult.assetsReady) {
        state = state.copyWith(
          isLoadingMoreCards: false,
          hasCardPageFailure: true,
        );
        return;
      }
      state = _stateForCatalog(
        assetResult.catalog,
        preserveState: state,
        failedSearchTabs: state.failedSearchTabs,
        cardPage: requestedPage,
        hasMoreCards: items.length == kandoPageSize,
      );
    } catch (_) {
      if (ref.mounted && generation == _loadGeneration) {
        state = state.copyWith(
          isLoadingMoreCards: false,
          hasCardPageFailure: true,
        );
      }
    }
  }

  Future<void> retryNextCardPage() {
    if (!state.hasCardPageFailure || state.selectedTab != SearchTab.cards) {
      return Future<void>.value();
    }
    state = state.copyWith(hasCardPageFailure: false);
    return loadNextCardPage();
  }

  Future<void> loadNextSetPage() async {
    if (state.isUnavailable ||
        state.isLoading ||
        state.selectedTab != SearchTab.sets ||
        state.isCurrentSearchUnavailable ||
        state.isSearching ||
        state.isLoadingSets ||
        state.isLoadingMoreSets ||
        state.hasSetPageFailure ||
        !state.hasMoreSets) {
      return;
    }
    final repository = ref.read(searchRepositoryProvider);
    if (repository is! PaginatedSetSearchRepository) return;
    final paginatedRepository = repository as PaginatedSetSearchRepository;
    final generation = ++_loadGeneration;
    final requestedPage = state.setPage + 1;
    state = state.copyWith(isLoadingMoreSets: true, hasSetPageFailure: false);
    try {
      final items = await paginatedRepository.searchSetPage(
        state.searchText.trim(),
        game: state.selectedGame.label,
        page: requestedPage,
      );
      if (!ref.mounted || generation != _loadGeneration) return;
      final setsById = {
        for (final set in state.catalog.sets) set.id: set,
        for (final set in items) set.id: set,
      };
      state = _stateForCatalog(
        _catalogWithSets(state.catalog, setsById.values.toList()),
        preserveState: state,
        failedSearchTabs: state.failedSearchTabs,
        cardPage: state.cardPage,
        hasMoreCards: state.hasMoreCards,
        hasCardPageFailure: state.hasCardPageFailure,
        setPage: requestedPage,
        hasMoreSets: items.length == kandoPageSize,
      );
    } catch (_) {
      if (ref.mounted && generation == _loadGeneration) {
        state = state.copyWith(
          isLoadingMoreSets: false,
          hasSetPageFailure: true,
        );
      }
    }
  }

  Future<void> retryNextSetPage() {
    if (!state.hasSetPageFailure || state.selectedTab != SearchTab.sets) {
      return Future<void>.value();
    }
    state = state.copyWith(hasSetPageFailure: false);
    return loadNextSetPage();
  }

  Future<SearchCollectAction> toggleCollect(String cardId) async {
    if (state.isUnavailable || state.isLoading) {
      return SearchCollectAction.ignored;
    }
    return toggleCollectCard(state.cardById(cardId));
  }

  Future<SearchCollectAction> toggleCollectCard(
    SearchCard card, {
    String? game,
  }) async {
    if (state.isUnavailable ||
        state.isLoading ||
        !state.isAssetReady(card.id) ||
        !_pendingCardMutations.add(card.id)) {
      return SearchCollectAction.ignored;
    }
    try {
      return await _toggleCollect(resolveCard(card), game: game);
    } finally {
      _pendingCardMutations.remove(card.id);
    }
  }

  Future<SearchCollectAction> _toggleCollect(
    SearchCard card, {
    String? game,
  }) async {
    final requestedGame = game?.trim();
    final added = ref
        .read(pendingCollectionProvider.notifier)
        .add(
          PendingCollectionCard(
            id: card.id,
            name: card.name,
            game: requestedGame == null || requestedGame.isEmpty
                ? state.selectedGame.label
                : requestedGame,
            setName: card.setName,
            metadataLine: card.metadataLine,
            variantLine: card.variantLine,
            imageUrl: card.imageUrl,
          ),
        );
    return added
        ? SearchCollectAction.updated
        : SearchCollectAction.limitReached;
  }

  Future<bool> toggleWishlist(String cardId) async {
    if (state.isUnavailable || state.isLoading) return false;
    return toggleWishlistCard(state.cardById(cardId));
  }

  Future<bool> toggleWishlistCard(SearchCard card) async {
    if (state.isUnavailable ||
        state.isLoading ||
        !state.isAssetReady(card.id) ||
        !_pendingCardMutations.add(card.id)) {
      return false;
    }
    try {
      return await _toggleWishlist(resolveCard(card));
    } finally {
      _pendingCardMutations.remove(card.id);
    }
  }

  Future<bool> _toggleWishlist(SearchCard card) async {
    final repository = ref.read(searchRepositoryProvider);
    if (repository is SearchAssetRepository) {
      if (card.isCollected) return true;
      final session = ref.read(searchSessionProvider);
      if (session == null) return false;
      final ownerKey = _searchOwnerKey(session);
      try {
        if (card.wishlistItemId == null) {
          _replaceCard(
            card.copyWith(
              isWishlisted: true,
              wishlistItemId: 'pending:${card.id}',
            ),
          );
          final item = await repository.addWishlist(session, card.id);
          if (!ref.mounted ||
              _assetOwnerKey != ownerKey ||
              _searchOwnerKey(ref.read(searchSessionProvider)) != ownerKey) {
            return false;
          }
          _replaceCard(
            card.copyWith(isWishlisted: true, wishlistItemId: item.id),
          );
        } else {
          _replaceCard(
            card.copyWith(isWishlisted: false, wishlistItemId: null),
          );
          await repository.deleteWishlist(session, card.wishlistItemId!);
          if (!ref.mounted ||
              _assetOwnerKey != ownerKey ||
              _searchOwnerKey(ref.read(searchSessionProvider)) != ownerKey) {
            return false;
          }
        }
        _invalidateAssetCard(card.id);
        _invalidateAssetConsumers(card.id);
        return true;
      } catch (_) {
        if (!ref.mounted ||
            _assetOwnerKey != ownerKey ||
            _searchOwnerKey(ref.read(searchSessionProvider)) != ownerKey) {
          return false;
        }
        _invalidateAssetCard(card.id);
        final desiredWishlisted = card.wishlistItemId == null;
        final synced = await _reloadAssetsAfterMutation(
          card.id,
          fallback: card,
        );
        if (synced?.isWishlisted == desiredWishlisted) {
          _invalidateAssetConsumers(card.id);
          return true;
        }
        _replaceCard(card);
        return false;
      }
    }

    final next = card.isCollected
        ? card.copyWith(isWishlisted: false)
        : card.copyWith(isWishlisted: !card.isWishlisted);
    _replaceCard(next);
    return true;
  }

  void _replaceCard(SearchCard card) {
    state = state.copyWith(
      cardOverrides: {...state.cardOverrides, card.id: card},
    );
  }

  SearchCard resolveCard(SearchCard card) {
    final override = state.cardOverrides[card.id];
    if (override != null) return override;

    final assets = _assetSnapshot?.statesByCardRef[card.id];
    return assets == null ? card : _cardWithAssets(card, assets);
  }

  Future<void> ensureCardAssets(Iterable<String> cardRefs) async {
    final repository = ref.read(searchRepositoryProvider);
    final session = _assetSession;
    if (repository is! SearchVisibleAssetRepository || session == null) return;
    try {
      await _loadAssetSnapshot(repository, session, cardRefs: cardRefs);
      if (!ref.mounted ||
          _assetOwnerKey != _searchOwnerKey(ref.read(searchSessionProvider))) {
        return;
      }
      state = state.copyWith(readyAssetCardRefs: {..._loadedAssetCardRefs});
    } catch (_) {
      // The current page remains visible; its actions stay disabled.
    }
  }

  void applySavedCollectionItems(Iterable<CardCollectionItem> savedItems) {
    final itemsByCardRef = <String, List<CardCollectionItem>>{};
    for (final item in savedItems) {
      (itemsByCardRef[item.cardRef] ??= []).add(item);
    }
    if (itemsByCardRef.isEmpty) return;

    _loadGeneration += 1;
    _assetGeneration += 1;
    _assetLoad = null;
    final snapshot = _assetSnapshot;
    final assetStates = snapshot == null ? null : {...snapshot.statesByCardRef};
    final overrides = {...state.cardOverrides};

    for (final entry in itemsByCardRef.entries) {
      final catalogCard = state.catalog.cards
          .where((card) => card.id == entry.key)
          .firstOrNull;
      if (catalogCard == null) continue;

      final current = resolveCard(catalogCard);
      final currentAssets = assetStates?[entry.key];
      final itemIds = [
        ...?currentAssets?.collectionItemIds,
        if (currentAssets == null && current.collectionItemId != null)
          current.collectionItemId!,
      ];
      final additions = [
        for (final item in entry.value)
          if (item.id.isEmpty || !itemIds.contains(item.id)) item,
      ];
      if (additions.isEmpty) continue;
      for (final item in additions) {
        if (item.id.isNotEmpty) itemIds.add(item.id);
      }

      final quantity =
          current.quantity +
          additions.fold<int>(0, (sum, item) => sum + item.quantity);
      final itemCount = current.collectionItemCount + additions.length;
      final collectionInfo = _collectionInfoWithSavedItems(
        current.collectionInfo,
        additions,
      );
      final updated = current.copyWith(
        quantity: quantity,
        collectionItemCount: itemCount,
        collectionItemId: itemCount == 1 && itemIds.length == 1
            ? itemIds.single
            : null,
        collectionInfo: collectionInfo,
        isWishlisted: false,
        wishlistItemId: null,
      );
      overrides[entry.key] = updated;
      if (assetStates != null) {
        assetStates[entry.key] = SearchCardAssetState(
          quantity: quantity,
          collectionItemIds: itemIds,
          wishlistItemId: null,
          collectionInfo: collectionInfo,
        );
      }
    }

    if (snapshot != null && assetStates != null) {
      _assetSnapshot = SearchAssetSnapshot(
        folderId: snapshot.folderId,
        statesByCardRef: assetStates,
      );
    }
    state = state.copyWith(cardOverrides: overrides);
  }

  void _scheduleSearch({
    required SearchTab tab,
    required String query,
    bool allowEmpty = false,
    bool debounce = true,
  }) {
    _searchDebounce?.cancel();
    if (state.failedSearchTabs.contains(tab)) {
      state = state.copyWith(
        failedSearchTabs: {...state.failedSearchTabs}..remove(tab),
      );
    }
    state = state.copyWith(isSearching: true, isLoadingSets: false);
    final trimmed = query.trim();
    if (trimmed.isEmpty && !allowEmpty) {
      _startLoad(preserveState: state, session: _assetSession);
      return;
    }

    final completer = Completer<void>();
    final generation = ++_loadGeneration;
    _loadCompleter = completer;
    if (!debounce) {
      unawaited(_loadSearch(tab, trimmed, generation, completer));
      return;
    }

    _searchDebounce = Timer(searchDebounceDuration, () {
      unawaited(_loadSearch(tab, trimmed, generation, completer));
    });
  }

  Future<void> _loadSearch(
    SearchTab tab,
    String query,
    int generation,
    Completer<void> completer,
  ) async {
    try {
      final repository = ref.read(searchRepositoryProvider);
      final currentCatalog = state.catalog;
      final game = state.selectedGame.label;
      var catalog = switch (tab) {
        SearchTab.cards => _catalogWithCards(
          currentCatalog,
          await repository.searchCards(query, game: game),
        ),
        SearchTab.sets => _catalogWithSets(
          currentCatalog,
          repository is PaginatedSetSearchRepository
              ? await (repository as PaginatedSetSearchRepository)
                    .searchSetPage(query, game: game, page: 1)
              : await repository.searchSets(query, game: game),
        ),
      };
      final assetResult = await _withAssets(repository, catalog, _assetSession);
      catalog = assetResult.catalog;
      if (!ref.mounted) return;
      if (generation == _loadGeneration) {
        _loadedGameByTab[tab] = state.selectedGame.id;
        final failedSearchTabs = {...state.failedSearchTabs}..remove(tab);
        state = _stateForCatalog(
          catalog,
          preserveState: state,
          clearOverrides: repository is SearchAssetRepository,
          assetStatus: assetResult.assetsReady
              ? KandoLoadStatus.content
              : KandoLoadStatus.failure,
          failedSearchTabs: failedSearchTabs,
          cardPage: tab == SearchTab.cards ? 1 : state.cardPage,
          hasMoreCards: tab == SearchTab.cards
              ? catalog.cards.length == kandoPageSize
              : state.hasMoreCards,
          hasCardPageFailure: tab == SearchTab.cards
              ? false
              : state.hasCardPageFailure,
          setPage: tab == SearchTab.sets ? 1 : state.setPage,
          hasMoreSets: tab == SearchTab.sets
              ? repository is PaginatedSetSearchRepository &&
                    catalog.sets.length == kandoPageSize
              : state.hasMoreSets,
          isLoadingMoreSets: false,
          hasSetPageFailure: false,
        );
      }
    } catch (_) {
      if (ref.mounted && generation == _loadGeneration) {
        state = state.copyWith(
          failedSearchTabs: {...state.failedSearchTabs, tab},
          isSearching: false,
        );
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  SearchState _stateForCatalog(
    SearchCatalog catalog, {
    SearchState? preserveState,
    bool clearOverrides = false,
    Set<SearchTab> failedSearchTabs = const {},
    int cardPage = 1,
    bool? hasMoreCards,
    bool hasCardPageFailure = false,
    int? setPage,
    bool? hasMoreSets,
    bool? isLoadingSets,
    bool isLoadingMoreSets = false,
    bool hasSetPageFailure = false,
    KandoLoadStatus? assetStatus,
  }) {
    final selectedTab = preserveState?.selectedTab ?? SearchTab.cards;
    final selectedGameId = _selectedGameIdFor(catalog, preserveState);
    return SearchState(
      catalog: catalog,
      selectedTab: selectedTab,
      selectedGameId: selectedGameId,
      searchByTab:
          preserveState?.searchByTab ??
          const {SearchTab.cards: '', SearchTab.sets: ''},
      cardOverrides: clearOverrides
          ? const {}
          : preserveState?.cardOverrides ?? const {},
      failedSearchTabs: failedSearchTabs,
      cardPage: cardPage,
      hasMoreCards: hasMoreCards ?? catalog.cards.length == kandoPageSize,
      isLoadingMoreCards: false,
      hasCardPageFailure: hasCardPageFailure,
      setPage: setPage ?? preserveState?.setPage ?? 1,
      hasMoreSets: hasMoreSets ?? preserveState?.hasMoreSets ?? false,
      isLoadingSets: isLoadingSets ?? preserveState?.isLoadingSets ?? false,
      isLoadingMoreSets: isLoadingMoreSets,
      hasSetPageFailure: hasSetPageFailure,
      assetStatus:
          assetStatus ?? preserveState?.assetStatus ?? KandoLoadStatus.content,
      readyAssetCardRefs:
          ref.read(searchRepositoryProvider) is SearchVisibleAssetRepository
          ? {..._loadedAssetCardRefs}
          : null,
    );
  }

  String _selectedGameIdFor(SearchCatalog catalog, SearchState? preserveState) {
    final previousGameId = preserveState?.selectedGameId;
    if (previousGameId != null &&
        catalog.games.any((game) => game.id == previousGameId)) {
      return previousGameId;
    }
    return catalog.defaultGame.id;
  }

  SearchCatalog _catalogWithCards(
    SearchCatalog currentCatalog,
    List<SearchCard> cards,
  ) {
    return SearchCatalog(
      games: currentCatalog.games,
      cards: cards,
      sets: currentCatalog.sets,
    );
  }

  SearchCatalog _catalogWithSets(
    SearchCatalog currentCatalog,
    List<SearchSet> sets,
  ) {
    return SearchCatalog(
      games: currentCatalog.games,
      cards: currentCatalog.cards,
      sets: sets,
    );
  }

  Future<({SearchCatalog catalog, bool assetsReady})> _withAssets(
    SearchRepository repository,
    SearchCatalog catalog,
    AuthSession? session, {
    Iterable<String>? cardRefs,
  }) async {
    if (repository is! SearchAssetRepository || session == null) {
      return (catalog: catalog, assetsReady: true);
    }
    try {
      final snapshot = await _loadAssetSnapshot(
        repository,
        session,
        cardRefs: cardRefs ?? catalog.cards.map((card) => card.id),
      );
      return (
        catalog: _catalogWithAssets(catalog, snapshot),
        assetsReady: true,
      );
    } catch (_) {
      return (
        catalog: SearchCatalog(
          games: catalog.games,
          cards: [
            for (final card in catalog.cards) _cardWithRetainedAssets(card),
          ],
          sets: catalog.sets,
        ),
        assetsReady: false,
      );
    }
  }

  SearchCard _cardWithRetainedAssets(SearchCard card) {
    final existing = state.catalog.cards
        .where((item) => item.id == card.id)
        .firstOrNull;
    if (existing == null) return resolveCard(card);
    final current = resolveCard(existing);
    return card.copyWith(
      quantity: current.quantity,
      collectionItemCount: current.collectionItemCount,
      collectionItemId: current.collectionItemId,
      collectionInfo: current.collectionInfo,
      isWishlisted: current.isWishlisted,
      wishlistItemId: current.wishlistItemId,
    );
  }

  Future<SearchAssetSnapshot> _loadAssetSnapshot(
    SearchAssetRepository repository,
    AuthSession session, {
    Iterable<String> cardRefs = const [],
  }) async {
    final ownerKey = _searchOwnerKey(session);
    if (_assetOwnerKey != ownerKey) {
      throw StateError('Search asset owner changed.');
    }
    final requested = cardRefs.toSet();
    while (true) {
      if (!ref.mounted ||
          _assetOwnerKey != ownerKey ||
          _searchOwnerKey(ref.read(searchSessionProvider)) != ownerKey) {
        throw StateError('Search asset owner changed.');
      }
      final cached = _assetSnapshot;
      if (repository is SearchVisibleAssetRepository) {
        if (requested.isEmpty) {
          return cached ??
              SearchAssetSnapshot(
                folderId: ref.read(selectedPortfolioFolderProvider) ?? '',
                statesByCardRef: const {},
              );
        }
        if (cached != null && _loadedAssetCardRefs.containsAll(requested)) {
          return cached;
        }
      } else if (cached != null) {
        return cached;
      }
      final loading = _assetLoad;
      if (loading != null) {
        await loading;
        continue;
      }
      final missing = requested
          .difference(_loadedAssetCardRefs)
          .take(100)
          .toSet();
      final generation = _assetGeneration;
      final future = repository is SearchVisibleAssetRepository
          ? repository.loadVisibleAssets(
              session,
              missing,
              selectedFolderId: ref.read(selectedPortfolioFolderProvider),
            )
          : repository.loadAssets(
              session,
              selectedFolderId: ref.read(selectedPortfolioFolderProvider),
            );
      _assetLoad = () async {
        try {
          final next = await future;
          if (!ref.mounted ||
              generation != _assetGeneration ||
              _assetOwnerKey != ownerKey) {
            throw StateError('Search asset request is stale.');
          }
          final snapshot = repository is SearchVisibleAssetRepository
              ? SearchAssetSnapshot(
                  folderId: next.folderId,
                  statesByCardRef: {
                    ...?(_assetSnapshot?.statesByCardRef),
                    for (final entry in next.statesByCardRef.entries)
                      if (missing.contains(entry.key)) entry.key: entry.value,
                  },
                )
              : next;
          _assetSnapshot = snapshot;
          _loadedAssetCardRefs.addAll(missing);
          if (ref.read(selectedPortfolioFolderProvider) == null &&
              snapshot.folderId.isNotEmpty) {
            ref
                .read(selectedPortfolioFolderProvider.notifier)
                .select(snapshot.folderId);
          }
          return snapshot;
        } finally {
          if (generation == _assetGeneration) _assetLoad = null;
        }
      }();
      await _assetLoad!;
    }
  }

  void _resetAssets() {
    _assetGeneration += 1;
    _assetSnapshot = null;
    _assetLoad = null;
    _loadedAssetCardRefs.clear();
  }

  void _invalidateAssetCard(String cardRef) {
    if (ref.read(searchRepositoryProvider) is! SearchVisibleAssetRepository) {
      _resetAssets();
      return;
    }
    _assetGeneration += 1;
    _assetLoad = null;
    _loadedAssetCardRefs.remove(cardRef);
    final snapshot = _assetSnapshot;
    if (snapshot == null) return;
    _assetSnapshot = SearchAssetSnapshot(
      folderId: snapshot.folderId,
      statesByCardRef: {...snapshot.statesByCardRef}..remove(cardRef),
    );
  }

  SearchCatalog _catalogWithAssets(
    SearchCatalog catalog,
    SearchAssetSnapshot snapshot,
  ) {
    return SearchCatalog(
      games: catalog.games,
      cards: [
        for (final card in catalog.cards)
          _cardWithAssets(card, snapshot.statesByCardRef[card.id]),
      ],
      sets: catalog.sets,
    );
  }

  SearchCard _cardWithAssets(SearchCard card, SearchCardAssetState? assets) {
    final itemIds = assets?.collectionItemIds ?? const [];
    final quantity = assets?.quantity ?? 0;
    return card.copyWith(
      quantity: quantity,
      collectionItemCount: itemIds.length,
      collectionItemId: itemIds.length == 1 ? itemIds.single : null,
      collectionInfo: assets?.collectionInfo,
      isWishlisted: quantity == 0 && assets?.wishlistItemId != null,
      wishlistItemId: quantity == 0 ? assets?.wishlistItemId : null,
    );
  }

  Future<SearchCard?> _reloadAssetsAfterMutation(
    String cardId, {
    SearchCard? fallback,
  }) async {
    final repository = ref.read(searchRepositoryProvider);
    final session = _assetSession;
    if (repository is! SearchAssetRepository || session == null) return null;
    final ownerKey = _searchOwnerKey(session);
    try {
      final result = await _withAssets(
        repository,
        state.catalog,
        session,
        cardRefs: [cardId],
      );
      if (!ref.mounted ||
          _assetOwnerKey != ownerKey ||
          _searchOwnerKey(ref.read(searchSessionProvider)) != ownerKey) {
        return null;
      }
      state = _stateForCatalog(
        result.catalog,
        preserveState: state,
        clearOverrides: true,
        assetStatus: result.assetsReady
            ? KandoLoadStatus.content
            : KandoLoadStatus.failure,
        failedSearchTabs: state.failedSearchTabs,
        cardPage: state.cardPage,
        hasMoreCards: state.hasMoreCards,
        hasCardPageFailure: state.hasCardPageFailure,
      );
      return fallback == null ? state.cardById(cardId) : resolveCard(fallback);
    } catch (_) {
      return null;
    }
  }

  void _invalidateAssetConsumers(String cardId) {
    unawaited(
      ref.read(homeControllerProvider.notifier).refreshPreservingContent(),
    );
    ref.invalidate(collectionControllerProvider);
    ref.invalidate(cardDetailControllerProvider(cardId));
  }

  AuthSession? get _assetSession {
    return ref.read(searchRepositoryProvider) is SearchAssetRepository
        ? ref.read(searchSessionProvider)
        : null;
  }
}

Object? _searchOwnerKey(AuthSession? session) => session == null
    ? null
    : (session.ownerType, session.userId, session.anonymousId);

String? _collectionInfoWithSavedItems(
  String? current,
  Iterable<CardCollectionItem> additions,
) {
  if (current == 'Mixed') return current;
  final values = <String>{
    if (current?.trim().isNotEmpty ?? false) current!.trim(),
    for (final item in additions)
      if (_collectionItemInfo(item) case final info?) info,
  };
  if (values.isEmpty) return null;
  return values.length == 1 ? values.single : 'Mixed';
}

String? _collectionItemInfo(CardCollectionItem item) {
  if (item.grader.trim().toLowerCase() == 'raw') {
    final condition = item.condition?.trim();
    return condition == null || condition.isEmpty ? null : condition;
  }
  final grader = item.grader.trim();
  if (grader.isEmpty) return null;
  final grade = item.grade?.trim();
  return grade == null || grade.isEmpty ? grader : '$grader $grade';
}
