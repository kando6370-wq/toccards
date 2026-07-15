import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'search_models.dart';
import 'search_repository.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return HttpSearchRepository(
    ref.watch(cardDataApiClientProvider),
    portfolioApi: ref.watch(portfolioApiClientProvider),
  );
});

final searchSessionProvider = Provider<AuthSession?>((ref) {
  return ref.watch(authControllerProvider).session;
});

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

const searchDebounceDuration = Duration(milliseconds: 300);

enum SearchCollectAction { updated, openDetail, ignored }

class SearchState {
  const SearchState({
    required SearchCatalog catalog,
    required this.selectedTab,
    required this.selectedGameId,
    required this.searchByTab,
    required this.cardOverrides,
  }) : _catalog = catalog,
       loadStatus = KandoLoadStatus.content;

  const SearchState.unavailable()
    : _catalog = null,
      selectedTab = SearchTab.cards,
      selectedGameId = '',
      searchByTab = const {SearchTab.cards: '', SearchTab.sets: ''},
      cardOverrides = const {},
      loadStatus = KandoLoadStatus.failure;

  const SearchState.loading()
    : _catalog = null,
      selectedTab = SearchTab.cards,
      selectedGameId = '',
      searchByTab = const {SearchTab.cards: '', SearchTab.sets: ''},
      cardOverrides = const {},
      loadStatus = KandoLoadStatus.loading;

  const SearchState._({
    required SearchCatalog? catalog,
    required this.selectedTab,
    required this.selectedGameId,
    required this.searchByTab,
    required this.cardOverrides,
    required this.loadStatus,
  }) : _catalog = catalog;

  final SearchCatalog? _catalog;
  final SearchTab selectedTab;
  final String selectedGameId;
  final Map<SearchTab, String> searchByTab;
  final Map<String, SearchCard> cardOverrides;
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
  }) {
    return SearchState._(
      catalog: _catalog,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedGameId: selectedGameId ?? this.selectedGameId,
      searchByTab: searchByTab ?? this.searchByTab,
      cardOverrides: cardOverrides ?? this.cardOverrides,
      loadStatus: loadStatus,
    );
  }

  bool _matchesCard(SearchCard card) {
    if (card.gameId != selectedGame.id) {
      return false;
    }

    final query = searchText.trim().toLowerCase();
    return query.isEmpty || card.searchableText.contains(query);
  }

  bool _matchesSet(SearchSet set) {
    if (set.gameId != selectedGame.id) {
      return false;
    }

    final query = searchText.trim().toLowerCase();
    return query.isEmpty || set.searchableText.contains(query);
  }
}

class SearchController extends Notifier<SearchState> {
  Completer<void>? _loadCompleter;
  Timer? _searchDebounce;
  var _loadGeneration = 0;
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
    _startLoad(session: _assetSession);
    return loadComplete;
  }

  void _startLoad({SearchState? preserveState, AuthSession? session}) {
    _searchDebounce?.cancel();
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
      var catalog = await repository.loadCatalog();
      catalog = await _withAssets(repository, catalog, session);
      if (!ref.mounted) return;
      if (catalog.games.isEmpty) {
        throw StateError('Search catalog needs at least one game.');
      }
      if (generation == _loadGeneration) {
        state = _stateForCatalog(
          catalog,
          preserveState: preserveState,
          clearOverrides: repository is SearchAssetRepository,
        );
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
  }

  void updateSearch(String value) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    final tab = state.selectedTab;
    state = state.copyWith(searchByTab: {...state.searchByTab, tab: value});
    _scheduleSearch(tab: tab, query: value);
  }

  void clearSearch() {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: ''},
    );
    _startLoad(preserveState: state, session: _assetSession);
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
  }

  Future<SearchCollectAction> toggleCollect(String cardId) async {
    if (state.isUnavailable ||
        state.isLoading ||
        !_pendingCardMutations.add(cardId)) {
      return SearchCollectAction.ignored;
    }
    try {
      return await _toggleCollect(cardId);
    } finally {
      _pendingCardMutations.remove(cardId);
    }
  }

  Future<SearchCollectAction> _toggleCollect(String cardId) async {
    final card = state.cardById(cardId);
    if (card.isCollected) {
      final collectionItemCount = card.collectionItemCount > 0
          ? card.collectionItemCount
          : 1;

      if (collectionItemCount > 1) {
        return SearchCollectAction.openDetail;
      }

      final repository = ref.read(searchRepositoryProvider);
      if (repository is SearchAssetRepository) {
        final session = ref.read(searchSessionProvider);
        final itemId = card.collectionItemId;
        if (session == null || itemId == null) {
          return SearchCollectAction.openDetail;
        }
        try {
          await repository.deleteCollectionItem(session, itemId);
        } catch (_) {
          return SearchCollectAction.ignored;
        }
      }
      _replaceCard(
        card.copyWith(
          quantity: 0,
          collectionItemCount: 0,
          collectionItemId: null,
        ),
      );
      _invalidateAssetConsumers(cardId);
      return SearchCollectAction.updated;
    }

    final repository = ref.read(searchRepositoryProvider);
    if (repository is SearchAssetRepository) {
      final session = ref.read(searchSessionProvider);
      final folderId = ref.read(selectedPortfolioFolderProvider);
      if (session == null || folderId == null) {
        return SearchCollectAction.ignored;
      }
      try {
        final item = await repository.collect(
          session,
          card: card,
          folderId: folderId,
        );
        final next = card.copyWith(
          quantity: item.quantity,
          collectionItemCount: 1,
          collectionItemId: item.id,
          isWishlisted: false,
          wishlistItemId: null,
        );
        _replaceCard(next);
        _invalidateAssetConsumers(cardId);
        return SearchCollectAction.updated;
      } catch (_) {
        return SearchCollectAction.ignored;
      }
    }

    final next = card.copyWith(
      quantity: 1,
      collectionItemCount: 1,
      isWishlisted: false,
    );
    _replaceCard(next);
    return SearchCollectAction.updated;
  }

  Future<bool> toggleWishlist(String cardId) async {
    if (state.isUnavailable ||
        state.isLoading ||
        !_pendingCardMutations.add(cardId)) {
      return false;
    }
    try {
      return await _toggleWishlist(cardId);
    } finally {
      _pendingCardMutations.remove(cardId);
    }
  }

  Future<bool> _toggleWishlist(String cardId) async {
    final card = state.cardById(cardId);
    final repository = ref.read(searchRepositoryProvider);
    if (repository is SearchAssetRepository) {
      if (card.isCollected) return true;
      final session = ref.read(searchSessionProvider);
      if (session == null) return false;
      try {
        if (card.wishlistItemId == null) {
          final item = await repository.addWishlist(session, card.id);
          _replaceCard(
            card.copyWith(isWishlisted: true, wishlistItemId: item.id),
          );
        } else {
          await repository.deleteWishlist(session, card.wishlistItemId!);
          _replaceCard(
            card.copyWith(isWishlisted: false, wishlistItemId: null),
          );
        }
        _invalidateAssetConsumers(cardId);
        return true;
      } catch (_) {
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

  void _scheduleSearch({required SearchTab tab, required String query}) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _startLoad(preserveState: state);
      return;
    }

    final completer = Completer<void>();
    final generation = ++_loadGeneration;
    _loadCompleter = completer;
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
      var catalog = switch (tab) {
        SearchTab.cards => _catalogWithCards(
          currentCatalog,
          await repository.searchCards(query),
        ),
        SearchTab.sets => _catalogWithSets(
          currentCatalog,
          await repository.searchSets(query),
        ),
      };
      catalog = await _withAssets(repository, catalog, _assetSession);
      if (!ref.mounted) return;
      if (generation == _loadGeneration) {
        state = _stateForCatalog(
          catalog,
          preserveState: state,
          clearOverrides: repository is SearchAssetRepository,
        );
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

  SearchState _stateForCatalog(
    SearchCatalog catalog, {
    SearchState? preserveState,
    bool clearOverrides = false,
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
    final games = _gamesFromCards(cards);
    return SearchCatalog(
      games: games.isEmpty ? currentCatalog.games : games,
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

  List<SearchGame> _gamesFromCards(List<SearchCard> cards) {
    final gamesById = <String, SearchGame>{};
    for (final card in cards) {
      final existing = state.catalog.games.where(
        (game) => game.id == card.gameId,
      );
      gamesById[card.gameId] = existing.isEmpty
          ? SearchGame(id: card.gameId, label: card.gameId)
          : existing.first;
    }
    return gamesById.values.toList();
  }

  Future<SearchCatalog> _withAssets(
    SearchRepository repository,
    SearchCatalog catalog,
    AuthSession? session,
  ) async {
    if (repository is! SearchAssetRepository || session == null) {
      return catalog;
    }
    final snapshot = await repository.loadAssets(
      session,
      selectedFolderId: ref.read(selectedPortfolioFolderProvider),
    );
    if (!ref.mounted) return catalog;
    if (ref.read(selectedPortfolioFolderProvider) == null) {
      ref
          .read(selectedPortfolioFolderProvider.notifier)
          .select(snapshot.folderId);
    }
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
      isWishlisted: quantity == 0 && assets?.wishlistItemId != null,
      wishlistItemId: quantity == 0 ? assets?.wishlistItemId : null,
    );
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
