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
    priceUsd: dto.priceUsd,
    previous30dPriceUsd: dto.previous30dPriceUsd,
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
