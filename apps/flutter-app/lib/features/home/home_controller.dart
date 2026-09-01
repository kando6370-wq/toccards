import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'home_models.dart';
import 'home_entitlement_repair.dart';
import 'home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository?>((ref) {
  final authState = ref.watch(authControllerProvider);
  if (authState.isLoading) return null;
  final session = authState.session;
  if (session == null) return const _MissingHomeSessionRepository();
  return ApiHomeRepository(
    session: session,
    portfolioApi: ref.watch(portfolioApiClientProvider),
    managementApi: ref.watch(portfolioManagementApiProvider),
    cardDataApi: ref.watch(cardDataApiClientProvider),
  );
});

final homeControllerProvider = NotifierProvider<HomeController, HomeState>(
  HomeController.new,
);

enum HomeCoreLoadResult { content, failure }

final homeAutomaticRetryDelaysProvider = Provider<List<Duration>>((ref) {
  return const [Duration(seconds: 1), Duration(seconds: 3)];
});

class HomeState {
  const HomeState({
    required HomeDashboard dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
    this.isChartRangeLoading = false,
    this.trendingStatus = KandoLoadStatus.content,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.content;

  HomeState.unavailable({
    required HomeDashboard dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
    this.isChartRangeLoading = false,
    this.trendingStatus = KandoLoadStatus.failure,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.failure;

  HomeState.loading({
    required HomeDashboard dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
    this.isChartRangeLoading = false,
    this.trendingStatus = KandoLoadStatus.loading,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.loading;

  const HomeState._({
    required HomeDashboard? dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
    required this.isChartRangeLoading,
    required this.loadStatus,
    required this.trendingStatus,
  }) : _dashboard = dashboard;

  final HomeDashboard? _dashboard;
  final String selectedFolderId;
  final AppCurrency currency;
  final bool amountHidden;
  final HomeChartRange chartRange;
  final bool isChartRangeLoading;
  final KandoLoadStatus loadStatus;
  final KandoLoadStatus trendingStatus;

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

  bool get hasCollectionItems => selectedPortfolio.itemCount > 0;

  bool get isMarketPriceMissing =>
      hasCollectionItems &&
      selectedPortfolio.marketPriceStatus == MarketPriceStatus.missing;

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

  List<String> get chartDates {
    final datesByRange = selectedPortfolio.chartDatesByRange;
    final selectedDates = datesByRange[chartRange];
    if (selectedDates != null) {
      return selectedDates;
    }

    final oneMonthDates = datesByRange[HomeChartRange.oneMonth];
    if (oneMonthDates != null) {
      return oneMonthDates;
    }

    for (final range in HomeChartRange.values) {
      final dates = datesByRange[range];
      if (dates != null) {
        return dates;
      }
    }

    return const [];
  }

  String get totalAmountText => isMarketPriceMissing
      ? '--'
      : _formatPortfolioTotal(selectedPortfolio.totalValueUsd);

  String get changeAmountText {
    if (isMarketPriceMissing) return '-- in the last 30 days';
    final change = MarketChange.fromPrices(
      current: selectedPortfolio.totalValueUsd,
      previous: selectedPortfolio.previous30dValueUsd,
    );
    final amountText = change.amount == null
        ? '--'
        : formatCardPrice(change.amount!);
    return '$amountText in the last 30 days';
  }

  String get changePercentText {
    if (isMarketPriceMissing) return '-/-';
    return MarketChange.fromPrices(
      current: selectedPortfolio.totalValueUsd,
      previous: selectedPortfolio.previous30dValueUsd,
    ).percentText;
  }

  String get mostValuablePriceText {
    final card = mostValuable;
    if (card == null) {
      return '--';
    }
    return formatCardPrice(card.priceUsd);
  }

  String formatCardPrice(double valueUsd) {
    return CurrencyFormatter(currency: currency).formatUsd(valueUsd);
  }

  String _formatPortfolioTotal(double valueUsd) {
    return CurrencyFormatter(
      currency: currency,
    ).formatUsd(valueUsd, hidden: amountHidden);
  }

  HomeState copyWith({
    HomeDashboard? dashboard,
    String? selectedFolderId,
    AppCurrency? currency,
    bool? amountHidden,
    HomeChartRange? chartRange,
    bool? isChartRangeLoading,
    KandoLoadStatus? trendingStatus,
  }) {
    return HomeState._(
      dashboard: dashboard ?? _dashboard,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      currency: currency ?? this.currency,
      amountHidden: amountHidden ?? this.amountHidden,
      chartRange: chartRange ?? this.chartRange,
      isChartRangeLoading: isChartRangeLoading ?? this.isChartRangeLoading,
      loadStatus: loadStatus,
      trendingStatus: trendingStatus ?? this.trendingStatus,
    );
  }
}

List<PortfolioValuationPointDto> _homeRangePoints(
  List<PortfolioValuationPointDto> series,
  HomeChartRange range,
) {
  const days = {
    HomeChartRange.oneDay: 1,
    HomeChartRange.sevenDays: 7,
    HomeChartRange.fifteenDays: 15,
    HomeChartRange.oneMonth: 30,
    HomeChartRange.threeMonths: 90,
    HomeChartRange.oneYear: 365,
  };
  final pointCount = days[range]! + 1;
  return series
      .skip((series.length - pointCount).clamp(0, series.length))
      .toList();
}

class HomeController extends Notifier<HomeState> {
  Completer<HomeCoreLoadResult>? _coreLoadCompleter;
  Completer<void>? _trendingLoadCompleter;
  var _loadGeneration = 0;
  var _trendingLoadGeneration = 0;
  var _isSelectingCurrency = false;
  var _chartRangeGeneration = 0;
  Future<bool>? _oneYearLoad;
  String? _oneYearLoadFolderId;
  String? _restoringCurrencyCode;

  Future<HomeCoreLoadResult> get coreLoadComplete {
    final completer = _coreLoadCompleter;
    if (completer != null) return completer.future;
    return Future<HomeCoreLoadResult>.value(
      state.isUnavailable
          ? HomeCoreLoadResult.failure
          : HomeCoreLoadResult.content,
    );
  }

  Future<void> get trendingLoadComplete {
    return _trendingLoadCompleter?.future ?? Future<void>.value();
  }

  bool get _isCoreLoadInFlight =>
      _coreLoadCompleter != null && !_coreLoadCompleter!.isCompleted;

  @override
  HomeState build() {
    ref.listen<AppCurrency>(selectedCurrencyProvider, (previous, next) {
      state = state.copyWith(currency: next);
    });
    ref.listen<String?>(selectedPortfolioFolderProvider, (previous, next) {
      if (next == null || state.isLoading || state.isUnavailable) return;
      if (next == state.selectedFolderId) return;
      unawaited(refresh());
    });
    ref.listen<bool?>(portfolioAmountHiddenProvider, (previous, next) {
      if (next != null && !state.isLoading && !state.isUnavailable) {
        state = state.copyWith(amountHidden: next);
      }
    });

    final repository = ref.watch(homeRepositoryProvider);
    return _loadDashboard(repository: repository);
  }

  Future<void> refresh() async {
    state = _loadDashboard(currency: state.currency, previousState: state);
    final coreLoad = coreLoadComplete;
    final trendingLoad = _trendingLoadCompleter?.future ?? Future<void>.value();
    await coreLoad;
    await trendingLoad;
  }

  Future<void> refreshSilently() async {
    if (_isCoreLoadInFlight) {
      await coreLoadComplete;
      return;
    }
    final previousState = state;
    final nextState = _loadDashboard(
      currency: state.currency,
      previousState: previousState,
    );
    if (!nextState.isLoading) state = nextState;
    await coreLoadComplete;
  }

  Future<bool> refreshTrending() async {
    final generation = ++_trendingLoadGeneration;
    state = state.copyWith(trendingStatus: KandoLoadStatus.loading);
    try {
      final trending = await loadTrendingCards(
        ref.read(cardDataApiClientProvider),
      );
      if (!ref.mounted || generation != _trendingLoadGeneration) return false;
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(
          trending: trending,
          trendingUnavailable: false,
        ),
        trendingStatus: KandoLoadStatus.content,
      );
      return true;
    } catch (_) {
      if (!ref.mounted || generation != _trendingLoadGeneration) return false;
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(trendingUnavailable: true),
        trendingStatus: KandoLoadStatus.failure,
      );
      return false;
    }
  }

  HomeState _loadDashboard({
    HomeRepository? repository,
    AppCurrency? currency,
    HomeState? previousState,
  }) {
    _beginCoreLoad();
    _completeTrendingLoad();
    final AppCurrency selectedCurrency =
        currency ?? ref.read(selectedCurrencyProvider);
    final HomeRepository? source =
        repository ?? ref.read(homeRepositoryProvider);
    if (source == null) {
      final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
      return HomeState.loading(
        dashboard: dashboard,
        selectedFolderId:
            previousState?.selectedFolderId ?? dashboard.defaultFolder.id,
        currency: selectedCurrency,
        amountHidden: _localAmountHidden(previousState),
        chartRange:
            previousState?.chartRange ??
            _bestChartRange(
              dashboard.portfoliosByFolderId[dashboard.defaultFolder.id]!,
            ),
      );
    }
    try {
      if (source is ProgressiveHomeRepository) {
        return _loadProgressiveDashboard(
          source,
          selectedCurrency,
          previousState,
        );
      }
      final result = source.loadDashboard();
      if (result is HomeDashboard) {
        final content = _contentState(
          result,
          selectedCurrency,
          previousState: previousState,
        );
        _completeCoreLoad(HomeCoreLoadResult.content);
        return content;
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
        amountHidden: _localAmountHidden(previousState),
        chartRange:
            previousState?.chartRange ??
            _bestChartRange(
              dashboard.portfoliosByFolderId[dashboard.defaultFolder.id]!,
            ),
      );
    } catch (error, stackTrace) {
      _logLoadFailure('core', error, stackTrace, willRetry: false);
      _completeCoreLoad(HomeCoreLoadResult.failure);
      final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
      return HomeState.unavailable(
        dashboard: dashboard,
        selectedFolderId:
            previousState?.selectedFolderId ?? dashboard.defaultFolder.id,
        currency: selectedCurrency,
        amountHidden: _localAmountHidden(previousState),
        chartRange:
            previousState?.chartRange ??
            _bestChartRange(
              dashboard.portfoliosByFolderId[dashboard.defaultFolder.id]!,
            ),
      );
    }
  }

  HomeState _loadProgressiveDashboard(
    ProgressiveHomeRepository repository,
    AppCurrency currency,
    HomeState? previousState,
  ) {
    final generation = ++_loadGeneration;
    final trendingGeneration = ++_trendingLoadGeneration;
    final trendingLoadCompleter = _beginTrendingLoad();
    unawaited(
      _resolveProgressiveDashboard(
        repository,
        generation,
        trendingGeneration,
        currency,
        previousState,
      ).whenComplete(() => _completeTrendingLoad(trendingLoadCompleter)),
    );
    final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
    return HomeState.loading(
      dashboard: dashboard,
      selectedFolderId:
          previousState?.selectedFolderId ?? dashboard.defaultFolder.id,
      currency: currency,
      amountHidden: _localAmountHidden(previousState),
      chartRange: previousState?.chartRange ?? HomeChartRange.oneMonth,
    );
  }

  Future<void> _resolveProgressiveDashboard(
    ProgressiveHomeRepository repository,
    int generation,
    int trendingGeneration,
    AppCurrency currency,
    HomeState? previousState,
  ) async {
    final retryDelays = ref.read(homeAutomaticRetryDelaysProvider);
    for (var attempt = 0; ; attempt += 1) {
      try {
        var dashboard = await repository.loadCoreDashboard();
        if (!ref.mounted || generation != _loadGeneration) return;
        if (previousState != null) {
          dashboard = dashboard.copyWith(
            trending: previousState.dashboard.trending,
          );
        }
        state = _contentState(
          dashboard,
          currency,
          previousState: previousState,
          trendingStatus: KandoLoadStatus.loading,
        );
        _completeCoreLoad(HomeCoreLoadResult.content);
        await _resolveTrending(repository, generation, trendingGeneration);
        return;
      } catch (error, stackTrace) {
        if (!ref.mounted || generation != _loadGeneration) return;
        final willRetry =
            _isTransientHomeError(error) && attempt < retryDelays.length;
        final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
        state = HomeState.unavailable(
          dashboard: dashboard,
          selectedFolderId:
              previousState?.selectedFolderId ?? dashboard.defaultFolder.id,
          currency: currency,
          amountHidden: _localAmountHidden(previousState),
          chartRange: previousState?.chartRange ?? HomeChartRange.oneMonth,
        );
        _logLoadFailure(
          'core',
          error,
          stackTrace,
          willRetry: willRetry,
          attempt: attempt + 1,
        );
        if (!willRetry) {
          _completeCoreLoad(HomeCoreLoadResult.failure);
          return;
        }
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  Future<void> _resolveTrending(
    ProgressiveHomeRepository repository,
    int generation,
    int trendingGeneration,
  ) async {
    final retryDelays = ref.read(homeAutomaticRetryDelaysProvider);
    for (var attempt = 0; ; attempt += 1) {
      try {
        final trending = await repository.loadTrending();
        if (!ref.mounted ||
            generation != _loadGeneration ||
            trendingGeneration != _trendingLoadGeneration) {
          return;
        }
        state = state.copyWith(
          dashboard: state.dashboard.copyWith(
            trending: trending,
            trendingUnavailable: false,
          ),
          trendingStatus: KandoLoadStatus.content,
        );
        return;
      } catch (error, stackTrace) {
        if (!ref.mounted ||
            generation != _loadGeneration ||
            trendingGeneration != _trendingLoadGeneration) {
          return;
        }
        final willRetry =
            _isTransientHomeError(error) && attempt < retryDelays.length;
        state = state.copyWith(
          dashboard: state.dashboard.copyWith(trendingUnavailable: true),
          trendingStatus: KandoLoadStatus.failure,
        );
        _logLoadFailure(
          'trending',
          error,
          stackTrace,
          willRetry: willRetry,
          attempt: attempt + 1,
        );
        if (!willRetry) return;
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  void _beginCoreLoad() {
    final previous = _coreLoadCompleter;
    if (previous != null && !previous.isCompleted) {
      previous.complete(HomeCoreLoadResult.failure);
    }
    _coreLoadCompleter = Completer<HomeCoreLoadResult>();
  }

  void _completeCoreLoad(HomeCoreLoadResult result) {
    final completer = _coreLoadCompleter;
    if (completer != null && !completer.isCompleted) completer.complete(result);
  }

  Completer<void> _beginTrendingLoad() {
    _completeTrendingLoad();
    return _trendingLoadCompleter = Completer<void>();
  }

  void _completeTrendingLoad([Completer<void>? load]) {
    final completer = load ?? _trendingLoadCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _logLoadFailure(
    String section,
    Object error,
    StackTrace stackTrace, {
    required bool willRetry,
    int attempt = 1,
  }) {
    developer.log(
      '$section load failed on attempt $attempt; retry=$willRetry',
      name: 'kando.home',
      error: error,
      stackTrace: stackTrace,
    );
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
      _completeCoreLoad(HomeCoreLoadResult.content);
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _loadGeneration) return;
      _logLoadFailure('core', error, stackTrace, willRetry: false);
      final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
      state = HomeState.unavailable(
        dashboard: dashboard,
        selectedFolderId:
            previousState?.selectedFolderId ?? dashboard.defaultFolder.id,
        currency: currency,
        amountHidden: _localAmountHidden(previousState),
        chartRange:
            previousState?.chartRange ??
            _bestChartRange(
              dashboard.portfoliosByFolderId[dashboard.defaultFolder.id]!,
            ),
      );
      _completeCoreLoad(HomeCoreLoadResult.failure);
    }
  }

  HomeState _contentState(
    HomeDashboard dashboard,
    AppCurrency currency, {
    HomeState? previousState,
    KandoLoadStatus trendingStatus = KandoLoadStatus.content,
  }) {
    final configuredCurrency = AppCurrency.fromCode(dashboard.currencyCode);
    final sharedCurrency = ref.read(selectedCurrencyProvider);
    final preferredCurrency =
        previousState?.currency ??
        (sharedCurrency.code == configuredCurrency.code &&
                sharedCurrency.usdRate != null
            ? sharedCurrency
            : AppCurrency.usd);
    if (previousState == null &&
        configuredCurrency.code != preferredCurrency.code) {
      unawaited(_restorePreferredCurrency(configuredCurrency));
    }
    final previousFolderId =
        ref.read(selectedPortfolioFolderProvider) ??
        previousState?.selectedFolderId;
    final selectedFolderId =
        dashboard.folders.any((folder) => folder.id == previousFolderId)
        ? previousFolderId!
        : dashboard.defaultFolder.id;
    final portfolio = dashboard.portfoliosByFolderId[selectedFolderId]!;
    final amountHidden = _localAmountHidden(previousState);
    if (previousState == null &&
        ref.read(selectedPortfolioFolderProvider) == null) {
      Future<void>.microtask(() {
        if (ref.mounted &&
            ref.read(selectedPortfolioFolderProvider) == null &&
            state.selectedFolderId == selectedFolderId) {
          ref
              .read(selectedPortfolioFolderProvider.notifier)
              .select(selectedFolderId);
        }
      });
    }
    if (previousState == null &&
        ref.read(portfolioAmountHiddenProvider) == null) {
      Future<void>.microtask(() {
        if (ref.mounted) {
          ref.read(portfolioAmountHiddenProvider.notifier).select(amountHidden);
        }
      });
    }
    return HomeState(
      dashboard: dashboard,
      selectedFolderId: selectedFolderId,
      currency: preferredCurrency,
      amountHidden: amountHidden,
      chartRange: _bestChartRange(
        portfolio,
        preferred: previousState?.chartRange,
      ),
      trendingStatus: trendingStatus,
    );
  }

  bool _localAmountHidden(HomeState? previousState) {
    return ref.read(portfolioAmountHiddenProvider) ??
        previousState?.amountHidden ??
        false;
  }

  Future<bool> selectFolder(String folderId) async {
    if (state.isUnavailable) {
      return false;
    }

    final exists = state.dashboard.folders.any(
      (folder) => folder.id == folderId,
    );
    if (!exists) {
      return false;
    }
    if (folderId == state.selectedFolderId) {
      return true;
    }

    final portfolio =
        state.dashboard.portfoliosByFolderId[folderId] ??
        state.selectedPortfolio;
    final previousFolderId = state.selectedFolderId;
    final previousRange = state.chartRange;
    _chartRangeGeneration++;
    state = state.copyWith(
      selectedFolderId: folderId,
      chartRange: _bestChartRange(portfolio, preferred: state.chartRange),
      isChartRangeLoading: false,
    );
    try {
      await _updatePreferences(lastSelectedFolderId: folderId);
      ref.read(selectedPortfolioFolderProvider.notifier).select(folderId);
      return true;
    } catch (_) {
      state = state.copyWith(
        selectedFolderId: previousFolderId,
        chartRange: previousRange,
        isChartRangeLoading: false,
      );
      return false;
    }
  }

  void updateFolderName(String folderId, String name) {
    if (state.isLoading || state.isUnavailable) return;
    final folders = state.dashboard.folders;
    if (!folders.any((folder) => folder.id == folderId)) return;

    state = state.copyWith(
      dashboard: state.dashboard.copyWith(
        folders: [
          for (final folder in folders)
            if (folder.id == folderId)
              HomeFolder(id: folder.id, name: name, isDefault: folder.isDefault)
            else
              folder,
        ],
      ),
    );
  }

  Future<bool> selectCurrency(String currencyCode) async {
    if (_isSelectingCurrency) return false;
    final metadata = AppCurrency.fromCode(currencyCode);
    if (metadata.code != currencyCode) {
      return false;
    }
    final previous = state.currency;
    _isSelectingCurrency = true;
    try {
      final rate = metadata.code == 'USD'
          ? 1.0
          : await ref.read(currencyRateApiProvider).loadUsdRate(metadata.code);
      final currency = metadata.withUsdRate(rate);
      ref.read(selectedCurrencyProvider.notifier).select(currency);
      await _updatePreferences(currency: currency.code);
      return true;
    } catch (_) {
      if (state.currency.code != previous.code) {
        ref.read(selectedCurrencyProvider.notifier).select(previous);
      }
      return false;
    } finally {
      _isSelectingCurrency = false;
    }
  }

  Future<void> preloadCurrencyRates() async {
    try {
      await ref.read(currencyRateApiProvider).loadUsdRate('EUR');
    } catch (_) {
      // Selection reports the error if rates are still unavailable on tap.
    }
  }

  Future<void> _restorePreferredCurrency(AppCurrency metadata) async {
    if (_restoringCurrencyCode == metadata.code) return;
    _restoringCurrencyCode = metadata.code;
    try {
      final rate = await ref
          .read(currencyRateApiProvider)
          .loadUsdRate(metadata.code);
      if (!ref.mounted ||
          ref.read(selectedCurrencyProvider).code != 'USD' ||
          state.isLoading ||
          state.isUnavailable) {
        return;
      }
      final currency = metadata.withUsdRate(rate);
      ref.read(selectedCurrencyProvider.notifier).select(currency);
      state = state.copyWith(currency: currency);
    } catch (_) {
      // Keep USD until the provider can prove a conversion rate.
    } finally {
      if (_restoringCurrencyCode == metadata.code) {
        _restoringCurrencyCode = null;
      }
    }
  }

  Future<bool> toggleAmountHidden() async {
    final previous = state.amountHidden;
    final next = !previous;
    state = state.copyWith(amountHidden: next);
    final saved = await ref
        .read(portfolioAmountHiddenProvider.notifier)
        .select(next);
    // Backend persistence is intentionally disabled while visibility is local.
    // try {
    //   await _updatePreferences(amountHidden: next);
    // } catch (_) {
    //   state = state.copyWith(amountHidden: previous);
    //   return false;
    // }
    if (!saved && state.amountHidden == next) {
      state = state.copyWith(amountHidden: previous);
    }
    return saved;
  }

  Future<void> _updatePreferences({
    String? currency,
    bool? amountHidden,
    String? lastSelectedFolderId,
  }) async {
    final session = ref.read(authControllerProvider).session;
    if (session == null) throw StateError('Home session is unavailable.');
    await ref
        .read(portfolioManagementApiProvider)
        .updatePreferences(
          session,
          currency: currency,
          amountHidden: amountHidden,
          lastSelectedFolderId: lastSelectedFolderId,
        );
  }

  Future<bool> selectChartRange(HomeChartRange chartRange) async {
    if (chartRange == HomeChartRange.oneYear &&
        !state.selectedPortfolio.chartValuesByRange.containsKey(chartRange)) {
      return _loadOneYearChart();
    }
    if (!state.selectedPortfolio.chartValuesByRange.containsKey(chartRange)) {
      return false;
    }

    if (state.isChartRangeLoading) _chartRangeGeneration++;
    state = state.copyWith(chartRange: chartRange, isChartRangeLoading: false);
    return true;
  }

  Future<bool> _loadOneYearChart() async {
    final session = ref.read(authControllerProvider).session;
    if (session == null || state.isLoading || state.isUnavailable) return false;
    final folderId = state.selectedFolderId;
    final inFlight = _oneYearLoad;
    if (inFlight != null &&
        _oneYearLoadFolderId == folderId &&
        state.chartRange == HomeChartRange.oneYear &&
        state.isChartRangeLoading) {
      return inFlight;
    }
    final request = _loadOneYearChartForFolder(
      session,
      folderId,
      state.chartRange,
    );
    _oneYearLoad = request;
    _oneYearLoadFolderId = folderId;
    try {
      return await request;
    } finally {
      if (identical(_oneYearLoad, request)) {
        _oneYearLoad = null;
        _oneYearLoadFolderId = null;
      }
    }
  }

  Future<bool> _loadOneYearChartForFolder(
    AuthSession session,
    String folderId,
    HomeChartRange previousRange,
  ) async {
    final generation = ++_chartRangeGeneration;
    state = state.copyWith(
      chartRange: HomeChartRange.oneYear,
      isChartRangeLoading: true,
    );
    try {
      final valuations = await _loadOneYearWithEntitlementRepair(
        session,
        folderId,
      );
      if (!ref.mounted ||
          generation != _chartRangeGeneration ||
          state.selectedFolderId != folderId) {
        return true;
      }
      final valuation = valuations
          .where((item) => item.folderId == folderId)
          .firstOrNull;
      if (valuation == null) {
        throw StateError('One year portfolio valuation is unavailable.');
      }
      final points = _homeRangePoints(valuation.series, HomeChartRange.oneYear);
      final portfolio = state.selectedPortfolio;
      final updated = portfolio.copyWith(
        chartValuesByRange: {
          ...portfolio.chartValuesByRange,
          HomeChartRange.oneYear: points
              .map((point) => point.valueUsd)
              .toList(),
        },
        chartDatesByRange: {
          ...portfolio.chartDatesByRange,
          HomeChartRange.oneYear: points.map((point) => point.date).toList(),
        },
      );
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(
          portfoliosByFolderId: {
            ...state.dashboard.portfoliosByFolderId,
            folderId: updated,
          },
        ),
        chartRange: HomeChartRange.oneYear,
        isChartRangeLoading: false,
      );
      return true;
    } catch (_) {
      if (!ref.mounted ||
          generation != _chartRangeGeneration ||
          state.selectedFolderId != folderId) {
        return true;
      }
      state = state.copyWith(
        chartRange: previousRange,
        isChartRangeLoading: false,
      );
      return false;
    }
  }

  Future<List<PortfolioFolderValuationDto>> _loadOneYearWithEntitlementRepair(
    AuthSession session,
    String folderId,
  ) async {
    Future<List<PortfolioFolderValuationDto>> request() => ref
        .read(portfolioApiClientProvider)
        .getValuationHistory(
          session,
          days: 365,
          folderId: folderId,
          localPremiumVerified: true,
        )
        .timeout(const Duration(seconds: 15));

    try {
      return await request();
    } catch (error) {
      if (!isEntitlementSyncRequired(error) ||
          !await ref.read(homeEntitlementRepairProvider)()) {
        rethrow;
      }
      return request();
    }
  }

  HomeChartRange _bestChartRange(
    PortfolioSummary portfolio, {
    HomeChartRange? preferred,
  }) {
    final valuesByRange = portfolio.chartValuesByRange;
    if (preferred != null && valuesByRange.containsKey(preferred)) {
      return preferred;
    }

    if (valuesByRange.containsKey(HomeChartRange.oneMonth)) {
      return HomeChartRange.oneMonth;
    }

    for (final range in HomeChartRange.values) {
      if (valuesByRange.containsKey(range)) {
        return range;
      }
    }

    return preferred ?? HomeChartRange.oneMonth;
  }
}

bool _isTransientHomeError(Object error) {
  if (error is TimeoutException) return true;
  if (error is PortfolioApiException) {
    return _isTransientStatusCode(error.statusCode);
  }
  if (error is CardDataApiException) {
    return _isTransientStatusCode(error.statusCode);
  }
  if (error is! DioException) return false;

  final statusCode = error.response?.statusCode;
  if (_isTransientStatusCode(statusCode)) return true;
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.transformTimeout ||
    DioExceptionType.connectionError => true,
    DioExceptionType.unknown => error.response == null,
    DioExceptionType.badResponse ||
    DioExceptionType.cancel ||
    DioExceptionType.badCertificate => false,
  };
}

bool _isTransientStatusCode(int? statusCode) {
  return statusCode == 408 ||
      statusCode == 429 ||
      (statusCode != null && statusCode >= 500);
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
      itemCount: 0,
      marketPriceStatus: MarketPriceStatus.missing,
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
