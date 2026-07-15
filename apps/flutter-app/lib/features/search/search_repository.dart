import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'search_models.dart';

abstract interface class SearchRepository {
  Future<SearchCatalog> loadCatalog();
  Future<List<SearchCard>> searchCards(String query);
  Future<List<SearchSet>> searchSets(String query);
}

abstract interface class SearchAssetRepository implements SearchRepository {
  Future<SearchAssetSnapshot> loadAssets(
    AuthSession session, {
    String? selectedFolderId,
  });
  Future<PortfolioItemDto> collect(
    AuthSession session, {
    required SearchCard card,
    required String folderId,
  });
  Future<void> deleteCollectionItem(AuthSession session, String itemId);
  Future<WishlistItemDto> addWishlist(AuthSession session, String cardRef);
  Future<void> deleteWishlist(AuthSession session, String itemId);
}

class SearchAssetSnapshot {
  const SearchAssetSnapshot({
    required this.folderId,
    required this.statesByCardRef,
  });

  final String folderId;
  final Map<String, SearchCardAssetState> statesByCardRef;
}

class SearchCardAssetState {
  const SearchCardAssetState({
    required this.quantity,
    required this.collectionItemIds,
    required this.wishlistItemId,
  });

  final int quantity;
  final List<String> collectionItemIds;
  final String? wishlistItemId;
}

class HttpSearchRepository implements SearchRepository, SearchAssetRepository {
  const HttpSearchRepository(
    this._api, {
    PortfolioApi? portfolioApi,
    String defaultSetQuery = 'pokemon',
  }) : _portfolioApi = portfolioApi,
       _defaultSetQuery = defaultSetQuery;

  final CardDataApi _api;
  final PortfolioApi? _portfolioApi;
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

  @override
  Future<SearchAssetSnapshot> loadAssets(
    AuthSession session, {
    String? selectedFolderId,
  }) async {
    final api = _requiredPortfolioApi;
    final results = await Future.wait([
      api.listFolders(session),
      api.listCollectionItems(session),
      api.listWishlistItems(session),
    ]);
    final folders = results[0] as List<PortfolioFolderDto>;
    final items = results[1] as List<PortfolioItemDto>;
    final wishlist = results[2] as List<WishlistItemDto>;
    if (folders.isEmpty) {
      throw StateError('Search requires at least one portfolio folder.');
    }
    final folder =
        folders.where((item) => item.id == selectedFolderId).firstOrNull ??
        folders.where((item) => item.isDefault).firstOrNull ??
        folders.first;
    final itemsByCardRef = <String, List<PortfolioItemDto>>{};
    for (final item in items.where((item) => item.folderId == folder.id)) {
      (itemsByCardRef[item.cardRef] ??= []).add(item);
    }
    final wishlistByCardRef = {
      for (final item in wishlist) item.cardRef: item.id,
    };
    final cardRefs = {...itemsByCardRef.keys, ...wishlistByCardRef.keys};

    return SearchAssetSnapshot(
      folderId: folder.id,
      statesByCardRef: {
        for (final cardRef in cardRefs)
          cardRef: SearchCardAssetState(
            quantity: (itemsByCardRef[cardRef] ?? const []).fold(
              0,
              (sum, item) => sum + item.quantity,
            ),
            collectionItemIds: [
              for (final item in itemsByCardRef[cardRef] ?? const []) item.id,
            ],
            wishlistItemId: wishlistByCardRef[cardRef],
          ),
      },
    );
  }

  @override
  Future<PortfolioItemDto> collect(
    AuthSession session, {
    required SearchCard card,
    required String folderId,
  }) {
    final sealed = card.type == SearchCardType.sealed;
    return _requiredPortfolioApi.quickCollect(
      session,
      cardRef: card.id,
      draft: PortfolioItemDraftDto(
        folderId: folderId,
        cardRef: card.id,
        objectType: card.type.name,
        grader: 'Raw',
        condition: sealed ? null : 'Near Mint (NM)',
        grade: null,
        language: card.language ?? 'English',
        finish: card.finish,
        quantity: 1,
        purchasePrice: null,
        purchaseCurrency: null,
        notes: null,
      ),
    );
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) {
    return _requiredPortfolioApi.deleteCollectionItem(session, itemId);
  }

  @override
  Future<WishlistItemDto> addWishlist(AuthSession session, String cardRef) {
    return _requiredPortfolioApi.addWishlist(session, cardRef);
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String itemId) {
    return _requiredPortfolioApi.deleteWishlist(session, itemId);
  }

  PortfolioApi get _requiredPortfolioApi {
    final api = _portfolioApi;
    if (api == null) {
      throw StateError('Portfolio API is unavailable.');
    }
    return api;
  }
}

List<SearchGame> _gamesFromCards(List<CardDataCardDto> cards) {
  final seen = <String>{};
  final games = <SearchGame>[];
  for (final card in cards) {
    final id = _gameIdFromCard(card);
    if (seen.add(id)) {
      games.add(SearchGame(id: id, label: _gameLabelFromCard(card)));
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
    gameId: _gameIdFromCard(dto),
    type: _cardTypeFromObjectType(dto.objectType),
    name: dto.name,
    priceUsd: dto.priceUsd,
    previous30dPriceUsd: dto.previous30dPriceUsd,
    setName: dto.setName,
    metadataLine: _metadataLine(dto),
    variantLine: _variantLine(dto),
    quantity: 0,
    isWishlisted: false,
    language: dto.language,
    finish: dto.finish,
    imageUrl: dto.imageUrl,
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

String _gameIdFromCard(CardDataCardDto card) {
  final game = card.game?.trim();
  if (game == null || game.isEmpty) {
    return _gameIdFromObjectType(card.objectType);
  }
  return game
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String _gameLabelFromCard(CardDataCardDto card) {
  final game = card.game?.trim();
  return game == null || game.isEmpty
      ? _gameLabelFromObjectType(_gameIdFromObjectType(card.objectType))
      : game;
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
