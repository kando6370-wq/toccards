import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'search_models.dart';
import 'search_repository.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return const MockSearchRepository();
});

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

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
  @override
  SearchState build() {
    final repository = ref.watch(searchRepositoryProvider);
    return _loadCatalog(repository: repository);
  }

  void refresh() {
    state = _loadCatalog();
  }

  SearchState _loadCatalog({SearchRepository? repository}) {
    try {
      final SearchRepository source =
          repository ?? ref.read(searchRepositoryProvider);
      final catalog = source.loadCatalog();
      return SearchState(
        catalog: catalog,
        selectedTab: SearchTab.cards,
        selectedGameId: catalog.defaultGame.id,
        searchByTab: const {SearchTab.cards: '', SearchTab.sets: ''},
        cardOverrides: const {},
      );
    } catch (_) {
      return const SearchState.unavailable();
    }
  }

  void selectTab(SearchTab tab) {
    if (state.isUnavailable) {
      return;
    }

    state = state.copyWith(selectedTab: tab);
  }

  void updateSearch(String value) {
    if (state.isUnavailable) {
      return;
    }

    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: value},
    );
  }

  void clearSearch() {
    if (state.isUnavailable) {
      return;
    }

    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: ''},
    );
  }

  void selectGame(String gameId) {
    if (state.isUnavailable) {
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

  void toggleCollect(String cardId) {
    if (state.isUnavailable) {
      return;
    }

    final card = state.cardById(cardId);
    final next = card.isCollected
        ? card.copyWith(quantity: 0)
        : card.copyWith(quantity: 1, isWishlisted: false);
    _replaceCard(next);
  }

  void toggleWishlist(String cardId) {
    if (state.isUnavailable) {
      return;
    }

    final card = state.cardById(cardId);
    final next = card.isCollected
        ? card.copyWith(isWishlisted: false)
        : card.copyWith(isWishlisted: !card.isWishlisted);
    _replaceCard(next);
  }

  void _replaceCard(SearchCard card) {
    state = state.copyWith(
      cardOverrides: {...state.cardOverrides, card.id: card},
    );
  }
}
