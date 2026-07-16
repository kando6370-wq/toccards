import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'card_detail_models.dart';

abstract interface class CardDetailRepository {
  Future<CardDetail> loadDetail(AuthSession session, String cardId);
  Future<CardCollectionItem> quickCollect(
    AuthSession session,
    CardDetail detail,
  );
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  });
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  });
  Future<void> deleteCollectionItem(AuthSession session, String itemId);
  Future<String> addWishlist(AuthSession session, String cardRef);
  Future<void> deleteWishlist(AuthSession session, String wishlistItemId);
}

class HttpCardDetailRepository implements CardDetailRepository {
  const HttpCardDetailRepository({
    required PortfolioApi api,
    required CardDataApi cardDataApi,
  }) : _api = api,
       _cardDataApi = cardDataApi;

  final PortfolioApi _api;
  final CardDataApi _cardDataApi;

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final detail = await _loadCardDataDetail(cardId);
    final results = await Future.wait([
      _api.listFolders(session),
      _api.listCollectionItems(session),
      _api.listWishlistItems(session),
    ]);
    final folders = results[0] as List<PortfolioFolderDto>;
    final items = results[1] as List<PortfolioItemDto>;
    final wishlist = results[2] as List<WishlistItemDto>;
    return _mergeAssetState(detail, folders, items, wishlist);
  }

  @override
  Future<CardCollectionItem> quickCollect(
    AuthSession session,
    CardDetail detail,
  ) async {
    final defaultFolder = _defaultPortfolioFolder(detail.portfolioFolders);
    final dto = await _api.quickCollect(
      session,
      cardRef: detail.id,
      draft: _draftFromCardItem(
        detail,
        CardCollectionItem(
          id: '',
          cardRef: detail.id,
          folderId: defaultFolder?.id,
          portfolioName: defaultFolder?.name ?? 'Main',
          quantity: 1,
          grader: 'Raw',
          condition: 'Near Mint (NM)',
          grade: null,
          language: detail.language,
          finish: detail.finish,
          purchasePriceUsd: null,
          notes: 'Quick collected from CardDetail.',
        ),
      ),
    );
    return _collectionItemFromDto(dto, const {});
  }

  @override
  Future<CardCollectionItem> createCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    final dto = await _api.createCollectionItem(
      session,
      _draftFromCardItem(detail, item),
    );
    return _collectionItemFromDto(dto, {item.folderId: item.portfolioName});
  }

  @override
  Future<CardCollectionItem> updateCollectionItem(
    AuthSession session, {
    required CardDetail detail,
    required CardCollectionItem item,
  }) async {
    final dto = await _api.updateCollectionItem(
      session,
      itemId: item.id,
      draft: _draftFromCardItem(detail, item),
    );
    return _collectionItemFromDto(dto, {item.folderId: item.portfolioName});
  }

  @override
  Future<void> deleteCollectionItem(AuthSession session, String itemId) {
    return _api.deleteCollectionItem(session, itemId);
  }

  @override
  Future<String> addWishlist(AuthSession session, String cardRef) async {
    final dto = await _api.addWishlist(session, cardRef);
    return dto.id;
  }

  @override
  Future<void> deleteWishlist(AuthSession session, String wishlistItemId) {
    return _api.deleteWishlist(session, wishlistItemId);
  }

  Future<CardDetail> _loadCardDataDetail(String cardId) async {
    final api = _cardDataApi;
    final card = await api.getCard(cardId);
    final prices = await api.getMarketPrices(cardId);
    final seriesByPrice = Map.fromEntries(
      await Future.wait(
        prices.map(
          (price) async =>
              MapEntry(price, await _loadSeriesByRange(card.cardRef, price)),
        ),
      ),
    );

    final rawPrice = _firstWhereOrNull(
      prices,
      (price) => price.grader.toLowerCase() == 'raw',
    );
    final gradedPrice = _firstWhereOrNull(
      prices,
      (price) => price.grader.toLowerCase() != 'raw',
    );
    final rawSeries = rawPrice == null
        ? const <CardPriceRange, List<CardPricePoint>>{}
        : seriesByPrice[rawPrice]!;
    final gradedSeries = gradedPrice == null
        ? const <CardPriceRange, List<CardPricePoint>>{}
        : seriesByPrice[gradedPrice]!;
    final marketPrices = prices
        .map((price) => _marketPriceFromDto(price, seriesByPrice[price]!))
        .toList();
    final soldListings = await api.getSoldListings(card.cardRef);

    return CardDetail(
      id: card.cardRef,
      imageUrl: card.imageUrl,
      type: _detailTypeFromObjectType(card.objectType),
      name: card.name,
      game: card.game?.trim().isNotEmpty == true
          ? card.game!.trim()
          : _gameLabelFromObjectType(card.objectType),
      setName: card.setName,
      identityLine: _identityLine(card),
      finish: card.finish ?? 'Unknown',
      language: card.language ?? 'Unknown',
      quantity: 0,
      isWishlisted: false,
      marketPrices: marketPrices.isEmpty
          ? const [
              CardMarketPrice(
                label: 'Raw',
                priceUsd: null,
                previous30dPriceUsd: null,
              ),
            ]
          : marketPrices,
      priceSeriesByRange: rawSeries,
      gradedPriceSeriesByRange: gradedSeries,
      soldListings: soldListings
          .map(
            (listing) => CardSoldListing(
              dateText: listing.date,
              title: listing.title,
              priceUsd: listing.price,
              platform: listing.platform,
              url: listing.url,
            ),
          )
          .toList(),
    );
  }

  Future<Map<CardPriceRange, List<CardPricePoint>>> _loadSeriesByRange(
    String cardRef,
    CardDataMarketPriceDto price,
  ) async {
    final api = _cardDataApi;
    return Map.fromEntries(
      await Future.wait(
        CardPriceRange.values.map((range) async {
          final series = await api.getPriceSeries(
            cardRef,
            days: range.days,
            grader: price.grader,
            grade: price.grade,
            condition: price.condition,
          );
          return MapEntry(
            range,
            series
                .map(
                  (point) => CardPricePoint(
                    dateLabel: point.date,
                    priceUsd: point.price,
                  ),
                )
                .toList(),
          );
        }),
      ),
    );
  }
}

CardMarketPrice _marketPriceFromDto(
  CardDataMarketPriceDto dto,
  Map<CardPriceRange, List<CardPricePoint>> seriesByRange,
) {
  return CardMarketPrice(
    label: _marketPriceLabel(dto),
    priceUsd: dto.price,
    previous30dPriceUsd: _previousPrice(seriesByRange[CardPriceRange.oneMonth]),
    previous7dPriceUsd: _previousPrice(seriesByRange[CardPriceRange.sevenDays]),
  );
}

double? _previousPrice(List<CardPricePoint>? points) {
  if (points == null || points.length < 2) {
    return null;
  }
  return points.first.priceUsd;
}

String _marketPriceLabel(CardDataMarketPriceDto dto) {
  if (dto.grader.toLowerCase() == 'raw') {
    return ['Raw', if (dto.condition != null) dto.condition!].join(' ');
  }

  return [dto.grader, if (dto.grade != null) _gradeText(dto.grade!)].join(' ');
}

String _gradeText(double grade) {
  if (grade == grade.truncateToDouble()) {
    return grade.toInt().toString();
  }
  return grade.toString();
}

CardDetailType _detailTypeFromObjectType(String objectType) {
  return switch (objectType.trim().toLowerCase()) {
    'tcg' => CardDetailType.tcg,
    'sports' => CardDetailType.sports,
    'sealed' => CardDetailType.sealed,
    _ => CardDetailType.other,
  };
}

String _gameLabelFromObjectType(String objectType) {
  return switch (objectType.trim().toLowerCase()) {
    'tcg' => 'TCG',
    'sports' => 'Sports',
    'sealed' => 'Sealed',
    _ => 'Other',
  };
}

String _identityLine(CardDataCardDto card) {
  final parts = [
    if (card.rarity != null) card.rarity!,
    if (card.cardNumber.trim().isNotEmpty) '#${card.cardNumber}',
  ];
  return parts.isEmpty ? card.setCode : parts.join(' ');
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T item) test) {
  for (final item in items) {
    if (test(item)) {
      return item;
    }
  }
  return null;
}

CardDetail _mergeAssetState(
  CardDetail detail,
  List<PortfolioFolderDto> folders,
  List<PortfolioItemDto> items,
  List<WishlistItemDto> wishlist,
) {
  final folderNames = {for (final folder in folders) folder.id: folder.name};
  final collectionItems = items
      .where((item) => item.cardRef == detail.id)
      .map((item) => _collectionItemFromDto(item, folderNames))
      .toList();
  WishlistItemDto? wishlistItem;
  for (final item in wishlist) {
    if (item.cardRef == detail.id) {
      wishlistItem = item;
      break;
    }
  }
  final quantity = collectionItems.fold<int>(
    0,
    (sum, item) => sum + item.quantity,
  );

  return detail.copyWith(
    quantity: quantity,
    portfolioFolders: folders
        .map(
          (folder) => CardPortfolioFolder(
            id: folder.id,
            name: folder.name,
            isDefault: folder.isDefault,
          ),
        )
        .toList(),
    collectionItems: collectionItems,
    isWishlisted: wishlistItem != null,
    wishlistItemId: wishlistItem?.id,
  );
}

CardCollectionItem _collectionItemFromDto(
  PortfolioItemDto dto,
  Map<String?, String> folderNames,
) {
  return CardCollectionItem(
    id: dto.id,
    cardRef: dto.cardRef,
    folderId: dto.folderId,
    portfolioName: folderNames[dto.folderId] ?? dto.folderId,
    quantity: dto.quantity,
    grader: dto.grader,
    condition: dto.condition,
    grade: dto.grade?.toString(),
    language: dto.language,
    finish: dto.finish,
    purchasePriceUsd: dto.purchasePrice,
    notes: dto.notes ?? '',
  );
}

PortfolioItemDraftDto _draftFromCardItem(
  CardDetail detail,
  CardCollectionItem item,
) {
  final folderId = item.folderId;
  if (folderId == null) {
    throw StateError('Collection Item requires a server portfolio folder.');
  }
  return PortfolioItemDraftDto(
    folderId: folderId,
    cardRef: item.cardRef.isEmpty ? detail.id : item.cardRef,
    objectType: _objectTypeFromDetail(detail),
    grader: item.grader,
    condition: item.condition,
    grade: double.tryParse(item.grade ?? ''),
    language: item.language,
    finish: item.finish,
    quantity: item.quantity,
    purchasePrice: item.purchasePriceUsd,
    purchaseCurrency: item.purchasePriceUsd == null ? null : 'USD',
    notes: item.notes.trim().isEmpty ? null : item.notes,
  );
}

String _objectTypeFromDetail(CardDetail detail) {
  return switch (detail.type) {
    CardDetailType.tcg => 'tcg',
    CardDetailType.sports => 'sports',
    CardDetailType.sealed => 'sealed',
    CardDetailType.other => 'other',
  };
}

CardPortfolioFolder? _defaultPortfolioFolder(
  List<CardPortfolioFolder> folders,
) {
  for (final folder in folders) {
    if (folder.isDefault) {
      return folder;
    }
  }
  return folders.firstOrNull;
}
