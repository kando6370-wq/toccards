import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';
import 'package:kando_app/features/auth/auth_storage.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/home/home_models.dart';
import 'package:kando_app/features/home/home_repository.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'support/mock_home_repository.dart';

void main() {
  test(
    'dashboard exposes spec-shaped folder, portfolio, highlight, and trend data',
    () {
      final container = _mockHomeContainer();
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
      expect(mainPortfolio.totalValueUsd, 12450.8);
      expect(mainPortfolio.previous30dValueUsd, 12030.8);
      expect(mainPortfolio.chartValuesByRange[HomeChartRange.fifteenDays], [
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
      ]);
      expect(mainHighlight.title, 'Charizard ex');
      expect(mainHighlight.subtitle, 'PSA 10 · Holofoil');
      expect(mainHighlight.priceUsd, 780);
      expect(mainHighlight.previousPriceUsd, 721.55);
      expect(dashboard.trending.first.title, 'Ragavan, Nimble Pilferer');
      expect(dashboard.trending.first.previousPriceUsd, 10320000);
      expect(state.totalAmountText, r'$12,450.80');
      expect(state.changeAmountText, r'$420.00 in the last 30 days');
      expect(state.changePercentText, '+3.49%');
      expect(
        state.selectedPortfolio.chartValuesByRange[HomeChartRange.fifteenDays],
        [
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
      );
    },
  );

  test(
    'initial repository failure exposes no fabricated assets and refresh restores dashboard',
    () {
      final repository = _FailingThenSuccessfulHomeRepository();
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final failed = container.read(homeControllerProvider);

      expect(failed.loadStatus, KandoLoadStatus.failure);
      expect(failed.isUnavailable, isTrue);
      expect(failed.totalAmountText, r'$0.00');
      expect(failed.dashboard.trending, isEmpty);
      expect(repository.calls, 1);

      container.read(homeControllerProvider.notifier).refresh();
      final restored = container.read(homeControllerProvider);

      expect(restored.loadStatus, KandoLoadStatus.content);
      expect(restored.isUnavailable, isFalse);
      expect(restored.totalAmountText, r'$12,450.80');
      expect(repository.calls, 2);
    },
  );

  test(
    'refresh failure preserves the selected dashboard shell instead of resetting it to Main',
    () async {
      final repository = _SuccessfulThenFailingHomeRepository();
      final container = _homeContainer(repository);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      final controller = container.read(homeControllerProvider.notifier);
      await controller.selectFolder('sealed');
      await controller.toggleAmountHidden();
      controller.selectChartRange(HomeChartRange.oneMonth);
      controller.refresh();

      final failed = container.read(homeControllerProvider);
      expect(failed.isUnavailable, isTrue);
      expect(failed.selectedFolder.id, 'sealed');
      expect(failed.amountHidden, isTrue);
      expect(failed.chartRange, HomeChartRange.oneMonth);
      expect(failed.totalAmountText, hiddenMoneyText);
      expect(repository.calls, 2);
    },
  );

  test(
    'switching folder changes portfolio-scoped data while market trending stays stable',
    () async {
      final container = _mockHomeContainer();
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      final initial = container.read(homeControllerProvider);
      final initialTrendingTitles = initial.dashboard.trending
          .map((card) => card.title)
          .toList();

      await container
          .read(homeControllerProvider.notifier)
          .selectFolder('sealed');
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
    () async {
      final container = _mockHomeContainer();
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      final controller = container.read(homeControllerProvider.notifier);
      expect(
        container.read(homeControllerProvider).totalAmountText,
        r'$12,450.80',
      );
      expect(
        container.read(homeControllerProvider).changePercentText,
        '+3.49%',
      );

      expect(await controller.selectCurrency('EUR'), isTrue);
      final state = container.read(homeControllerProvider);

      expect(state.totalAmountText, '€11,330.23');
      expect(state.changeAmountText, '€382.20 in the last 30 days');
      expect(state.changePercentText, '+3.49%');
    },
  );

  test(
    'restores a saved non-USD currency only after loading its rate',
    () async {
      final container = _homeContainer(const _EurPreferenceHomeRepository());
      addTearDown(container.dispose);

      expect(container.read(homeControllerProvider).currencyCode, 'USD');
      await Future<void>.delayed(Duration.zero);

      final restored = container.read(homeControllerProvider);
      expect(restored.currencyCode, 'EUR');
      expect(restored.totalAmountText, '€11,330.23');
    },
  );

  test(
    'negative change amount keeps minus before the currency symbol',
    () async {
      final container = _homeContainer(const _NegativeChangeHomeRepository());
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      expect(
        container.read(homeControllerProvider).changeAmountText,
        r'-$420.00 in the last 30 days',
      );
      expect(
        container.read(homeControllerProvider).changePercentText,
        '-3.17%',
      );

      expect(
        await container
            .read(homeControllerProvider.notifier)
            .selectCurrency('EUR'),
        isTrue,
      );
      expect(
        container.read(homeControllerProvider).changeAmountText,
        '-€382.20 in the last 30 days',
      );
    },
  );

  test(
    'rate failure keeps the previous currency because conversion is unproven',
    () async {
      final container = _homeContainer(
        const MockHomeRepository(),
        currencyRateApi: const _TestCurrencyRateApi(fails: true),
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      final changed = await container
          .read(homeControllerProvider.notifier)
          .selectCurrency('EUR');

      expect(changed, isFalse);
      expect(container.read(homeControllerProvider).currencyCode, 'USD');
      expect(
        container.read(homeControllerProvider).totalAmountText,
        r'$12,450.80',
      );
    },
  );

  test(
    'invalid folder and currency selections leave state unchanged',
    () async {
      final container = _mockHomeContainer();
      addTearDown(container.dispose);

      final controller = container.read(homeControllerProvider.notifier);
      final initial = container.read(homeControllerProvider);

      controller.selectFolder('missing');
      expect(await controller.selectCurrency('CNY'), isFalse);
      final state = container.read(homeControllerProvider);

      expect(state.selectedFolder.id, initial.selectedFolder.id);
      expect(state.totalAmountText, initial.totalAmountText);
      expect(state.currencyCode, initial.currencyCode);
    },
  );

  test(
    'hidden amount masks asset money without losing selected folder state',
    () async {
      final container = _mockHomeContainer();
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      final controller = container.read(homeControllerProvider.notifier);
      await controller.selectFolder('sealed');
      await controller.toggleAmountHidden();
      final state = container.read(homeControllerProvider);

      expect(state.selectedFolder.id, 'sealed');
      expect(state.totalAmountText, hiddenMoneyText);
      expect(state.changeAmountText, '$hiddenMoneyText in the last 30 days');
      expect(state.mostValuablePriceText, hiddenMoneyText);
    },
  );

  test(
    'empty folder most valuable price uses placeholder unless amounts are hidden',
    () async {
      final container = _mockHomeContainer();
      addTearDown(container.dispose);
      await container.read(authControllerProvider.notifier).startupComplete;

      final controller = container.read(homeControllerProvider.notifier);
      await controller.selectFolder('empty');
      expect(
        container.read(homeControllerProvider).mostValuablePriceText,
        '--',
      );

      await controller.toggleAmountHidden();
      expect(
        container.read(homeControllerProvider).mostValuablePriceText,
        hiddenMoneyText,
      );
    },
  );

  test('zero previous portfolio value falls back for percent change', () async {
    final container = _mockHomeContainer();
    addTearDown(container.dispose);
    await container.read(authControllerProvider.notifier).startupComplete;

    final controller = container.read(homeControllerProvider.notifier);
    await controller.selectFolder('empty');

    expect(
      container.read(homeControllerProvider).changeAmountText,
      '-- in the last 30 days',
    );
    expect(container.read(homeControllerProvider).changePercentText, '-/-');
  });

  test(
    'dashboard selects an available chart range when a source omits the Figma default 15D series',
    () {
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(
            const _NegativeChangeHomeRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final state = container.read(homeControllerProvider);

      expect(state.chartRange, HomeChartRange.oneMonth);
      expect(state.chartValues, [12840]);
    },
  );

  test('chart range switches the selected mock series', () {
    final container = _mockHomeContainer();
    addTearDown(container.dispose);

    final controller = container.read(homeControllerProvider.notifier);
    expect(
      container.read(homeControllerProvider).chartRange,
      HomeChartRange.fifteenDays,
    );

    controller.selectChartRange(HomeChartRange.oneMonth);

    var state = container.read(homeControllerProvider);
    expect(state.chartRange, HomeChartRange.oneMonth);
    expect(state.chartValues, [10800, 11320, 11940, 12220, 12450.8]);

    controller.selectChartRange(HomeChartRange.fifteenDays);

    state = container.read(homeControllerProvider);
    expect(state.chartRange, HomeChartRange.fifteenDays);
    expect(state.chartValues, [
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
    ]);
  });
}

ProviderContainer _mockHomeContainer() {
  return _homeContainer(const MockHomeRepository());
}

ProviderContainer _homeContainer(
  HomeRepository repository, {
  CurrencyRateApi currencyRateApi = const _TestCurrencyRateApi(),
}) {
  final storage = InMemoryAuthStorage();
  return ProviderContainer(
    overrides: [
      authStorageProvider.overrideWithValue(storage),
      authRepositoryProvider.overrideWithValue(
        LocalPlaceholderAuthRepository(storage),
      ),
      authDeviceIdProvider.overrideWithValue('home-controller-test-device'),
      homeRepositoryProvider.overrideWithValue(repository),
      currencyRateApiProvider.overrideWithValue(currencyRateApi),
      portfolioManagementApiProvider.overrideWithValue(
        const _TestPortfolioManagementApi(),
      ),
    ],
  );
}

class _TestCurrencyRateApi implements CurrencyRateApi {
  const _TestCurrencyRateApi({this.fails = false});

  final bool fails;

  @override
  Future<double> loadUsdRate(String targetCurrency) async {
    if (fails) throw const CurrencyRateApiException();
    return 0.91;
  }
}

class _TestPortfolioManagementApi implements PortfolioManagementApi {
  const _TestPortfolioManagementApi();

  @override
  Future<UserPreferenceDto> updatePreferences(
    AuthSession session, {
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    return UserPreferenceDto(
      currency: currency ?? 'USD',
      amountHidden: amountHidden ?? false,
      lastSelectedFolderId: lastSelectedFolderId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _EurPreferenceHomeRepository implements HomeRepository {
  const _EurPreferenceHomeRepository();

  @override
  HomeDashboard loadDashboard() {
    final dashboard = const MockHomeRepository().loadDashboard();
    return HomeDashboard(
      folders: dashboard.folders,
      portfoliosByFolderId: dashboard.portfoliosByFolderId,
      mostValuableByFolderId: dashboard.mostValuableByFolderId,
      mostValuableCardsByFolderId: dashboard.mostValuableCardsByFolderId,
      trending: dashboard.trending,
      currencyCode: 'EUR',
      amountHidden: dashboard.amountHidden,
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

class _SuccessfulThenFailingHomeRepository implements HomeRepository {
  var calls = 0;

  @override
  HomeDashboard loadDashboard() {
    calls += 1;
    if (calls == 1) {
      return const MockHomeRepository().loadDashboard();
    }
    throw StateError('mock home unavailable');
  }
}
