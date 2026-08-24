import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
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
    this.isSearching = false,
    this.isLoadingMoreCards = false,
    this.hasCardPageFailure = false,
    this.assetStatus = KandoLoadStatus.content,
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
      isSearching = false,
      isLoadingMoreCards = false,
      hasCardPageFailure = false,
      assetStatus = KandoLoadStatus.failure,
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
      isSearching = false,
      isLoadingMoreCards = false,
      hasCardPageFailure = false,
      assetStatus = KandoLoadStatus.loading,
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
    required this.isSearching,
    required this.isLoadingMoreCards,
    required this.hasCardPageFailure,
    required this.assetStatus,
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
  final bool isSearching;
  final bool isLoadingMoreCards;
  final bool hasCardPageFailure;
  final KandoLoadStatus assetStatus;
  final KandoLoadStatus loadStatus;

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
        .map((card) => cardById(card.id))
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
    bool? isSearching,
    bool? isLoadingMoreCards,
    bool? hasCardPageFailure,
    KandoLoadStatus? assetStatus,
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
      isSearching: isSearching ?? this.isSearching,
      isLoadingMoreCards: isLoadingMoreCards ?? this.isLoadingMoreCards,
      hasCardPageFailure: hasCardPageFailure ?? this.hasCardPageFailure,
      assetStatus: assetStatus ?? this.assetStatus,
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
  var _hasCompleteSets = true;
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
    _hasCompleteSets =
        ref.read(searchRepositoryProvider) is! HttpSearchRepository;
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
      final Future<SearchAssetSnapshot?>? assetsFuture = loadsAssets
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
      if (catalog.games.isEmpty) {
        throw StateError('Search catalog needs at least one game.');
      }
      if (generation == _loadGeneration) {
        state = _stateForCatalog(
          catalog,
          preserveState: preserveState,
          clearOverrides: repository is SearchAssetRepository,
          failedSearchTabs: catalogLoad.failedSearchTabs,
          assetStatus: loadsAssets
              ? KandoLoadStatus.loading
              : KandoLoadStatus.content,
        );
        for (final tab in SearchTab.values) {
          if (!catalogLoad.failedSearchTabs.contains(tab)) {
            _loadedGameByTab[tab] = state.selectedGame.id;
          }
        }
      }
      if (assetsFuture != null) {
        final snapshot = await assetsFuture;
        if (snapshot != null) {
          catalog = _catalogWithAssets(catalog, snapshot);
          if (ref.mounted && generation == _loadGeneration) {
            state = _stateForCatalog(
              catalog,
              preserveState: state,
              clearOverrides: true,
              failedSearchTabs: catalogLoad.failedSearchTabs,
              assetStatus: KandoLoadStatus.content,
            );
          }
        } else {
          if (ref.mounted && generation == _loadGeneration) {
            state = state.copyWith(assetStatus: KandoLoadStatus.failure);
          }
        }
      }
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
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(selectedTab: tab);
    final needsCurrentGame = _loadedGameByTab[tab] != state.selectedGame.id;
    if (needsCurrentGame || (tab == SearchTab.sets && !_hasCompleteSets)) {
      _hasCompleteSets = true;
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
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    final tab = state.selectedTab;
    state = state.copyWith(searchByTab: {...state.searchByTab, tab: value});
    _scheduleSearch(
      tab: tab,
      query: value,
      allowEmpty: true,
      debounce: debounce,
    );
  }

  void clearSearch() {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: ''},
    );
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

    _hasCompleteSets =
        ref.read(searchRepositoryProvider) is! HttpSearchRepository;
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
    state = state.copyWith(isLoadingMoreCards: true, hasCardPageFailure: false);
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
      catalog = await _withAssets(repository, catalog, _assetSession);
      if (!ref.mounted || generation != _loadGeneration) return;
      state = _stateForCatalog(
        catalog,
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
        state.assetStatus != KandoLoadStatus.content ||
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
        state.assetStatus != KandoLoadStatus.content ||
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
      try {
        if (card.wishlistItemId == null) {
          _replaceCard(
            card.copyWith(
              isWishlisted: true,
              wishlistItemId: 'pending:${card.id}',
            ),
          );
          final item = await repository.addWishlist(session, card.id);
          _replaceCard(
            card.copyWith(isWishlisted: true, wishlistItemId: item.id),
          );
        } else {
          _replaceCard(
            card.copyWith(isWishlisted: false, wishlistItemId: null),
          );
          await repository.deleteWishlist(session, card.wishlistItemId!);
        }
        _resetAssets();
        _invalidateAssetConsumers(card.id);
        return true;
      } catch (_) {
        _resetAssets();
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
    state = state.copyWith(isSearching: true);
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
          await repository.searchSets(query, game: game),
        ),
      };
      catalog = await _withAssets(repository, catalog, _assetSession);
      if (!ref.mounted) return;
      if (generation == _loadGeneration) {
        _loadedGameByTab[tab] = state.selectedGame.id;
        final failedSearchTabs = {...state.failedSearchTabs}..remove(tab);
        if (tab == SearchTab.sets) {
          _hasCompleteSets = true;
        }
        state = _stateForCatalog(
          catalog,
          preserveState: state,
          clearOverrides: repository is SearchAssetRepository,
          failedSearchTabs: failedSearchTabs,
        );
      }
    } catch (_) {
      if (ref.mounted && generation == _loadGeneration) {
        if (tab == SearchTab.sets) {
          _hasCompleteSets = false;
        }
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
      assetStatus:
          assetStatus ?? preserveState?.assetStatus ?? KandoLoadStatus.content,
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

  Future<SearchCatalog> _withAssets(
    SearchRepository repository,
    SearchCatalog catalog,
    AuthSession? session,
  ) async {
    if (repository is! SearchAssetRepository || session == null) {
      return catalog;
    }
    try {
      final snapshot = await _loadAssetSnapshot(repository, session);
      return _catalogWithAssets(catalog, snapshot);
    } catch (_) {
      return catalog;
    }
  }

  Future<SearchAssetSnapshot> _loadAssetSnapshot(
    SearchAssetRepository repository,
    AuthSession session,
  ) {
    final cached = _assetSnapshot;
    if (cached != null) return Future.value(cached);
    final loading = _assetLoad;
    if (loading != null) return loading;
    final future = repository.loadAssets(
      session,
      selectedFolderId: ref.read(selectedPortfolioFolderProvider),
    );
    final generation = _assetGeneration;
    _assetLoad = future.then((snapshot) {
      if (generation == _assetGeneration) {
        _assetSnapshot = snapshot;
      }
      if (ref.mounted && ref.read(selectedPortfolioFolderProvider) == null) {
        ref
            .read(selectedPortfolioFolderProvider.notifier)
            .select(snapshot.folderId);
      }
      return snapshot;
    });
    return _assetLoad!;
  }

  void _resetAssets() {
    _assetGeneration += 1;
    _assetSnapshot = null;
    _assetLoad = null;
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
    try {
      final catalog = await _withAssets(repository, state.catalog, session);
      if (!ref.mounted) return null;
      state = _stateForCatalog(
        catalog,
        preserveState: state,
        clearOverrides: true,
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
    ref.invalidate(homeControllerProvider);
    ref.invalidate(collectionControllerProvider);
    ref.invalidate(cardDetailControllerProvider(cardId));
  }

  AuthSession? get _assetSession {
    return ref.read(searchRepositoryProvider) is SearchAssetRepository
        ? ref.read(searchSessionProvider)
        : null;
  }
}
