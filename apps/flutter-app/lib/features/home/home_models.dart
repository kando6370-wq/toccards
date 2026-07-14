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
  });

  final String folderId;
  final double totalValueUsd;
  final double previous30dValueUsd;
  final Map<HomeChartRange, List<double>> chartValuesByRange;
}

class HomeCardHighlight {
  const HomeCardHighlight({
    required this.title,
    required this.subtitle,
    required this.priceUsd,
    required this.previousPriceUsd,
    this.imageAssetPath,
  });

  final String title;
  final String subtitle;
  final double priceUsd;
  final double previousPriceUsd;
  final String? imageAssetPath;
}

class TrendingCard {
  const TrendingCard({
    required this.title,
    required this.subtitle,
    required this.priceUsd,
    required this.previousPriceUsd,
    this.imageAssetPath,
  });

  final String title;
  final String subtitle;
  final double priceUsd;
  final double previousPriceUsd;
  final String? imageAssetPath;
}

class HomeDashboard {
  const HomeDashboard({
    required this.folders,
    required this.portfoliosByFolderId,
    required this.mostValuableByFolderId,
    required this.trending,
    this.mostValuableCardsByFolderId = const {},
  });

  final List<HomeFolder> folders;
  final Map<String, PortfolioSummary> portfoliosByFolderId;
  final Map<String, HomeCardHighlight?> mostValuableByFolderId;
  final Map<String, List<HomeCardHighlight>> mostValuableCardsByFolderId;
  final List<TrendingCard> trending;

  HomeFolder get defaultFolder {
    return folders.firstWhere((folder) => folder.isDefault);
  }
}
