import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';

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

      expect(dashboard.defaultFolder.id, 'main');
      expect(dashboard.defaultFolder.isDefault, isTrue);
      expect(mainPortfolio.totalValueUsd, 12840);
      expect(mainPortfolio.change30dUsd, 420);
      expect(mainPortfolio.change30dPercent, 3.4);
      expect(
        mainPortfolio.chartValuesByRange[HomeChartRange.max],
        [6400, 8200, 9800, 11100, 12840],
      );
      expect(mainHighlight.title, 'Charizard ex');
      expect(mainHighlight.subtitle, 'PSA 10 · Holofoil');
      expect(mainHighlight.priceUsd, 780);
      expect(mainHighlight.change30dPercent, 8.1);
      expect(dashboard.trending.first.title, 'Umbreon VMAX');
      expect(dashboard.trending.first.changeTodayPercent, 12.2);
      expect(state.selectedPortfolio.change30dUsd, 420);
      expect(state.selectedPortfolio.change30dPercent, 3.4);
      expect(
        state.selectedPortfolio.chartValuesByRange[HomeChartRange.max],
        [6400, 8200, 9800, 11100, 12840],
      );
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

  test('currency conversion changes money display but leaves percentage stable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    expect(container.read(homeControllerProvider).totalAmountText, r'$12,840');
    expect(container.read(homeControllerProvider).changePercentText, '+3.4%');

    controller.selectCurrency('CNY');
    final state = container.read(homeControllerProvider);

    expect(state.totalAmountText, '¥89,880');
    expect(state.changeAmountText, '¥2,940 in the last 30 days');
    expect(state.changePercentText, '+3.4%');
  });

  test('hidden amount masks asset money without losing selected folder state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    controller.selectFolder('sealed');
    controller.toggleAmountHidden();
    final state = container.read(homeControllerProvider);

    expect(state.selectedFolder.id, 'sealed');
    expect(state.totalAmountText, '••••••');
    expect(state.changeAmountText, '•••••• in the last 30 days');
    expect(state.mostValuablePriceText, '••••••');
  });

  test('empty folder most valuable price uses placeholder unless amounts are hidden', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    controller.selectFolder('empty');
    expect(container.read(homeControllerProvider).mostValuablePriceText, '--');

    controller.toggleAmountHidden();
    expect(
      container.read(homeControllerProvider).mostValuablePriceText,
      '••••••',
    );
  });

  test('chart range switches the selected mock series', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    expect(
      container.read(homeControllerProvider).chartRange,
      HomeChartRange.oneMonth,
    );

    controller.selectChartRange(HomeChartRange.max);

    final state = container.read(homeControllerProvider);
    expect(state.chartRange, HomeChartRange.max);
    expect(state.chartValues, [6400, 8200, 9800, 11100, 12840]);
  });
}
