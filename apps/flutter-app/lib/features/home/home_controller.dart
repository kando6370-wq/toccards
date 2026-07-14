import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/ui/load_state.dart';

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
    required HomeDashboard dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.content;

  HomeState.unavailable({
    required HomeDashboard dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.failure;

  const HomeState._({
    required HomeDashboard? dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
    required this.loadStatus,
  }) : _dashboard = dashboard;

  final HomeDashboard? _dashboard;
  final String selectedFolderId;
  final AppCurrency currency;
  final bool amountHidden;
  final HomeChartRange chartRange;
  final KandoLoadStatus loadStatus;

  HomeDashboard get dashboard {
    final dashboard = _dashboard;
    if (dashboard == null) {
      throw StateError('Home dashboard is unavailable.');
    }
    return dashboard;
  }

  bool get isUnavailable => loadStatus == KandoLoadStatus.failure;
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

  List<HomeCardHighlight> get mostValuableCards {
    final cards = dashboard.mostValuableCardsByFolderId[selectedFolder.id];
    if (cards != null) {
      return cards;
    }

    final card = mostValuable;
    return card == null ? const [] : [card];
  }

  List<double> get chartValues {
    final valuesByRange = selectedPortfolio.chartValuesByRange;
    final selectedValues = valuesByRange[chartRange];
    if (selectedValues != null) {
      return selectedValues;
    }

    final oneMonthValues = valuesByRange[HomeChartRange.oneMonth];
    if (oneMonthValues != null) {
      return oneMonthValues;
    }

    for (final range in HomeChartRange.values) {
      final values = valuesByRange[range];
      if (values != null) {
        return values;
      }
    }

    return const [];
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
    return HomeState._(
      dashboard: _dashboard,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      currency: currency ?? this.currency,
      amountHidden: amountHidden ?? this.amountHidden,
      chartRange: chartRange ?? this.chartRange,
      loadStatus: loadStatus,
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

    final repository = ref.watch(homeRepositoryProvider);
    return _loadDashboard(repository: repository);
  }

  void refresh() {
    state = _loadDashboard(currency: state.currency, previousState: state);
  }

  HomeState _loadDashboard({
    HomeRepository? repository,
    AppCurrency? currency,
    HomeState? previousState,
  }) {
    final AppCurrency selectedCurrency =
        currency ?? ref.read(selectedCurrencyProvider);
    try {
      final HomeRepository source =
          repository ?? ref.read(homeRepositoryProvider);
      final dashboard = source.loadDashboard();
      return HomeState(
        dashboard: dashboard,
        selectedFolderId: dashboard.defaultFolder.id,
        currency: selectedCurrency,
        amountHidden: false,
        chartRange: _bestChartRange(
          dashboard.portfoliosByFolderId[dashboard.defaultFolder.id]!,
        ),
      );
    } catch (_) {
      final dashboard =
          previousState?.dashboard ??
          const MockHomeRepository().loadDashboard();
      return HomeState.unavailable(
        dashboard: dashboard,
        selectedFolderId:
            previousState?.selectedFolderId ?? dashboard.defaultFolder.id,
        currency: selectedCurrency,
        amountHidden: previousState?.amountHidden ?? false,
        chartRange:
            previousState?.chartRange ??
            _bestChartRange(
              dashboard.portfoliosByFolderId[dashboard.defaultFolder.id]!,
            ),
      );
    }
  }

  void selectFolder(String folderId) {
    if (state.isUnavailable) {
      return;
    }

    final exists = state.dashboard.folders.any(
      (folder) => folder.id == folderId,
    );
    if (!exists) {
      return;
    }

    final portfolio =
        state.dashboard.portfoliosByFolderId[folderId] ??
        state.selectedPortfolio;
    state = state.copyWith(
      selectedFolderId: folderId,
      chartRange: _bestChartRange(portfolio, preferred: state.chartRange),
    );
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
    if (!state.selectedPortfolio.chartValuesByRange.containsKey(chartRange)) {
      return;
    }

    state = state.copyWith(chartRange: chartRange);
  }

  HomeChartRange _bestChartRange(
    PortfolioSummary portfolio, {
    HomeChartRange? preferred,
  }) {
    final valuesByRange = portfolio.chartValuesByRange;
    if (preferred != null && valuesByRange.containsKey(preferred)) {
      return preferred;
    }

    if (valuesByRange.containsKey(HomeChartRange.fifteenDays)) {
      return HomeChartRange.fifteenDays;
    }

    if (valuesByRange.containsKey(HomeChartRange.oneMonth)) {
      return HomeChartRange.oneMonth;
    }

    for (final range in HomeChartRange.values) {
      if (valuesByRange.containsKey(range)) {
        return range;
      }
    }

    return preferred ?? HomeChartRange.fifteenDays;
  }
}
