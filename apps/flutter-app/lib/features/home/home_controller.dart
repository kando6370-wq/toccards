import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';

import 'home_models.dart';
import 'home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  return const MockHomeRepository();
});

final homeControllerProvider = NotifierProvider<HomeController, HomeState>(
  HomeController.new,
);

class HomeState {
  const HomeState({
    required this.dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
  });

  final HomeDashboard dashboard;
  final String selectedFolderId;
  final AppCurrency currency;
  final bool amountHidden;
  final HomeChartRange chartRange;

  String get currencyCode => currency.code;

  HomeFolder get selectedFolder {
    return dashboard.folders.firstWhere(
      (folder) => folder.id == selectedFolderId,
      orElse: () => dashboard.defaultFolder,
    );
  }

  PortfolioSummary get selectedPortfolio {
    return dashboard.portfoliosByFolderId[selectedFolder.id] ??
        dashboard.portfoliosByFolderId[dashboard.defaultFolder.id]!;
  }

  HomeCardHighlight? get mostValuable {
    return dashboard.mostValuableByFolderId[selectedFolder.id];
  }

  List<double> get chartValues {
    return selectedPortfolio.chartValuesByRange[chartRange]!;
  }

  String get totalAmountText => _formatMoney(selectedPortfolio.totalValueUsd);

  String get changeAmountText {
    final change = MarketChange.fromPrices(
      current: selectedPortfolio.totalValueUsd,
      previous: selectedPortfolio.previous30dValueUsd,
    );
    final amountText = change.amount == null
        ? '--'
        : _formatMoney(change.amount!);
    return '$amountText in the last 30 days';
  }

  String get changePercentText {
    return MarketChange.fromPrices(
      current: selectedPortfolio.totalValueUsd,
      previous: selectedPortfolio.previous30dValueUsd,
    ).percentText;
  }

  String get mostValuablePriceText {
    if (amountHidden) {
      return hiddenMoneyText;
    }

    final card = mostValuable;
    if (card == null) {
      return '--';
    }
    return formatCardPrice(card.priceUsd);
  }

  String formatCardPrice(double valueUsd) => _formatMoney(valueUsd);

  HomeState copyWith({
    String? selectedFolderId,
    AppCurrency? currency,
    bool? amountHidden,
    HomeChartRange? chartRange,
  }) {
    return HomeState(
      dashboard: dashboard,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      currency: currency ?? this.currency,
      amountHidden: amountHidden ?? this.amountHidden,
      chartRange: chartRange ?? this.chartRange,
    );
  }

  String _formatMoney(double usdAmount) {
    return CurrencyFormatter(
      currency: currency,
    ).formatUsd(usdAmount, hidden: amountHidden);
  }
}

class HomeController extends Notifier<HomeState> {
  @override
  HomeState build() {
    ref.listen<AppCurrency>(selectedCurrencyProvider, (previous, next) {
      state = state.copyWith(currency: next);
    });

    final dashboard = ref.watch(homeRepositoryProvider).loadDashboard();
    return HomeState(
      dashboard: dashboard,
      selectedFolderId: dashboard.defaultFolder.id,
      currency: ref.read(selectedCurrencyProvider),
      amountHidden: false,
      chartRange: HomeChartRange.oneMonth,
    );
  }

  void selectFolder(String folderId) {
    final exists = state.dashboard.folders.any(
      (folder) => folder.id == folderId,
    );
    if (!exists) {
      return;
    }

    state = state.copyWith(selectedFolderId: folderId);
  }

  void selectCurrency(String currencyCode) {
    final currency = AppCurrency.fromCode(currencyCode);
    if (currency.code != currencyCode) {
      return;
    }

    ref.read(selectedCurrencyProvider.notifier).select(currency);
    state = state.copyWith(currency: currency);
  }

  void toggleAmountHidden() {
    state = state.copyWith(amountHidden: !state.amountHidden);
  }

  void selectChartRange(HomeChartRange chartRange) {
    state = state.copyWith(chartRange: chartRange);
  }
}
