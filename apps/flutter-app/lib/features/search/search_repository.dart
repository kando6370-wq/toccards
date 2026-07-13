import 'package:kando_app/shared/card_data/card_data_api_client.dart';

import 'search_models.dart';

abstract interface class SearchRepository {
  Future<SearchCatalog> loadCatalog();
  Future<List<SearchCard>> searchCards(String query);
  Future<List<SearchSet>> searchSets(String query);
}

class HttpSearchRepository implements SearchRepository {
  const HttpSearchRepository(this._api, {String defaultSetQuery = 'pokemon'})
    : _defaultSetQuery = defaultSetQuery;

  final CardDataApi _api;
  final String _defaultSetQuery;

  @override
  Future<SearchCatalog> loadCatalog() async {
    final cards = await _api.trendingCards();
    final sets = await _api.searchSets(_defaultSetQuery);

    return SearchCatalog(
      games: _gamesFromCards(cards),
      cards: cards.map(_cardFromDto).toList(),
      sets: sets.map(_setFromDto).toList(),
    );
  }

  @override
  Future<List<SearchCard>> searchCards(String query) async {
    final cards = await _api.searchCards(query);
    return cards.map(_cardFromDto).toList();
  }

  @override
  Future<List<SearchSet>> searchSets(String query) async {
    final sets = await _api.searchSets(query);
    return sets.map(_setFromDto).toList();
  }
}

class MockSearchRepository implements SearchRepository {
  const MockSearchRepository();

  @override
  Future<SearchCatalog> loadCatalog() async {
    return const SearchCatalog(
      games: [
        SearchGame(id: 'pokemon', label: 'Pokemon'),
        SearchGame(id: 'lorcana', label: 'Lorcana'),
        SearchGame(id: 'one-piece', label: 'One Piece'),
      ],
      cards: [
        SearchCard(
          id: 'squirtle',
          gameId: 'pokemon',
          type: SearchCardType.tcg,
          name: 'Squirtle',
          priceUsd: 32.13,
          previous30dPriceUsd: 30.67,
          setName: 'Mega Evolution Promos',
          metadataLine: 'Promo · 039',
          variantLine: 'Holofoil',
          quantity: 0,
          isWishlisted: false,
        ),
        SearchCard(
          id: 'charizard-ex',
          gameId: 'pokemon',
          type: SearchCardType.tcg,
          name: 'Charizard ex',
          priceUsd: 780,
          previous30dPriceUsd: 721.58,
          setName: 'Obsidian Flames',
          metadataLine: 'Special Illustration Rare · 223',
          variantLine: 'PSA 10',
          quantity: 1,
          collectionItemCount: 1,
          isWishlisted: false,
        ),
        SearchCard(
          id: 'mystery-promo',
          gameId: 'pokemon',
          type: SearchCardType.other,
          name: 'Mystery Promo',
          priceUsd: null,
          previous30dPriceUsd: null,
          setName: 'Promo Vault',
          metadataLine: 'Special Release',
          variantLine: 'Raw',
          quantity: 0,
          isWishlisted: false,
        ),
        SearchCard(
          id: 'lorcana-elsa',
          gameId: 'lorcana',
          type: SearchCardType.tcg,
          name: 'Lorcana Elsa',
          priceUsd: 480,
          previous30dPriceUsd: 449.86,
          setName: 'The First Chapter',
          metadataLine: 'Enchanted · 212',
          variantLine: 'Cold Foil',
          quantity: 0,
          isWishlisted: false,
        ),
        SearchCard(
          id: 'one-piece-luffy',
          gameId: 'one-piece',
          type: SearchCardType.tcg,
          name: 'One Piece Manga Luffy',
          priceUsd: 330,
          previous30dPriceUsd: 306.69,
          setName: 'Romance Dawn',
          metadataLine: 'Manga Rare · 001',
          variantLine: 'Japanese',
          quantity: 0,
          isWishlisted: true,
        ),
      ],
      sets: [
        SearchSet(
          id: 'mega-evolution-promos',
          gameId: 'pokemon',
          name: 'Mega Evolution Promos',
          subtitle: 'Pokemon promotional cards',
          releaseText: '2025',
          cardCountText: '124 cards',
        ),
        SearchSet(
          id: 'obsidian-flames',
          gameId: 'pokemon',
          name: 'Obsidian Flames',
          subtitle: 'Scarlet & Violet',
          releaseText: '2023',
          cardCountText: '230 cards',
        ),
        SearchSet(
          id: 'the-first-chapter',
          gameId: 'lorcana',
          name: 'The First Chapter',
          subtitle: 'Disney Lorcana',
          releaseText: '2023',
          cardCountText: '216 cards',
        ),
        SearchSet(
          id: 'romance-dawn',
          gameId: 'one-piece',
          name: 'Romance Dawn',
          subtitle: 'One Piece Card Game',
          releaseText: '2022',
          cardCountText: '121 cards',
        ),
      ],
    );
  }

  @override
  Future<List<SearchCard>> searchCards(String query) async {
    final catalog = await loadCatalog();
    final normalized = query.trim().toLowerCase();
    return catalog.cards
        .where((card) => card.searchableText.contains(normalized))
        .toList();
  }

  @override
  Future<List<SearchSet>> searchSets(String query) async {
    final catalog = await loadCatalog();
    final normalized = query.trim().toLowerCase();
    return catalog.sets
        .where((set) => set.searchableText.contains(normalized))
        .toList();
  }
}

List<SearchGame> _gamesFromCards(List<CardDataCardDto> cards) {
  final seen = <String>{};
  final games = <SearchGame>[];
  for (final card in cards) {
    final id = _gameIdFromObjectType(card.objectType);
    if (seen.add(id)) {
      games.add(SearchGame(id: id, label: _gameLabelFromObjectType(id)));
    }
  }

  if (games.isEmpty) {
    return const [SearchGame(id: 'tcg', label: 'TCG')];
  }
  return games;
}

SearchCard _cardFromDto(CardDataCardDto dto) {
  return SearchCard(
    id: dto.cardRef,
    gameId: _gameIdFromObjectType(dto.objectType),
    type: _cardTypeFromObjectType(dto.objectType),
    name: dto.name,
    priceUsd: null,
    previous30dPriceUsd: null,
    setName: dto.setName,
    metadataLine: _metadataLine(dto),
    variantLine: _variantLine(dto),
    quantity: 0,
    isWishlisted: false,
  );
}

SearchSet _setFromDto(CardDataSetDto dto) {
  return SearchSet(
    id: dto.setCode,
    gameId: 'tcg',
    name: dto.setName,
    subtitle: 'Card catalog set',
    releaseText: dto.setCode,
    cardCountText: '${dto.cardCount} cards',
  );
}

SearchCardType _cardTypeFromObjectType(String objectType) {
  return switch (_gameIdFromObjectType(objectType)) {
    'sports' => SearchCardType.sports,
    'sealed' => SearchCardType.sealed,
    'tcg' => SearchCardType.tcg,
    _ => SearchCardType.other,
  };
}

String _gameIdFromObjectType(String objectType) {
  return switch (objectType.trim().toLowerCase()) {
    'tcg' => 'tcg',
    'sports' => 'sports',
    'sealed' => 'sealed',
    _ => 'other',
  };
}

String _gameLabelFromObjectType(String objectType) {
  return switch (objectType) {
    'tcg' => 'TCG',
    'sports' => 'Sports',
    'sealed' => 'Sealed',
    _ => 'Other',
  };
}

String _metadataLine(CardDataCardDto dto) {
  final parts = [
    if (dto.rarity != null) dto.rarity!,
    if (dto.cardNumber.trim().isNotEmpty) '#${dto.cardNumber}',
  ];
  return parts.isEmpty ? dto.setCode : parts.join(' ');
}

String _variantLine(CardDataCardDto dto) {
  final parts = [
    if (dto.finish != null) dto.finish!,
    if (dto.language != null) dto.language!,
  ];
  return parts.isEmpty ? 'Standard' : parts.join(' / ');
}
