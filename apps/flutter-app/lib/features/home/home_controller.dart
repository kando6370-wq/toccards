import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'home_models.dart';
import 'home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  final session = ref.watch(authControllerProvider).session;
  if (session == null) return const _MissingHomeSessionRepository();
  return ApiHomeRepository(
    session: session,
    portfolioApi: ref.watch(portfolioApiClientProvider),
    cardDataApi: ref.watch(cardDataApiClientProvider),
  );
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

  HomeState.loading({
    required HomeDashboard dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.loading;

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
  bool get isLoading => loadStatus == KandoLoadStatus.loading;
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
  var _loadGeneration = 0;

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
      final result = source.loadDashboard();
      if (result is HomeDashboard) {
        return _contentState(
          result,
          selectedCurrency,
          previousState: previousState,
        );
      }
      final generation = ++_loadGeneration;
      unawaited(
        _resolveDashboard(result, generation, selectedCurrency, previousState),
      );
      final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
      return HomeState.loading(
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
    } catch (_) {
      final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
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

  Future<void> _resolveDashboard(
    Future<HomeDashboard> result,
    int generation,
    AppCurrency currency,
    HomeState? previousState,
  ) async {
    try {
      final dashboard = await result;
      if (!ref.mounted || generation != _loadGeneration) return;
      state = _contentState(dashboard, currency, previousState: previousState);
    } catch (_) {
      if (!ref.mounted || generation != _loadGeneration) return;
      final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
      state = HomeState.unavailable(
        dashboard: dashboard,
        selectedFolderId:
            previousState?.selectedFolderId ?? dashboard.defaultFolder.id,
        currency: currency,
        amountHidden: previousState?.amountHidden ?? false,
        chartRange:
            previousState?.chartRange ??
            _bestChartRange(
              dashboard.portfoliosByFolderId[dashboard.defaultFolder.id]!,
            ),
      );
    }
  }

  HomeState _contentState(
    HomeDashboard dashboard,
    AppCurrency currency, {
    HomeState? previousState,
  }) {
    final previousFolderId = previousState?.selectedFolderId;
    final selectedFolderId =
        dashboard.folders.any((folder) => folder.id == previousFolderId)
        ? previousFolderId!
        : dashboard.defaultFolder.id;
    final portfolio = dashboard.portfoliosByFolderId[selectedFolderId]!;
    return HomeState(
      dashboard: dashboard,
      selectedFolderId: selectedFolderId,
      currency: currency,
      amountHidden: previousState?.amountHidden ?? false,
      chartRange: _bestChartRange(
        portfolio,
        preferred: previousState?.chartRange,
      ),
    );
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

class _MissingHomeSessionRepository implements HomeRepository {
  const _MissingHomeSessionRepository();

  @override
  Future<HomeDashboard> loadDashboard() {
    return Future.error(StateError('Home requires an authenticated session.'));
  }
}

const _emptyHomeDashboard = HomeDashboard(
  folders: [HomeFolder(id: 'main', name: 'Main', isDefault: true)],
  portfoliosByFolderId: {
    'main': PortfolioSummary(
      folderId: 'main',
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
  mostValuableByFolderId: {'main': null},
  mostValuableCardsByFolderId: {'main': []},
  trending: [],
);
