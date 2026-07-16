enum HomeChartRange {
  oneDay('1d'),
  sevenDays('7d'),
  fifteenDays('15d'),
  oneMonth('1m'),
  threeMonths('3m');

  const HomeChartRange(this.label);

  final String label;
}

class HomeFolder {
  const HomeFolder({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;
}

class PortfolioSummary {
  const PortfolioSummary({
    required this.folderId,
    required this.totalValueUsd,
    required this.previous30dValueUsd,
    required this.chartValuesByRange,
    this.chartDatesByRange = const {},
  });

  final String folderId;
  final double totalValueUsd;
  final double previous30dValueUsd;
  final Map<HomeChartRange, List<double>> chartValuesByRange;
  final Map<HomeChartRange, List<String>> chartDatesByRange;
}

class HomeCardHighlight {
  const HomeCardHighlight({
    this.cardRef,
    required this.title,
    required this.subtitle,
    required this.priceUsd,
    required this.previousPriceUsd,
    this.imageAssetPath,
    this.imageUrl,
  });

  final String? cardRef;
  final String title;
  final String subtitle;
  final double priceUsd;
  final double? previousPriceUsd;
  final String? imageAssetPath;
  final String? imageUrl;
}

class TrendingCard {
  const TrendingCard({
    this.cardRef,
    required this.title,
    required this.subtitle,
    required this.priceUsd,
    required this.previousPriceUsd,
    this.imageAssetPath,
    this.imageUrl,
  });

  final String? cardRef;
  final String title;
  final String subtitle;
  final double priceUsd;
  final double previousPriceUsd;
  final String? imageAssetPath;
  final String? imageUrl;
}

class HomeDashboard {
  const HomeDashboard({
    required this.folders,
    required this.portfoliosByFolderId,
    required this.mostValuableByFolderId,
    required this.trending,
    this.mostValuableCardsByFolderId = const {},
    this.currencyCode = 'USD',
    this.amountHidden = false,
    this.trendingUnavailable = false,
  });

  final List<HomeFolder> folders;
  final Map<String, PortfolioSummary> portfoliosByFolderId;
  final Map<String, HomeCardHighlight?> mostValuableByFolderId;
  final Map<String, List<HomeCardHighlight>> mostValuableCardsByFolderId;
  final List<TrendingCard> trending;
  final String currencyCode;
  final bool amountHidden;
  final bool trendingUnavailable;

  HomeFolder get defaultFolder {
    return folders.firstWhere((folder) => folder.isDefault);
  }

  HomeDashboard copyWith({
    List<TrendingCard>? trending,
    bool? trendingUnavailable,
  }) {
    return HomeDashboard(
      folders: folders,
      portfoliosByFolderId: portfoliosByFolderId,
      mostValuableByFolderId: mostValuableByFolderId,
      mostValuableCardsByFolderId: mostValuableCardsByFolderId,
      trending: trending ?? this.trending,
      currencyCode: currencyCode,
      amountHidden: amountHidden,
      trendingUnavailable: trendingUnavailable ?? this.trendingUnavailable,
    );
  }
}
