import 'dart:async';

import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'home_models.dart';

abstract interface class HomeRepository {
  FutureOr<HomeDashboard> loadDashboard();
}

class ApiHomeRepository implements HomeRepository {
  const ApiHomeRepository({
    required this.session,
    required this.portfolioApi,
    required this.managementApi,
    required this.cardDataApi,
  });

  final AuthSession session;
  final PortfolioApi portfolioApi;
  final PortfolioManagementApi managementApi;
  final CardDataApi cardDataApi;

  @override
  Future<HomeDashboard> loadDashboard() async {
    final source = await Future.wait([
      portfolioApi.listFolders(session),
      portfolioApi.listCollectionItems(session),
      portfolioApi.getValuationHistory(session),
      managementApi.getPreferences(session),
    ]);
    final folders = source[0] as List<PortfolioFolderDto>;
    final items = source[1] as List<PortfolioItemDto>;
    final valuations = source[2] as List<PortfolioFolderValuationDto>;
    final preferences = source[3] as UserPreferenceDto;
    final assets = await Future.wait(items.map(_loadAsset));
    final valuedAssets = assets.whereType<_HomeAsset>().toList();
    final trending = await _loadTrending();
    final homeFolders = folders
        .map(
          (folder) => HomeFolder(
            id: folder.id,
            name: folder.name,
            isDefault: folder.isDefault,
          ),
        )
        .toList();

    if (homeFolders.isEmpty) {
      throw StateError('Home requires at least one portfolio folder.');
    }
    if (!homeFolders.any((folder) => folder.isDefault)) {
      final first = homeFolders.first;
      homeFolders[0] = HomeFolder(
        id: first.id,
        name: first.name,
        isDefault: true,
      );
    }

    final portfolios = <String, PortfolioSummary>{};
    final highlights = <String, List<HomeCardHighlight>>{};
    final primaryHighlights = <String, HomeCardHighlight?>{};
    for (final folder in homeFolders) {
      final folderAssets = valuedAssets
          .where((asset) => asset.item.folderId == folder.id)
          .toList();
      final valuation = valuations
          .where((item) => item.folderId == folder.id)
          .firstOrNull;
      final total = valuation?.currentValueUsd ?? 0;
      final chartValues = {
        for (final range in HomeChartRange.values)
          range: _rangeValues(valuation?.series ?? const [], range),
      };
      final monthValues = chartValues[HomeChartRange.oneMonth]!;
      portfolios[folder.id] = PortfolioSummary(
        folderId: folder.id,
        totalValueUsd: total,
        previous30dValueUsd: monthValues.length > 1 ? monthValues.first : 0,
        chartValuesByRange: chartValues,
      );

      folderAssets.sort((left, right) => right.price.compareTo(left.price));
      final cards = folderAssets.take(3).map(_highlight).toList();
      highlights[folder.id] = cards;
      primaryHighlights[folder.id] = cards.firstOrNull;
    }

    return HomeDashboard(
      folders: homeFolders,
      portfoliosByFolderId: portfolios,
      mostValuableByFolderId: primaryHighlights,
      mostValuableCardsByFolderId: highlights,
      trending: trending,
      currencyCode: preferences.currency,
      amountHidden: preferences.amountHidden,
    );
  }

  Future<_HomeAsset?> _loadAsset(PortfolioItemDto item) async {
    try {
      final values = await Future.wait<Object>([
        cardDataApi.getCard(item.cardRef),
        cardDataApi.getMarketPrices(item.cardRef),
      ]);
      final card = values[0] as CardDataCardDto;
      final prices = values[1] as List<CardDataMarketPriceDto>;
      final price = _matchingPrice(item, prices);
      if (price?.price == null) return null;
      return _HomeAsset(item: item, card: card, price: price!.price!);
    } catch (_) {
      return null;
    }
  }

  Future<List<TrendingCard>> _loadTrending() async {
    final cards = (await cardDataApi.trendingCards()).take(3);
    return cards
        .where(
          (card) => card.priceUsd != null && card.previous1dPriceUsd != null,
        )
        .map(
          (card) => TrendingCard(
            cardRef: card.cardRef,
            title: card.name,
            subtitle: card.setName,
            priceUsd: card.priceUsd!,
            previousPriceUsd: card.previous1dPriceUsd!,
            imageUrl: card.imageUrl,
          ),
        )
        .toList();
  }
}

CardDataMarketPriceDto? _matchingPrice(
  PortfolioItemDto item,
  List<CardDataMarketPriceDto> prices,
) {
  final grader = item.grader.trim().toLowerCase();
  final matchingGrader = prices.where(
    (price) => price.grader.trim().toLowerCase() == grader,
  );
  for (final price in matchingGrader) {
    final gradeMatches = item.grade == null || price.grade == item.grade;
    final conditionMatches =
        item.condition == null ||
        _normalizedCondition(price.condition) ==
            _normalizedCondition(item.condition);
    if (gradeMatches && conditionMatches) return price;
  }
  return matchingGrader.firstOrNull;
}

String _normalizedCondition(String? value) {
  return (value ?? '').trim().toLowerCase().replaceFirst(
    RegExp(r'\s*\([^)]*\)\s*$'),
    '',
  );
}

List<double> _rangeValues(
  List<PortfolioValuationPointDto> series,
  HomeChartRange range,
) {
  final pointCount = _rangeDays[range]! + 1;
  return series
      .skip((series.length - pointCount).clamp(0, series.length))
      .map((point) => point.valueUsd)
      .toList();
}

HomeCardHighlight _highlight(_HomeAsset asset) {
  return HomeCardHighlight(
    cardRef: asset.card.cardRef,
    title: asset.card.name,
    subtitle: '#${asset.card.cardNumber} • ${asset.card.setName}',
    priceUsd: asset.price,
    previousPriceUsd: 0,
    imageUrl: asset.card.imageUrl,
  );
}

class _HomeAsset {
  const _HomeAsset({
    required this.item,
    required this.card,
    required this.price,
  });

  final PortfolioItemDto item;
  final CardDataCardDto card;
  final double price;
}

const _rangeDays = {
  HomeChartRange.oneDay: 1,
  HomeChartRange.sevenDays: 7,
  HomeChartRange.fifteenDays: 15,
  HomeChartRange.oneMonth: 30,
  HomeChartRange.threeMonths: 90,
};
