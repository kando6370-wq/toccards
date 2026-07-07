enum HomeChartRange {
  oneDay('1D'),
  sevenDays('7D'),
  oneMonth('1M'),
  threeMonths('3M'),
  sixMonths('6M'),
  max('MAX');

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
    required this.change30dUsd,
    required this.change30dPercent,
    required this.chartValuesByRange,
  });

  final String folderId;
  final double totalValueUsd;
  final double change30dUsd;
  final double change30dPercent;
  final Map<HomeChartRange, List<double>> chartValuesByRange;
}

class HomeCardHighlight {
  const HomeCardHighlight({
    required this.title,
    required this.subtitle,
    required this.priceUsd,
    required this.change30dPercent,
  });

  final String title;
  final String subtitle;
  final double priceUsd;
  final double change30dPercent;
}

class TrendingCard {
  const TrendingCard({
    required this.title,
    required this.subtitle,
    required this.priceUsd,
    required this.changeTodayPercent,
  });

  final String title;
  final String subtitle;
  final double priceUsd;
  final double changeTodayPercent;
}

class HomeDashboard {
  const HomeDashboard({
    required this.folders,
    required this.portfoliosByFolderId,
    required this.mostValuableByFolderId,
    required this.trending,
  });

  final List<HomeFolder> folders;
  final Map<String, PortfolioSummary> portfoliosByFolderId;
  final Map<String, HomeCardHighlight?> mostValuableByFolderId;
  final List<TrendingCard> trending;

  HomeFolder get defaultFolder {
    return folders.firstWhere((folder) => folder.isDefault);
  }
}
