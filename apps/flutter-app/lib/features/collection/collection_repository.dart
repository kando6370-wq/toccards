import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'collection_models.dart';

abstract interface class CollectionRepository {
  Future<CollectionDashboard> loadDashboard(AuthSession session);
  Future<CollectionFolder> createFolder(AuthSession session, String name);
  Future<CollectionFolder> renameFolder(
    AuthSession session,
    String folderId,
    String name,
  );
  Future<void> setDefaultFolder(AuthSession session, String folderId);
  Future<void> reorderFolders(AuthSession session, List<String> folderIds);
  Future<void> deleteFolder(AuthSession session, String folderId);
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  });
}

class HttpCollectionRepository implements CollectionRepository {
  const HttpCollectionRepository(
    this._api, {
    required PortfolioManagementApi managementApi,
    CardDataApi? cardDataApi,
  }) : _managementApi = managementApi,
       _cardDataApi = cardDataApi;

  final PortfolioApi _api;
  final PortfolioManagementApi _managementApi;
  final CardDataApi? _cardDataApi;

  @override
  Future<CollectionDashboard> loadDashboard(AuthSession session) async {
    final results = await Future.wait([
      _api.listFolders(session),
      _api.listCollectionItems(session),
      _api.listWishlistItems(session),
      _managementApi.getPreferences(session),
    ]);
    final folders = results[0] as List<PortfolioFolderDto>;
    final items = results[1] as List<PortfolioItemDto>;
    final wishlist = results[2] as List<WishlistItemDto>;
    final preferences = results[3] as UserPreferenceDto;
    final presentations = await _loadPresentations(items, wishlist);
    final portfolioItems = await Future.wait(
      items.map(
        (item) => _collectionItemFromPortfolioDto(
          item,
          presentations[item.cardRef],
          _cardDataApi,
        ),
      ),
    );
    final wishlistItems = await Future.wait(
      wishlist.map(
        (item) => _collectionItemFromWishlistDto(
          item,
          presentations[item.cardRef],
          _cardDataApi,
        ),
      ),
    );

    return CollectionDashboard(
      folders: folders.map(_folderFromDto).toList(),
      portfolioItems: portfolioItems,
      wishlistItems: wishlistItems,
      currencyCode: preferences.currency,
      amountHidden: preferences.amountHidden,
    );
  }

  @override
  Future<CollectionFolder> createFolder(
    AuthSession session,
    String name,
  ) async {
    return _folderFromDto(await _managementApi.createFolder(session, name));
  }

  @override
  Future<CollectionFolder> renameFolder(
    AuthSession session,
    String folderId,
    String name,
  ) async {
    return _folderFromDto(
      await _managementApi.renameFolder(session, folderId, name),
    );
  }

  @override
  Future<void> setDefaultFolder(AuthSession session, String folderId) {
    return _managementApi.setDefaultFolder(session, folderId);
  }

  @override
  Future<void> reorderFolders(
    AuthSession session,
    List<String> folderIds,
  ) {
    return _managementApi.reorderFolders(session, folderIds);
  }

  @override
  Future<void> deleteFolder(AuthSession session, String folderId) {
    return _managementApi.deleteFolder(session, folderId);
  }

  @override
  Future<void> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    await _managementApi.updatePreferences(
      session,
      currency: currency,
      amountHidden: amountHidden,
      lastSelectedFolderId: lastSelectedFolderId,
    );
  }

  Future<Map<String, _CollectionPresentation>> _loadPresentations(
    List<PortfolioItemDto> items,
    List<WishlistItemDto> wishlist,
  ) async {
    final api = _cardDataApi;
    if (api == null) {
      return const {};
    }

    final cardRefs = <String>{
      for (final item in items) item.cardRef,
      for (final item in wishlist) item.cardRef,
    };
    final entries = await Future.wait(cardRefs.map((cardRef) async {
      final CardDataCardDto card;
      try {
        card = await api.getCard(cardRef);
      } catch (_) {
        return MapEntry(cardRef, _missingPresentation(cardRef));
      }
      var prices = const <CardDataMarketPriceDto>[];
      try {
        prices = await api.getMarketPrices(cardRef);
      } catch (_) {
      }
      return MapEntry(cardRef, _presentationFromCardData(card, prices));
    }));
    return Map.fromEntries(entries);
  }
}

CollectionFolder _folderFromDto(PortfolioFolderDto dto) {
  return CollectionFolder(id: dto.id, name: dto.name, isDefault: dto.isDefault);
}

Future<CollectionItem> _collectionItemFromPortfolioDto(
  PortfolioItemDto dto,
  _CollectionPresentation? presentation,
  CardDataApi? api,
) async {
  final card = presentation ?? _missingPresentation(dto.cardRef);
  final marketPrice = _marketPriceFor(
    card.prices,
    grader: dto.grader,
    grade: dto.grade,
    condition: dto.condition,
  );
  final previousPrice = await _previous30dPrice(
    api,
    dto.cardRef,
    marketPrice,
  );
  return CollectionItem(
    id: dto.id,
    cardRef: dto.cardRef,
    folderId: dto.folderId,
    name: card.name,
    setName: card.setName,
    number: card.number,
    game: card.game,
    language: dto.language ?? card.language,
    finish: dto.finish ?? card.finish,
    grader: dto.grader,
    condition: dto.condition,
    grade: dto.grade,
    quantity: dto.quantity,
    marketValueUsd: marketPrice?.price,
    previous30dPriceUsd: previousPrice,
    createdAtSort: dto.createdAt.millisecondsSinceEpoch,
    imageUrl: card.imageUrl,
  );
}

Future<CollectionItem> _collectionItemFromWishlistDto(
  WishlistItemDto dto,
  _CollectionPresentation? presentation,
  CardDataApi? api,
) async {
  final card = presentation ?? _missingPresentation(dto.cardRef);
  final marketPrice = _wishlistMarketPrice(card.prices);
  final previousPrice = await _previous30dPrice(
    api,
    dto.cardRef,
    marketPrice,
  );
  return CollectionItem(
    id: dto.id,
    cardRef: dto.cardRef,
    folderId: null,
    name: card.name,
    setName: card.setName,
    number: card.number,
    game: card.game,
    language: card.language,
    finish: card.finish,
    grader: 'Raw',
    condition: marketPrice?.condition,
    grade: null,
    quantity: 1,
    marketValueUsd: marketPrice?.price,
    previous30dPriceUsd: previousPrice,
    createdAtSort: dto.createdAt.millisecondsSinceEpoch,
    imageUrl: card.imageUrl,
  );
}

_CollectionPresentation _presentationFromCardData(
  CardDataCardDto card,
  List<CardDataMarketPriceDto> prices,
) {
  return _CollectionPresentation(
    name: card.name,
    setName: card.setName,
    number: card.cardNumber.isEmpty ? '--' : '#${card.cardNumber}',
    game: card.game ?? _gameLabelFromObjectType(card.objectType),
    language: card.language ?? 'Unknown',
    finish: card.finish ?? 'Unknown',
    imageUrl: card.imageUrl,
    prices: prices,
  );
}

_CollectionPresentation _missingPresentation(String cardRef) {
  return _CollectionPresentation(
    name: cardRef,
    setName: 'Card data unavailable',
    number: '--',
    game: 'Unknown',
    language: 'Unknown',
    finish: 'Unknown',
    imageUrl: null,
    prices: const [],
  );
}

CardDataMarketPriceDto? _marketPriceFor(
  List<CardDataMarketPriceDto> prices, {
  required String grader,
  required double? grade,
  required String? condition,
}) {
  for (final price in prices) {
    if (_matchesMarketPrice(
      price,
      grader: grader,
      grade: grade,
      condition: condition,
    )) {
      return price;
    }
  }
  return null;
}

CardDataMarketPriceDto? _wishlistMarketPrice(
  List<CardDataMarketPriceDto> prices,
) {
  for (final price in prices) {
    if (price.grader.toLowerCase() == 'raw' &&
        _normalizedCondition(price.condition) == 'near mint') {
      return price;
    }
  }
  for (final price in prices) {
    if (price.grader.toLowerCase() == 'raw') {
      return price;
    }
  }
  return null;
}

Future<double?> _previous30dPrice(
  CardDataApi? api,
  String cardRef,
  CardDataMarketPriceDto? marketPrice,
) async {
  if (api == null || marketPrice?.price == null) {
    return null;
  }
  try {
    final series = await api.getPriceSeries(
      cardRef,
      days: 30,
      grader: marketPrice!.grader,
      grade: marketPrice.grade,
      condition: marketPrice.condition,
    );
    return series.length > 1 ? series.first.price : null;
  } catch (_) {
    return null;
  }
}

bool _matchesMarketPrice(
  CardDataMarketPriceDto price, {
  required String grader,
  required double? grade,
  required String? condition,
}) {
  if (price.grader.toLowerCase() != grader.toLowerCase()) {
    return false;
  }
  if (grade != null && price.grade != grade) {
    return false;
  }
  if (condition != null &&
      _normalizedCondition(price.condition) != _normalizedCondition(condition)) {
    return false;
  }
  return true;
}

String _normalizedCondition(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');
}

String _gameLabelFromObjectType(String objectType) {
  return switch (objectType.trim().toLowerCase()) {
    'tcg' => 'TCG',
    'sports' => 'Sports',
    'sealed' => 'Sealed',
    _ => 'Other',
  };
}

class _CollectionPresentation {
  const _CollectionPresentation({
    required this.name,
    required this.setName,
    required this.number,
    required this.game,
    required this.language,
    required this.finish,
    required this.imageUrl,
    this.prices = const [],
  });

  final String name;
  final String setName;
  final String number;
  final String game;
  final String language;
  final String finish;
  final String? imageUrl;
  final List<CardDataMarketPriceDto> prices;
}
