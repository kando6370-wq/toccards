import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'search_repository.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return const MockSearchRepository();
});

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

class SearchState {
  const SearchState({
    required this.catalog,
    required this.selectedTab,
    required this.selectedGameId,
    required this.searchByTab,
    required this.cardOverrides,
  });

  final SearchCatalog catalog;
  final SearchTab selectedTab;
  final String selectedGameId;
  final Map<SearchTab, String> searchByTab;
  final Map<String, SearchCard> cardOverrides;

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
    return SearchState(
      catalog: catalog,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedGameId: selectedGameId ?? this.selectedGameId,
      searchByTab: searchByTab ?? this.searchByTab,
      cardOverrides: cardOverrides ?? this.cardOverrides,
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
    final catalog = ref.watch(searchRepositoryProvider).loadCatalog();
    return SearchState(
      catalog: catalog,
      selectedTab: SearchTab.cards,
      selectedGameId: catalog.defaultGame.id,
      searchByTab: const {SearchTab.cards: '', SearchTab.sets: ''},
      cardOverrides: const {},
    );
  }

  void selectTab(SearchTab tab) {
    state = state.copyWith(selectedTab: tab);
  }

  void updateSearch(String value) {
    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: value},
    );
  }

  void clearSearch() {
    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: ''},
    );
  }

  void selectGame(String gameId) {
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
    final card = state.cardById(cardId);
    final next = card.isCollected
        ? card.copyWith(quantity: 0)
        : card.copyWith(quantity: 1, isWishlisted: false);
    _replaceCard(next);
  }

  void toggleWishlist(String cardId) {
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
