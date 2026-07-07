import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';

void main() {
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
