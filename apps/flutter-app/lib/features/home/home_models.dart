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
  const HomeFolder({required this.id, required this.name});

  final String id;
  final String name;
}

class PortfolioSummary {
  const PortfolioSummary({
    required this.folderId,
    required this.totalValueUsd,
    required this.changeValueUsd,
    required this.changePercent,
    required this.chartSeries,
    this.mostValuable,
  });

  final String folderId;
  final int totalValueUsd;
  final int changeValueUsd;
  final double changePercent;
  final Map<HomeChartRange, List<int>> chartSeries;
  final HomeCardHighlight? mostValuable;
}

class HomeCardHighlight {
  const HomeCardHighlight({
    required this.title,
    required this.subtitle,
    required this.priceUsd,
  });

  final String title;
  final String subtitle;
  final int priceUsd;
}

class TrendingCard {
  const TrendingCard({
    required this.title,
    required this.subtitle,
    required this.priceUsd,
  });

  final String title;
  final String subtitle;
  final int priceUsd;
}

class HomeDashboard {
  const HomeDashboard({
    required this.folders,
    required this.portfolios,
    required this.trending,
  });

  final List<HomeFolder> folders;
  final List<PortfolioSummary> portfolios;
  final List<TrendingCard> trending;

  HomeFolder get defaultFolder => folders.first;
}
