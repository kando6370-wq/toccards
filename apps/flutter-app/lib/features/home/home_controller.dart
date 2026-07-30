import 'dart:async';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/shared/card_data/card_data_api_client.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'home_models.dart';
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
    this.trendingStatus = KandoLoadStatus.content,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.content;

  HomeState.unavailable({
    required HomeDashboard dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
    this.trendingStatus = KandoLoadStatus.failure,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.failure;

  HomeState.loading({
    required HomeDashboard dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
    this.trendingStatus = KandoLoadStatus.loading,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.loading;

  const HomeState._({
    required HomeDashboard? dashboard,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.chartRange,
    required this.loadStatus,
    required this.trendingStatus,
  }) : _dashboard = dashboard;

  final HomeDashboard? _dashboard;
  final String selectedFolderId;
  final AppCurrency currency;
  final bool amountHidden;
  final HomeChartRange chartRange;
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

  String get totalAmountText =>
      _formatPortfolioTotal(selectedPortfolio.totalValueUsd);

  String get changeAmountText {
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
    KandoLoadStatus? trendingStatus,
  }) {
    return HomeState._(
      dashboard: dashboard ?? _dashboard,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      currency: currency ?? this.currency,
      amountHidden: amountHidden ?? this.amountHidden,
      chartRange: chartRange ?? this.chartRange,
      loadStatus: loadStatus,
      trendingStatus: trendingStatus ?? this.trendingStatus,
    );
  }
}

class HomeController extends Notifier<HomeState> {
  Completer<HomeCoreLoadResult>? _coreLoadCompleter;
  var _loadGeneration = 0;
  var _trendingLoadGeneration = 0;
  var _isSelectingCurrency = false;
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

  bool get _isCoreLoadInFlight =>
      _coreLoadCompleter != null && !_coreLoadCompleter!.isCompleted;

  @override
  HomeState build() {
    ref.listen<AppCurrency>(selectedCurrencyProvider, (previous, next) {
      state = state.copyWith(currency: next);
    });
    ref.listen<String?>(selectedPortfolioFolderProvider, (previous, next) {
      if (next == null || state.isLoading || state.isUnavailable) return;
      if (state.dashboard.folders.any((folder) => folder.id == next)) {
        final portfolio = state.dashboard.portfoliosByFolderId[next]!;
        state = state.copyWith(
          selectedFolderId: next,
          chartRange: _bestChartRange(portfolio, preferred: state.chartRange),
        );
      }
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
    await coreLoadComplete;
    while (ref.mounted && state.trendingStatus == KandoLoadStatus.loading) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
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
        amountHidden: previousState?.amountHidden ?? false,
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
        amountHidden: previousState?.amountHidden ?? false,
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
        amountHidden: previousState?.amountHidden ?? false,
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
    unawaited(
      _resolveProgressiveDashboard(
        repository,
        generation,
        trendingGeneration,
        currency,
        previousState,
      ),
    );
    final dashboard = previousState?.dashboard ?? _emptyHomeDashboard;
    return HomeState.loading(
      dashboard: dashboard,
      selectedFolderId:
          previousState?.selectedFolderId ?? dashboard.defaultFolder.id,
      currency: currency,
      amountHidden: previousState?.amountHidden ?? false,
      chartRange: previousState?.chartRange ?? HomeChartRange.fifteenDays,
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
          amountHidden: previousState?.amountHidden ?? false,
          chartRange: previousState?.chartRange ?? HomeChartRange.fifteenDays,
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
        amountHidden: previousState?.amountHidden ?? false,
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
        previousState?.selectedFolderId ??
        ref.read(selectedPortfolioFolderProvider);
    final selectedFolderId =
        dashboard.folders.any((folder) => folder.id == previousFolderId)
        ? previousFolderId!
        : dashboard.defaultFolder.id;
    final portfolio = dashboard.portfoliosByFolderId[selectedFolderId]!;
    final amountHidden =
        previousState?.amountHidden ??
        ref.read(portfolioAmountHiddenProvider) ??
        dashboard.amountHidden;
    if (previousState == null &&
        ref.read(selectedPortfolioFolderProvider) == null) {
      Future<void>.microtask(() {
        if (ref.mounted) {
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

    final portfolio =
        state.dashboard.portfoliosByFolderId[folderId] ??
        state.selectedPortfolio;
    final previousFolderId = state.selectedFolderId;
    final previousRange = state.chartRange;
    state = state.copyWith(
      selectedFolderId: folderId,
      chartRange: _bestChartRange(portfolio, preferred: state.chartRange),
    );
    try {
      await _updatePreferences(lastSelectedFolderId: folderId);
      ref.read(selectedPortfolioFolderProvider.notifier).select(folderId);
      return true;
    } catch (_) {
      state = state.copyWith(
        selectedFolderId: previousFolderId,
        chartRange: previousRange,
      );
      return false;
    }
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
    state = state.copyWith(amountHidden: !previous);
    try {
      await _updatePreferences(amountHidden: !previous);
      ref.read(portfolioAmountHiddenProvider.notifier).select(!previous);
      return true;
    } catch (_) {
      state = state.copyWith(amountHidden: previous);
      return false;
    }
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
