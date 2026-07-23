import 'dart:async';

import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_image/card_image_url.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';

import 'home_models.dart';

abstract interface class HomeRepository {
  FutureOr<HomeDashboard> loadDashboard();
}

abstract interface class ProgressiveHomeRepository implements HomeRepository {
  Future<HomeDashboard> loadCoreDashboard();
  Future<List<TrendingCard>> loadTrending();
}

class ApiHomeRepository implements ProgressiveHomeRepository {
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
    final trendingResult = loadTrending().then<(List<TrendingCard>, bool)>(
      (cards) => (cards, false),
      onError: (_) => (const <TrendingCard>[], true),
    );
    final dashboard = await loadCoreDashboard();
    final (trending, trendingUnavailable) = await trendingResult;
    return dashboard.copyWith(
      trending: trending,
      trendingUnavailable: trendingUnavailable,
    );
  }

  @override
  Future<HomeDashboard> loadCoreDashboard() async {
    final source = await Future.wait([
      portfolioApi.listFolders(session),
      portfolioApi.getValuationHistory(session),
      managementApi.getPreferences(session),
    ]);
    final folders = source[0] as List<PortfolioFolderDto>;
    final valuations = source[1] as List<PortfolioFolderValuationDto>;
    final preferences = source[2] as UserPreferenceDto;
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
      final valuation = valuations
          .where((item) => item.folderId == folder.id)
          .firstOrNull;
      final total = valuation?.currentValueUsd ?? 0;
      final chartSeries = {
        for (final range in HomeChartRange.values)
          range: _rangePoints(valuation?.series ?? const [], range),
      };
      final chartValues = {
        for (final entry in chartSeries.entries)
          entry.key: entry.value.map((point) => point.valueUsd).toList(),
      };
      final chartDates = {
        for (final entry in chartSeries.entries)
          entry.key: entry.value.map((point) => point.date).toList(),
      };
      final monthValues = chartValues[HomeChartRange.oneMonth]!;
      portfolios[folder.id] = PortfolioSummary(
        folderId: folder.id,
        totalValueUsd: total,
        previous30dValueUsd: monthValues.length > 1 ? monthValues.first : 0,
        chartValuesByRange: chartValues,
        chartDatesByRange: chartDates,
      );

      final cards = (valuation?.mostValuable ?? const [])
          .map(_highlight)
          .toList();
      highlights[folder.id] = cards;
      primaryHighlights[folder.id] = cards.firstOrNull;
    }

    return HomeDashboard(
      folders: homeFolders,
      portfoliosByFolderId: portfolios,
      mostValuableByFolderId: primaryHighlights,
      mostValuableCardsByFolderId: highlights,
      trending: const [],
      currencyCode: preferences.currency,
      amountHidden: preferences.amountHidden,
    );
  }

  @override
  Future<List<TrendingCard>> loadTrending() => loadTrendingCards(cardDataApi);
}

Future<List<TrendingCard>> loadTrendingCards(CardDataApi cardDataApi) async {
  final cards = await cardDataApi.trendingCards();
  return cards
      .where(
        (card) => card.priceUsd != null && card.priceChange1dPercent != null,
      )
      .take(3)
      .map(
        (card) => TrendingCard(
          cardRef: card.cardRef,
          title: card.name,
          subtitle: card.setName,
          priceUsd: card.priceUsd!,
          increaseRate: card.priceChange1dPercent!,
          imageUrl: cardImageUrl(card.cardRef, CardImageVariant.thumbnail),
        ),
      )
      .toList();
}

List<PortfolioValuationPointDto> _rangePoints(
  List<PortfolioValuationPointDto> series,
  HomeChartRange range,
) {
  final pointCount = _rangeDays[range]! + 1;
  return series
      .skip((series.length - pointCount).clamp(0, series.length))
      .toList();
}

HomeCardHighlight _highlight(PortfolioMostValuableDto item) {
  final subtitle = [
    if (item.cardNumber.isNotEmpty) '#${item.cardNumber}',
    if (item.finish != null) item.finish!,
    item.setName,
  ].join(' • ');
  return HomeCardHighlight(
    cardRef: item.cardRef,
    title: item.name,
    subtitle: subtitle,
    priceUsd: item.priceUsd,
    previousPriceUsd: item.previous30dPriceUsd,
    imageUrl: cardImageUrl(item.cardRef, CardImageVariant.thumbnail),
  );
}

const _rangeDays = {
  HomeChartRange.oneDay: 1,
  HomeChartRange.sevenDays: 7,
  HomeChartRange.fifteenDays: 15,
  HomeChartRange.oneMonth: 30,
  HomeChartRange.threeMonths: 90,
};
