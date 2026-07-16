import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_repository.dart';

class MockHomeRepository implements HomeRepository {
  const MockHomeRepository();

  @override
  HomeDashboard loadDashboard() => mockHomeDashboard;
}

const mockHomeDashboard = HomeDashboard(
  folders: [
    HomeFolder(id: 'main', name: 'Main', isDefault: true),
    HomeFolder(id: 'sealed', name: 'Sealed', isDefault: false),
    HomeFolder(id: 'empty', name: 'Empty', isDefault: false),
  ],
  portfoliosByFolderId: {
    'main': PortfolioSummary(
      folderId: 'main',
      totalValueUsd: 12450.8,
      previous30dValueUsd: 12030.8,
      chartValuesByRange: {
        HomeChartRange.oneDay: [12150, 12300, 12450.8],
        HomeChartRange.sevenDays: [11980, 12140, 12300, 12450.8],
        HomeChartRange.fifteenDays: [
          11800,
          12350,
          12800,
          12450,
          12050,
          12300,
          13250,
          12700,
          11600,
          12450.8,
        ],
        HomeChartRange.oneMonth: [10800, 11320, 11940, 12220, 12450.8],
        HomeChartRange.threeMonths: [9400, 10200, 11100, 12100, 12450.8],
      },
      chartDatesByRange: {
        HomeChartRange.oneDay: ['2025-02-17', '2025-02-18', '2025-02-19'],
        HomeChartRange.sevenDays: [
          '2025-02-12',
          '2025-02-14',
          '2025-02-16',
          '2025-02-18',
        ],
        HomeChartRange.fifteenDays: [
          '2025-02-12',
          '2025-02-13',
          '2025-02-14',
          '2025-02-15',
          '2025-02-16',
          '2025-02-17',
          '2025-02-18',
          '2025-02-19',
          '2025-02-20',
          '2025-02-21',
        ],
        HomeChartRange.oneMonth: [
          '2025-01-20',
          '2025-01-27',
          '2025-02-03',
          '2025-02-10',
          '2025-02-18',
        ],
        HomeChartRange.threeMonths: [
          '2024-11-18',
          '2024-12-18',
          '2025-01-18',
          '2025-02-01',
          '2025-02-18',
        ],
      },
    ),
    'sealed': PortfolioSummary(
      folderId: 'sealed',
      totalValueUsd: 8640,
      previous30dValueUsd: 8330,
      chartValuesByRange: {
        HomeChartRange.oneDay: [8500, 8580, 8640],
        HomeChartRange.sevenDays: [8100, 8240, 8460, 8640],
        HomeChartRange.fifteenDays: [7900, 8120, 8330, 8520, 8640],
        HomeChartRange.oneMonth: [7200, 7600, 8040, 8320, 8640],
        HomeChartRange.threeMonths: [6100, 6800, 7400, 8100, 8640],
      },
      chartDatesByRange: {
        HomeChartRange.oneDay: ['2025-02-17', '2025-02-18', '2025-02-19'],
        HomeChartRange.sevenDays: [
          '2025-02-12',
          '2025-02-14',
          '2025-02-16',
          '2025-02-18',
        ],
        HomeChartRange.fifteenDays: [
          '2025-02-14',
          '2025-02-15',
          '2025-02-16',
          '2025-02-17',
          '2025-02-18',
        ],
        HomeChartRange.oneMonth: [
          '2025-01-20',
          '2025-01-27',
          '2025-02-03',
          '2025-02-10',
          '2025-02-18',
        ],
        HomeChartRange.threeMonths: [
          '2024-11-18',
          '2024-12-18',
          '2025-01-18',
          '2025-02-01',
          '2025-02-18',
        ],
      },
    ),
    'empty': PortfolioSummary(
      folderId: 'empty',
      totalValueUsd: 0,
      previous30dValueUsd: 0,
      chartValuesByRange: {
        HomeChartRange.oneDay: [0],
        HomeChartRange.sevenDays: [0],
        HomeChartRange.fifteenDays: [0],
        HomeChartRange.oneMonth: [0],
        HomeChartRange.threeMonths: [0],
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
  mostValuableCardsByFolderId: {
    'main': [
      HomeCardHighlight(
        title: 'Pikachu',
        subtitle: '#95 • Diamond & Pearl',
        priceUsd: 10000000.12,
        previousPriceUsd: 9690000.12,
        imageAssetPath: 'assets/home/mega_lucario_ex.png',
      ),
      HomeCardHighlight(
        title: 'Pikachu',
        subtitle: '#95 · Diamond & Pearl',
        priceUsd: 9999000.12,
        previousPriceUsd: 9690000.12,
        imageAssetPath: 'assets/home/mega_lucario_ex.png',
      ),
      HomeCardHighlight(
        title: 'Pikachu',
        subtitle: '#95 · Diamond & Pearl',
        priceUsd: 9998000.12,
        previousPriceUsd: 9690000.12,
        imageAssetPath: 'assets/home/mega_lucario_ex.png',
      ),
    ],
    'sealed': [
      HomeCardHighlight(
        title: 'Evolving Skies Booster Box',
        subtitle: 'Sealed • 36 Packs',
        priceUsd: 620,
        previousPriceUsd: 588.24,
        imageAssetPath: 'assets/home/mega_lucario_ex.png',
      ),
    ],
  },
  trending: [
    TrendingCard(
      title: 'Ragavan, Nimble Pilferer',
      subtitle: 'MTG · Modern Horizons 2',
      priceUsd: 10000000.12,
      previousPriceUsd: 10320000,
      imageAssetPath: 'assets/home/mega_lucario_ex.png',
    ),
    TrendingCard(
      title: 'Black Lotus',
      subtitle: 'MTG · Alpha',
      priceUsd: 10000000.12,
      previousPriceUsd: 9523828.69,
      imageAssetPath: 'assets/home/mega_lucario_ex.png',
    ),
    TrendingCard(
      title: 'Base Set Charizard',
      subtitle: 'Pokémon · Unlimited',
      priceUsd: 10000000.12,
      previousPriceUsd: 8896797.26,
      imageAssetPath: 'assets/home/mega_lucario_ex.png',
    ),
  ],
);
