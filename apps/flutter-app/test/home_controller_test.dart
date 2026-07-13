import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/ui/load_state.dart';

void main() {
  test(
    'dashboard exposes spec-shaped folder, portfolio, highlight, and trend data',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(homeControllerProvider);
      final dashboard = state.dashboard;
      final mainPortfolio = dashboard.portfoliosByFolderId['main']!;
      final mainHighlight = dashboard.mostValuableByFolderId['main']!;

      expect(HomeChartRange.values.map((range) => range.label), [
        '1d',
        '7d',
        '15d',
        '1m',
        '3m',
      ]);
      expect(dashboard.defaultFolder.id, 'main');
      expect(dashboard.defaultFolder.isDefault, isTrue);
      expect(mainPortfolio.totalValueUsd, 12840);
      expect(mainPortfolio.previous30dValueUsd, 12420);
      expect(mainPortfolio.chartValuesByRange[HomeChartRange.fifteenDays], [
        11600,
        12040,
        12420,
        12680,
        12840,
      ]);
      expect(mainHighlight.title, 'Charizard ex');
      expect(mainHighlight.subtitle, 'PSA 10 · Holofoil');
      expect(mainHighlight.priceUsd, 780);
      expect(mainHighlight.previousPriceUsd, 721.55);
      expect(dashboard.trending.first.title, 'Umbreon VMAX');
      expect(dashboard.trending.first.previousPriceUsd, 365.42);
      expect(state.totalAmountText, r'$12,840.00');
      expect(state.changeAmountText, r'$420.00 in the last 30 days');
      expect(state.changePercentText, '+3.38%');
      expect(
        state.selectedPortfolio.chartValuesByRange[HomeChartRange.fifteenDays],
        [11600, 12040, 12420, 12680, 12840],
      );
    },
  );

  test(
    'repository failure shows page failure and refresh restores dashboard',
    () {
      final repository = _FailingThenSuccessfulHomeRepository();
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final failed = container.read(homeControllerProvider);

      expect(failed.loadStatus, KandoLoadStatus.failure);
      expect(failed.isUnavailable, isTrue);
      expect(repository.calls, 1);

      container.read(homeControllerProvider.notifier).refresh();
      final restored = container.read(homeControllerProvider);

      expect(restored.loadStatus, KandoLoadStatus.content);
      expect(restored.isUnavailable, isFalse);
      expect(restored.totalAmountText, r'$12,840.00');
      expect(repository.calls, 2);
    },
  );

  test(
    'switching folder changes portfolio-scoped data while market trending stays stable',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initial = container.read(homeControllerProvider);
      final initialTrendingTitles = initial.dashboard.trending
          .map((card) => card.title)
          .toList();

      container.read(homeControllerProvider.notifier).selectFolder('sealed');
      final changed = container.read(homeControllerProvider);

      expect(changed.selectedFolder.name, 'Sealed');
      expect(changed.selectedPortfolio.totalValueUsd, 8640);
      expect(changed.mostValuable?.title, 'Evolving Skies Booster Box');
      expect(changed.mostValuable?.priceUsd, 620);
      expect(
        changed.dashboard.trending.map((card) => card.title).toList(),
        initialTrendingTitles,
      );
    },
  );

  test(
    'currency conversion changes money display but leaves percentage stable',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(homeControllerProvider.notifier);
      expect(
        container.read(homeControllerProvider).totalAmountText,
        r'$12,840.00',
      );
      expect(
        container.read(homeControllerProvider).changePercentText,
        '+3.38%',
      );

      controller.selectCurrency('EUR');
      final state = container.read(homeControllerProvider);

      expect(state.totalAmountText, '€11,684.40');
      expect(state.changeAmountText, '€382.20 in the last 30 days');
      expect(state.changePercentText, '+3.38%');
    },
  );

  test('negative change amount keeps minus before the currency symbol', () {
    final container = ProviderContainer(
      overrides: [
        homeRepositoryProvider.overrideWithValue(
          const _NegativeChangeHomeRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(homeControllerProvider).changeAmountText,
      r'-$420.00 in the last 30 days',
    );
    expect(container.read(homeControllerProvider).changePercentText, '-3.17%');

    container.read(homeControllerProvider.notifier).selectCurrency('EUR');
    expect(
      container.read(homeControllerProvider).changeAmountText,
      '-€382.20 in the last 30 days',
    );
  });

  test('invalid folder and currency selections leave state unchanged', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    final initial = container.read(homeControllerProvider);

    controller.selectFolder('missing');
    controller.selectCurrency('CNY');
    final state = container.read(homeControllerProvider);

    expect(state.selectedFolder.id, initial.selectedFolder.id);
    expect(state.totalAmountText, initial.totalAmountText);
    expect(state.currencyCode, initial.currencyCode);
  });

  test(
    'hidden amount masks asset money without losing selected folder state',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(homeControllerProvider.notifier);
      controller.selectFolder('sealed');
      controller.toggleAmountHidden();
      final state = container.read(homeControllerProvider);

      expect(state.selectedFolder.id, 'sealed');
      expect(state.totalAmountText, hiddenMoneyText);
      expect(state.changeAmountText, '$hiddenMoneyText in the last 30 days');
      expect(state.mostValuablePriceText, hiddenMoneyText);
    },
  );

  test(
    'empty folder most valuable price uses placeholder unless amounts are hidden',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(homeControllerProvider.notifier);
      controller.selectFolder('empty');
      expect(
        container.read(homeControllerProvider).mostValuablePriceText,
        '--',
      );

      controller.toggleAmountHidden();
      expect(
        container.read(homeControllerProvider).mostValuablePriceText,
        hiddenMoneyText,
      );
    },
  );

  test('zero previous portfolio value falls back for percent change', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    controller.selectFolder('empty');

    expect(
      container.read(homeControllerProvider).changeAmountText,
      '-- in the last 30 days',
    );
    expect(container.read(homeControllerProvider).changePercentText, '-/-');
  });

  test('chart range switches the selected mock series', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    expect(
      container.read(homeControllerProvider).chartRange,
      HomeChartRange.oneMonth,
    );

    controller.selectChartRange(HomeChartRange.fifteenDays);

    final state = container.read(homeControllerProvider);
    expect(state.chartRange, HomeChartRange.fifteenDays);
    expect(state.chartValues, [11600, 12040, 12420, 12680, 12840]);
  });
}

class _NegativeChangeHomeRepository implements HomeRepository {
  const _NegativeChangeHomeRepository();

  @override
  HomeDashboard loadDashboard() {
    return const HomeDashboard(
      folders: [HomeFolder(id: 'main', name: 'Main', isDefault: true)],
      portfoliosByFolderId: {
        'main': PortfolioSummary(
          folderId: 'main',
          totalValueUsd: 12840,
          previous30dValueUsd: 13260,
          chartValuesByRange: {
            HomeChartRange.oneMonth: [12840],
          },
        ),
      },
      mostValuableByFolderId: {'main': null},
      trending: [],
    );
  }
}

class _FailingThenSuccessfulHomeRepository implements HomeRepository {
  var calls = 0;

  @override
  HomeDashboard loadDashboard() {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock home unavailable');
    }
    return const MockHomeRepository().loadDashboard();
  }
}
