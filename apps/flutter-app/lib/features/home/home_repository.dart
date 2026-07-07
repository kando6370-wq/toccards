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
        HomeFolder(id: 'main', name: 'Main'),
        HomeFolder(id: 'sealed', name: 'Sealed'),
        HomeFolder(id: 'empty', name: 'Empty'),
      ],
      portfolios: [
        PortfolioSummary(
          folderId: 'main',
          totalValueUsd: 12840,
          changeValueUsd: 420,
          changePercent: 3.4,
          chartSeries: {
            HomeChartRange.oneDay: [12520, 12680, 12840],
            HomeChartRange.sevenDays: [11980, 12140, 12460, 12840],
            HomeChartRange.oneMonth: [10800, 11320, 11940, 12420, 12840],
            HomeChartRange.threeMonths: [9400, 10200, 11100, 12100, 12840],
            HomeChartRange.sixMonths: [7600, 9100, 10500, 11800, 12840],
            HomeChartRange.max: [6400, 8200, 9800, 11100, 12840],
          },
          mostValuable: HomeCardHighlight(
            title: 'Umbreon VMAX',
            subtitle: 'PSA 10 · Holofoil',
            priceUsd: 3280,
          ),
        ),
        PortfolioSummary(
          folderId: 'sealed',
          totalValueUsd: 8640,
          changeValueUsd: 310,
          changePercent: 2.8,
          chartSeries: {
            HomeChartRange.oneDay: [8500, 8580, 8640],
            HomeChartRange.sevenDays: [8100, 8240, 8460, 8640],
            HomeChartRange.oneMonth: [7200, 7600, 8040, 8320, 8640],
            HomeChartRange.threeMonths: [6100, 6800, 7400, 8100, 8640],
            HomeChartRange.sixMonths: [5200, 6100, 7000, 7900, 8640],
            HomeChartRange.max: [4200, 5600, 6900, 7800, 8640],
          },
          mostValuable: HomeCardHighlight(
            title: 'Evolving Skies Booster Box',
            subtitle: 'Sealed · 36 Packs',
            priceUsd: 720,
          ),
        ),
        PortfolioSummary(
          folderId: 'empty',
          totalValueUsd: 0,
          changeValueUsd: 0,
          changePercent: 0,
          chartSeries: {
            HomeChartRange.oneDay: [0],
            HomeChartRange.sevenDays: [0],
            HomeChartRange.oneMonth: [0],
            HomeChartRange.threeMonths: [0],
            HomeChartRange.sixMonths: [0],
            HomeChartRange.max: [0],
          },
        ),
      ],
      trending: [
        TrendingCard(
          title: 'Umbreon VMAX',
          subtitle: 'PSA 10 · Holofoil',
          priceUsd: 3280,
        ),
        TrendingCard(
          title: 'Shohei Ohtani Chrome',
          subtitle: 'Topps · Refractor',
          priceUsd: 1180,
        ),
        TrendingCard(
          title: 'One Piece Manga Luffy',
          subtitle: 'Pokemon · Evolving Skies',
          priceUsd: 2140,
        ),
      ],
    );
  }
}
