import 'home_models.dart';

abstract interface class HomeRepository {
  HomeDashboard loadDashboard();
}

class MockHomeRepository implements HomeRepository {
  const MockHomeRepository();

  @override
  HomeDashboard loadDashboard() {
    return const HomeDashboard(
      folders: [
        HomeFolder(id: 'main', name: 'Main', isDefault: true),
        HomeFolder(id: 'sealed', name: 'Sealed', isDefault: false),
        HomeFolder(id: 'empty', name: 'Empty', isDefault: false),
      ],
      portfoliosByFolderId: {
        'main': PortfolioSummary(
          folderId: 'main',
          totalValueUsd: 12840,
          previous30dValueUsd: 12420,
          chartValuesByRange: {
            HomeChartRange.oneDay: [12520, 12680, 12840],
            HomeChartRange.sevenDays: [11980, 12140, 12460, 12840],
            HomeChartRange.oneMonth: [10800, 11320, 11940, 12420, 12840],
            HomeChartRange.threeMonths: [9400, 10200, 11100, 12100, 12840],
            HomeChartRange.sixMonths: [7600, 9100, 10500, 11800, 12840],
            HomeChartRange.max: [6400, 8200, 9800, 11100, 12840],
          },
        ),
        'sealed': PortfolioSummary(
          folderId: 'sealed',
          totalValueUsd: 8640,
          previous30dValueUsd: 8330,
          chartValuesByRange: {
            HomeChartRange.oneDay: [8500, 8580, 8640],
            HomeChartRange.sevenDays: [8100, 8240, 8460, 8640],
            HomeChartRange.oneMonth: [7200, 7600, 8040, 8320, 8640],
            HomeChartRange.threeMonths: [6100, 6800, 7400, 8100, 8640],
            HomeChartRange.sixMonths: [5200, 6100, 7000, 7900, 8640],
            HomeChartRange.max: [4200, 5600, 6900, 7800, 8640],
          },
        ),
        'empty': PortfolioSummary(
          folderId: 'empty',
          totalValueUsd: 0,
          previous30dValueUsd: 0,
          chartValuesByRange: {
            HomeChartRange.oneDay: [0],
            HomeChartRange.sevenDays: [0],
            HomeChartRange.oneMonth: [0],
            HomeChartRange.threeMonths: [0],
            HomeChartRange.sixMonths: [0],
            HomeChartRange.max: [0],
          },
        ),
      },
      mostValuableByFolderId: {
        'main': HomeCardHighlight(
          title: 'Charizard ex',
          subtitle: 'PSA 10 · Holofoil',
          priceUsd: 780,
          previousPriceUsd: 721.55,
        ),
        'sealed': HomeCardHighlight(
          title: 'Evolving Skies Booster Box',
          subtitle: 'Sealed · 36 Packs',
          priceUsd: 620,
          previousPriceUsd: 588.24,
        ),
        'empty': null,
      },
      trending: [
        TrendingCard(
          title: 'Umbreon VMAX',
          subtitle: 'Pokemon · Evolving Skies',
          priceUsd: 410,
          previousPriceUsd: 365.42,
        ),
        TrendingCard(
          title: 'Shohei Ohtani Chrome',
          subtitle: 'Baseball · 2024 Topps Chrome',
          priceUsd: 240,
          previousPriceUsd: 220.18,
        ),
        TrendingCard(
          title: 'One Piece Manga Luffy',
          subtitle: 'One Piece · Romance Dawn',
          priceUsd: 330,
          previousPriceUsd: 306.69,
        ),
      ],
    );
  }
}
