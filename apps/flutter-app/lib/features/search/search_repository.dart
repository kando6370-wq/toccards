import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_image/card_image_url.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'search_models.dart';

abstract interface class SearchRepository {
  Future<SearchCatalog> loadCatalog();
  Future<List<SearchCard>> searchCards(String query, {String? game});
  Future<List<SearchSet>> searchSets(String query, {String? game});
}

abstract interface class PaginatedSearchRepository {
  Future<List<SearchCard>> searchCardPage(
    String query, {
    String? game,
    required int page,
  });
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

class HttpSearchRepository
    implements
        SearchRepository,
        PaginatedSearchRepository,
        SearchAssetRepository {
  const HttpSearchRepository(
    this._api, {
    SetCatalogApi? setCatalogApi,
    PortfolioApi? portfolioApi,
    String? defaultSetQuery,
  }) : _setCatalogApi = setCatalogApi,
       _portfolioApi = portfolioApi,
       _defaultSetQuery = defaultSetQuery;

  final CardDataApi _api;
  final SetCatalogApi? _setCatalogApi;
  final PortfolioApi? _portfolioApi;
  final String? _defaultSetQuery;

  @override
  Future<SearchCatalog> loadCatalog() async {
    final gameDtos = await _setCatalogApi?.listGames();
    late final List<SearchGame> games;
    late final List<SearchCard> cards;
    if (gameDtos == null) {
      final seedCards = await _api.trendingCards();
      games = _gamesFromCards(seedCards);
      cards = seedCards.map(_cardFromDto).toList();
      final setQuery = _defaultSetQuery ?? games.first.label;
      final sets = await _api.searchSets('', game: setQuery);
      return SearchCatalog(
        games: games,
        cards: cards,
        sets: sets.map(_setFromDto).toList(),
      );
    } else {
      games = gameDtos
          .map(
            (game) =>
                SearchGame(id: _gameIdFromValue(game.name), label: game.name),
          )
          .toList();
      final setQuery = _defaultSetQuery ?? games.first.label;
      final results = await Future.wait([
        searchCardPage('', game: games.first.label, page: 1),
        _api.searchSets('', game: setQuery),
      ]);
      cards = results[0] as List<SearchCard>;
      final sets = results[1] as List<CardDataSetDto>;
      return SearchCatalog(
        games: games,
        cards: cards,
        sets: sets.map(_setFromDto).toList(),
      );
    }
  }

  @override
  Future<List<SearchCard>> searchCards(String query, {String? game}) async {
    return searchCardPage(query, game: game, page: 1);
  }

  @override
  Future<List<SearchCard>> searchCardPage(
    String query, {
    String? game,
    required int page,
  }) async {
    final cards = _api is PaginatedCardDataApi
        ? await (_api as PaginatedCardDataApi).searchCardPage(
            query,
            game: game,
            page: page,
          )
        : page == 1
        ? await _api.searchCards(query, game: game)
        : const <CardDataCardDto>[];
    return cards.map(_cardFromDto).toList();
  }

  @override
  Future<List<SearchSet>> searchSets(String query, {String? game}) async {
    final sets = _setCatalogApi == null
        ? await _api.searchSets(query, game: game)
        : await _setCatalogApi.searchCatalogSets(query, game: game);
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
    imageUrl: cardImageUrl(dto.cardRef, CardImageVariant.list),
  );
}

SearchSet _setFromDto(CardDataSetDto dto) {
  return SearchSet(
    id: dto.setCode,
    gameId: _gameIdFromValue(dto.game),
    name: dto.setName,
    subtitle: dto.game ?? 'Card catalog set',
    releaseText: dto.setCode,
    cardCountText: '${dto.cardCount} cards',
    game: dto.game ?? 'TCG',
    imageUrl: dto.imageUrl,
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
  if (card.game == null || card.game!.trim().isEmpty) {
    return _gameIdFromObjectType(card.objectType);
  }

  return _gameIdFromValue(card.game);
}

String _gameIdFromValue(String? value) {
  final game = value?.trim();
  if (game == null || game.isEmpty) return 'tcg';

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
