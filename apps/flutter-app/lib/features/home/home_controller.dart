import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_models.dart';
import 'home_repository.dart';

const _hiddenAmountText = '••••••';

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
    required this.currencyCode,
    required this.amountHidden,
    required this.chartRange,
  });

  final HomeDashboard dashboard;
  final String selectedFolderId;
  final String currencyCode;
  final bool amountHidden;
  final HomeChartRange chartRange;

  HomeFolder get selectedFolder {
    return dashboard.folders.firstWhere(
      (folder) => folder.id == selectedFolderId,
      orElse: () => dashboard.defaultFolder,
    );
  }

  PortfolioSummary get selectedPortfolio {
    return dashboard.portfolios.firstWhere(
      (portfolio) => portfolio.folderId == selectedFolder.id,
      orElse: () => dashboard.portfolios.first,
    );
  }

  HomeCardHighlight? get mostValuable => selectedPortfolio.mostValuable;

  List<int> get chartValues {
    return selectedPortfolio.chartSeries[chartRange] ?? const [];
  }

  String get totalAmountText => _formatMoney(selectedPortfolio.totalValueUsd);

  String get changeAmountText {
    return '${_formatMoney(selectedPortfolio.changeValueUsd)} in the last 30 days';
  }

  String get changePercentText {
    final sign = selectedPortfolio.changePercent > 0 ? '+' : '';
    return '$sign${selectedPortfolio.changePercent.toStringAsFixed(1)}%';
  }

  String get mostValuablePriceText {
    final card = mostValuable;
    if (card == null) {
      return _formatMoney(0);
    }
    return formatCardPrice(card.priceUsd);
  }

  String formatCardPrice(int priceUsd) => _formatMoney(priceUsd);

  HomeState copyWith({
    String? selectedFolderId,
    String? currencyCode,
    bool? amountHidden,
    HomeChartRange? chartRange,
  }) {
    return HomeState(
      dashboard: dashboard,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      currencyCode: currencyCode ?? this.currencyCode,
      amountHidden: amountHidden ?? this.amountHidden,
      chartRange: chartRange ?? this.chartRange,
    );
  }

  String _formatMoney(int usdAmount) {
    if (amountHidden) {
      return _hiddenAmountText;
    }

    final converted = usdAmount * _currencyRate;
    return '$_currencySymbol${_formatInteger(converted)}';
  }

  int get _currencyRate {
    return switch (currencyCode) {
      'CNY' => 7,
      'JPY' => 156,
      _ => 1,
    };
  }

  String get _currencySymbol {
    return switch (currencyCode) {
      'CNY' || 'JPY' => '¥',
      _ => r'$',
    };
  }

  String _formatInteger(int value) {
    final source = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      final remaining = source.length - index;
      buffer.write(source[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

class HomeController extends Notifier<HomeState> {
  @override
  HomeState build() {
    final dashboard = ref.watch(homeRepositoryProvider).loadDashboard();
    return HomeState(
      dashboard: dashboard,
      selectedFolderId: dashboard.defaultFolder.id,
      currencyCode: 'USD',
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
    if (!const ['USD', 'CNY', 'JPY'].contains(currencyCode)) {
      return;
    }

    state = state.copyWith(currencyCode: currencyCode);
  }

  void toggleAmountHidden() {
    state = state.copyWith(amountHidden: !state.amountHidden);
  }

  void selectChartRange(HomeChartRange chartRange) {
    state = state.copyWith(chartRange: chartRange);
  }
}
