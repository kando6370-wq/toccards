import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_image/card_image_url.dart';
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

class CardDetailMarketData {
  const CardDetailMarketData({
    required this.prices,
    required this.marketPrices,
  });

  final List<CardDataMarketPriceDto> prices;
  final List<CardMarketPrice> marketPrices;
}

class CardDetailSeriesData {
  const CardDetailSeriesData({
    required this.marketPrices,
    required this.rawSeriesByRange,
    this.rawSeries = const [],
    required this.gradedSeriesByRange,
    this.gradedSeries = const [],
  });

  final List<CardMarketPrice> marketPrices;
  final Map<CardPriceRange, List<CardPricePoint>> rawSeriesByRange;
  final List<CardPriceChartSeries> rawSeries;
  final Map<CardPriceRange, List<CardPricePoint>> gradedSeriesByRange;
  final List<CardPriceChartSeries> gradedSeries;
}

abstract interface class CardDetailSectionRepository {
  Future<CardDetail> loadCoreDetail(String cardId);
  Future<CardDetail> loadAssetState(AuthSession session, CardDetail detail);
  Future<CardDetail> loadBaseDetail(AuthSession session, String cardId);
  Future<CardDetailMarketData> loadMarketPrices(
    String cardId, {
    String? finish,
    String? language,
  });
  Future<CardDetailSeriesData> loadPriceSeries(
    String cardId, {
    CardDetailMarketData? market,
    String? finish,
    Iterable<CardPriceRange> ranges = const [
      CardPriceRange.oneDay,
      CardPriceRange.sevenDays,
      CardPriceRange.fifteenDays,
      CardPriceRange.oneMonth,
      CardPriceRange.threeMonths,
    ],
  });
  Future<List<CardSoldListing>> loadSoldListings(String cardId);
}

abstract interface class PremiumCardDetailSectionRepository {
  Future<CardDetailSeriesData> loadPremiumPriceSeries(
    AuthSession session,
    String cardId, {
    CardDetailMarketData? market,
    String? finish,
    required Iterable<CardPriceRange> ranges,
    required bool localPremiumVerified,
  });
}

class HttpCardDetailRepository
    implements
        CardDetailRepository,
        CardDetailSectionRepository,
        PremiumCardDetailSectionRepository {
  const HttpCardDetailRepository({
    required PortfolioApi api,
    required CardDataApi cardDataApi,
  }) : _api = api,
       _cardDataApi = cardDataApi;

  final PortfolioApi _api;
  final CardDataApi _cardDataApi;

  @override
  Future<CardDetail> loadDetail(AuthSession session, String cardId) async {
    final results = await Future.wait([
      loadBaseDetail(session, cardId),
      loadMarketPrices(
        cardId,
      ).then((market) => loadPriceSeries(cardId, market: market)),
      loadSoldListings(cardId),
    ]);
    final detail = results[0] as CardDetail;
    final series = results[1] as CardDetailSeriesData;
    final soldListings = results[2] as List<CardSoldListing>;
    return _mergeSections(detail, series, soldListings);
  }

  @override
  Future<CardDetail> loadBaseDetail(AuthSession session, String cardId) async {
    final detail = await loadCoreDetail(cardId);
    return loadAssetState(session, detail);
  }

  @override
  Future<CardDetail> loadCoreDetail(String cardId) async {
    return _baseDetailFromDto(await _cardDataApi.getCard(cardId));
  }

  @override
  Future<CardDetail> loadAssetState(
    AuthSession session,
    CardDetail detail,
  ) async {
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
  Future<CardDetailMarketData> loadMarketPrices(
    String cardId, {
    String? finish,
    String? language,
  }) async {
    final prices = await _cardDataApi.getMarketPrices(
      cardId,
      finish: finish,
      language: language,
    );
    return CardDetailMarketData(
      prices: prices,
      marketPrices: prices
          .map(
            (price) => _marketPriceFromDto(
              price,
              const <CardPriceRange, List<CardPricePoint>>{},
            ),
          )
          .toList(),
    );
  }

  @override
  Future<CardDetailSeriesData> loadPriceSeries(
    String cardId, {
    CardDetailMarketData? market,
    String? finish,
    Iterable<CardPriceRange> ranges = const [
      CardPriceRange.oneDay,
      CardPriceRange.sevenDays,
      CardPriceRange.fifteenDays,
      CardPriceRange.oneMonth,
      CardPriceRange.threeMonths,
    ],
  }) {
    return _loadPriceSeries(
      cardId,
      market: market,
      finish: finish,
      ranges: ranges,
    );
  }

  @override
  Future<CardDetailSeriesData> loadPremiumPriceSeries(
    AuthSession session,
    String cardId, {
    CardDetailMarketData? market,
    String? finish,
    required Iterable<CardPriceRange> ranges,
    required bool localPremiumVerified,
  }) {
    return _loadPriceSeries(
      cardId,
      market: market,
      finish: finish,
      ranges: ranges,
      premiumSession: session,
      localPremiumVerified: localPremiumVerified,
    );
  }

  Future<CardDetailSeriesData> _loadPriceSeries(
    String cardId, {
    CardDetailMarketData? market,
    String? finish,
    required Iterable<CardPriceRange> ranges,
    AuthSession? premiumSession,
    bool localPremiumVerified = false,
  }) async {
    final prices =
        market?.prices ??
        await _cardDataApi.getMarketPrices(cardId, finish: finish);
    final rawPrices = prices
        .where((price) => price.grader.toLowerCase() == 'raw')
        .toList();
    final seriesPrices = premiumSession == null ? rawPrices : prices;
    final rangesByPrice = {
      for (final price in seriesPrices) price: ranges.toList(),
    };
    final seriesByPrice = await _loadSeriesForPrices(
      cardId,
      rangesByPrice,
      finish: finish,
      premiumSession: premiumSession,
      localPremiumVerified: localPremiumVerified,
    );
    final rawSeries = rawPrices
        .map(
          (price) => CardPriceChartSeries(
            label: price.condition?.trim().isNotEmpty == true
                ? price.condition!.trim()
                : 'Price',
            seriesByRange: seriesByPrice[price] ?? const {},
          ),
        )
        .toList();
    final gradedPrices = prices.where(
      (price) =>
          price.grader.toLowerCase() != 'raw' &&
          (premiumSession != null || price.history.length >= 2),
    );
    final gradedSeries = premiumSession == null
        ? gradedPrices
              .map((price) => _gradedSeriesFromDto(price, ranges))
              .toList()
        : gradedPrices
              .map(
                (price) => CardPriceChartSeries(
                  label: _gradedSeriesLabel(price),
                  seriesByRange: seriesByPrice[price] ?? const {},
                ),
              )
              .toList();
    return CardDetailSeriesData(
      marketPrices: prices
          .map(
            (price) =>
                _marketPriceFromDto(price, seriesByPrice[price] ?? const {}),
          )
          .toList(),
      rawSeriesByRange: rawSeries.isEmpty
          ? const <CardPriceRange, List<CardPricePoint>>{}
          : rawSeries.first.seriesByRange,
      rawSeries: rawSeries,
      gradedSeriesByRange: gradedSeries.isEmpty
          ? const <CardPriceRange, List<CardPricePoint>>{}
          : gradedSeries.first.seriesByRange,
      gradedSeries: gradedSeries,
    );
  }

  @override
  Future<List<CardSoldListing>> loadSoldListings(String cardId) async {
    final listings = await _cardDataApi.getSoldListings(cardId);
    return listings
        .map(
          (listing) => CardSoldListing(
            dateText: listing.date,
            title: listing.title,
            priceUsd: listing.price,
            platform: listing.platform,
            url: listing.url,
          ),
        )
        .toList();
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

  Future<List<CardPricePoint>> _loadSeries(
    String cardRef,
    CardDataMarketPriceDto price,
    CardPriceRange range,
    String? finish,
  ) async {
    final series = await _cardDataApi.getPriceSeries(
      cardRef,
      days: range.days,
      grader: price.grader,
      grade: price.grade,
      condition: price.condition,
      finish: finish,
    );
    return series
        .map(
          (point) =>
              CardPricePoint(dateLabel: point.date, priceUsd: point.price),
        )
        .toList();
  }

  Future<Map<CardPriceRange, List<CardPricePoint>>> _loadSeriesByRange(
    String cardRef,
    CardDataMarketPriceDto price, {
    required Iterable<CardPriceRange> ranges,
    String? finish,
  }) async {
    return Map.fromEntries(
      await Future.wait(
        ranges.map((range) async {
          return MapEntry(
            range,
            await _loadSeries(cardRef, price, range, finish),
          );
        }),
      ),
    );
  }

  Future<Map<CardDataMarketPriceDto, Map<CardPriceRange, List<CardPricePoint>>>>
  _loadSeriesForPrices(
    String cardRef,
    Map<CardDataMarketPriceDto, List<CardPriceRange>> rangesByPrice, {
    String? finish,
    AuthSession? premiumSession,
    bool localPremiumVerified = false,
  }) async {
    final api = _cardDataApi;
    if (premiumSession != null) {
      if (api is! PremiumPriceSeriesApi) {
        throw const CardDataApiException('Premium price history unavailable.');
      }
      final premiumApi = api as PremiumPriceSeriesApi;
      final keys = [
        for (final entry in rangesByPrice.entries)
          for (final range in entry.value) (entry.key, range),
      ];
      final results = await premiumApi
          .getPremiumPriceSeriesBatch(premiumSession, cardRef, [
            for (final (price, range) in keys)
              CardDataPriceSeriesQuery(
                days: range.days,
                grader: price.grader,
                grade: price.grade,
                condition: price.condition,
                finish: finish,
              ),
          ], localPremiumVerified: localPremiumVerified);
      return _mapBatchSeries(rangesByPrice.keys, keys, results);
    }
    if (api is BatchCardDataApi) {
      final batchApi = api as BatchCardDataApi;
      try {
        final keys = [
          for (final entry in rangesByPrice.entries)
            for (final range in entry.value) (entry.key, range),
        ];
        final results = await batchApi.getPriceSeriesBatch(cardRef, [
          for (final (price, range) in keys)
            CardDataPriceSeriesQuery(
              days: range.days,
              grader: price.grader,
              grade: price.grade,
              condition: price.condition,
              finish: finish,
            ),
        ]);
        return _mapBatchSeries(rangesByPrice.keys, keys, results);
      } catch (_) {
        // Supports clients deployed before the batch Workers route is live.
      }
    }

    return Map.fromEntries(
      await Future.wait(
        rangesByPrice.entries.map(
          (entry) async => MapEntry(
            entry.key,
            await _loadSeriesByRange(
              cardRef,
              entry.key,
              ranges: entry.value,
              finish: finish,
            ),
          ),
        ),
      ),
    );
  }
}

Map<CardDataMarketPriceDto, Map<CardPriceRange, List<CardPricePoint>>>
_mapBatchSeries(
  Iterable<CardDataMarketPriceDto> prices,
  List<(CardDataMarketPriceDto, CardPriceRange)> keys,
  List<List<CardDataPricePointDto>> results,
) {
  final mapped = {
    for (final price in prices) price: <CardPriceRange, List<CardPricePoint>>{},
  };
  for (var index = 0; index < keys.length; index += 1) {
    final (price, range) = keys[index];
    mapped[price]![range] = _pricePointsFromDtos(results[index]);
  }
  return mapped;
}

List<CardPricePoint> _pricePointsFromDtos(List<CardDataPricePointDto> points) {
  return points
      .map(
        (point) => CardPricePoint(dateLabel: point.date, priceUsd: point.price),
      )
      .toList();
}

CardDetail _baseDetailFromDto(CardDataCardDto card) {
  return CardDetail(
    id: card.cardRef,
    imageUrl: cardImageUrl(card.cardRef, CardImageVariant.detail),
    type: _detailTypeFromObjectType(card.objectType),
    name: card.name,
    game: card.game?.trim().isNotEmpty == true
        ? card.game!.trim()
        : _gameLabelFromObjectType(card.objectType),
    setName: card.setName,
    identityLine: _identityLine(card),
    finish: card.finish ?? 'Unknown',
    language: card.language ?? 'Unknown',
    availableFinishes: card.availableFinishes,
    availableLanguages: card.availableLanguages,
    quantity: 0,
    isWishlisted: false,
    marketPrices: [
      CardMarketPrice(
        label: 'Raw',
        priceUsd: card.priceUsd,
        previous30dPriceUsd: card.previous30dPriceUsd,
        previous7dPriceUsd: card.previous7dPriceUsd,
        increasePercent: card.priceChange7dPercent,
      ),
    ],
  );
}

CardDetail _mergeSections(
  CardDetail detail,
  CardDetailSeriesData series,
  List<CardSoldListing> soldListings,
) {
  return CardDetail(
    id: detail.id,
    imageUrl: detail.imageUrl,
    type: detail.type,
    name: detail.name,
    game: detail.game,
    setName: detail.setName,
    identityLine: detail.identityLine,
    finish: detail.finish,
    language: detail.language,
    availableFinishes: detail.availableFinishes,
    availableLanguages: detail.availableLanguages,
    quantity: detail.quantity,
    isWishlisted: detail.isWishlisted,
    wishlistItemId: detail.wishlistItemId,
    marketPrices: series.marketPrices.isEmpty
        ? detail.marketPrices
        : series.marketPrices,
    portfolioFolders: detail.portfolioFolders,
    collectionItems: detail.collectionItems,
    priceSeriesByRange: series.rawSeriesByRange,
    rawPriceSeries: series.rawSeries,
    gradedPriceSeriesByRange: series.gradedSeriesByRange,
    gradedPriceSeries: series.gradedSeries,
    soldListings: soldListings,
  );
}

CardMarketPrice _marketPriceFromDto(
  CardDataMarketPriceDto dto,
  Map<CardPriceRange, List<CardPricePoint>> seriesByRange,
) {
  final history = _pricePointsFromDtos(dto.history);
  return CardMarketPrice(
    label: _marketPriceLabel(dto),
    grader: dto.grader,
    grade: dto.grade,
    gradeLabel: dto.gradeLabel,
    condition: dto.condition,
    pricechartingId: dto.pricechartingId,
    productSubType: dto.productSubType,
    increasePercent: dto.increasePercent,
    history: history,
    priceUsd: dto.price,
    previous30dPriceUsd: _previousPrice(seriesByRange[CardPriceRange.oneMonth]),
    previous7dPriceUsd: dto.previous7dPriceUsd,
  );
}

CardPriceChartSeries _gradedSeriesFromDto(
  CardDataMarketPriceDto dto,
  Iterable<CardPriceRange> ranges,
) {
  final points = _pricePointsFromDtos(dto.history);
  return CardPriceChartSeries(
    label: _gradedSeriesLabel(dto),
    seriesByRange: {
      for (final range in ranges)
        range: _filterPointsByDays(points, range.days),
    },
  );
}

String _gradedSeriesLabel(CardDataMarketPriceDto dto) {
  final grade =
      dto.gradeLabel ?? (dto.grade == null ? '' : _gradeText(dto.grade!));
  return [dto.grader, if (grade.isNotEmpty) grade].join(' ');
}

List<CardPricePoint> _filterPointsByDays(
  List<CardPricePoint> points,
  int days,
) {
  if (points.isEmpty) return const [];
  final sorted = [...points]
    ..sort((left, right) => left.dateLabel.compareTo(right.dateLabel));
  final latest = DateTime.tryParse(sorted.last.dateLabel);
  if (latest == null) return sorted;
  final cutoff = latest.subtract(Duration(days: days));
  final inRange = sorted.where((point) {
    final date = DateTime.tryParse(point.dateLabel);
    return date != null && !date.isBefore(cutoff);
  }).toList();
  final baseline = sorted.where((point) {
    final date = DateTime.tryParse(point.dateLabel);
    return date != null && date.isBefore(cutoff);
  }).lastOrNull;
  return [if (baseline != null) baseline, ...inRange];
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
    grade: dto.grade == null ? null : _gradeText(dto.grade!),
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
