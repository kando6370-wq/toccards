import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/features/subscription/subscription_controller.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/platform/app_commercial_policy.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/portfolio/portfolio_api_client.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'collection_models.dart';
import 'collection_repository.dart';

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return HttpCollectionRepository(
    ref.watch(portfolioApiClientProvider),
    managementApi: ref.watch(portfolioManagementApiProvider),
    gameCatalogApi: ref.watch(setCatalogApiClientProvider),
  );
});

final collectionControllerProvider =
    NotifierProvider<CollectionController, CollectionState>(
      CollectionController.new,
    );

final collectionInitialSortProvider =
    NotifierProvider<CollectionInitialSortController, CollectionSort?>(
      CollectionInitialSortController.new,
    );

final collectionPerformanceOrderProvider =
    NotifierProvider<CollectionPerformanceOrderController, List<String>>(
      CollectionPerformanceOrderController.new,
    );

class CollectionInitialSortController extends Notifier<CollectionSort?> {
  @override
  CollectionSort? build() => null;

  void select(CollectionSort sort) {
    state = sort;
  }

  void clear() {
    state = null;
  }
}

class CollectionPerformanceOrderController extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void select(List<String> itemIds) {
    state = List.unmodifiable(itemIds);
  }

  void clear() {
    state = const [];
  }
}

class CollectionSummary {
  const CollectionSummary({
    required this.totalValueText,
    required this.cardCount,
    required this.gradedCount,
  });

  final String totalValueText;
  final int? cardCount;
  final int? gradedCount;
}

class CollectionViewItem {
  const CollectionViewItem({
    required this.source,
    required this.valueText,
    required this.changeText,
  });

  final CollectionItem source;
  final String valueText;
  final String changeText;

  String get name => source.name;
  String get setName => source.setName;
  String get number => source.number;
  String get game => source.game;
  String get language => source.language;
  String get finish => source.finish;
  String get statusText => source.statusText;
  int get quantity => source.quantity;
  String get cardRef => source.cardRef;
  String? get imageUrl => source.imageUrl;
}

class CollectionState {
  const CollectionState({
    required CollectionDashboard dashboard,
    required this.selectedTab,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.searchByTab,
    required this.sortByTab,
    required this.gamesByTab,
    required this.languagesByTab,
    this.performanceItemIds = const [],
    this.gameOptions = const [],
    this.isPaged = false,
    this.summary,
    this.summaryStatus = KandoLoadStatus.content,
    this.page = 1,
    this.total = 0,
    this.baseCount,
    this.pageSize = 40,
    this.isLoadingPage = false,
    this.isLoadingMore = false,
    this.hasPageFailure = false,
  }) : _dashboard = dashboard,
       loadStatus = KandoLoadStatus.content;

  const CollectionState.unavailable({required this.currency})
    : _dashboard = null,
      selectedTab = CollectionTab.portfolio,
      selectedFolderId = '',
      amountHidden = false,
      searchByTab = const {
        CollectionTab.portfolio: '',
        CollectionTab.wishlist: '',
      },
      sortByTab = const {
        CollectionTab.portfolio: CollectionSort.newest,
        CollectionTab.wishlist: CollectionSort.newest,
      },
      gamesByTab = const {
        CollectionTab.portfolio: <String>{},
        CollectionTab.wishlist: <String>{},
      },
      languagesByTab = const {
        CollectionTab.portfolio: <String>{},
        CollectionTab.wishlist: <String>{},
      },
      performanceItemIds = const [],
      gameOptions = const [],
      isPaged = false,
      summary = null,
      summaryStatus = KandoLoadStatus.failure,
      page = 1,
      total = 0,
      baseCount = null,
      pageSize = 40,
      isLoadingPage = false,
      isLoadingMore = false,
      hasPageFailure = false,
      loadStatus = KandoLoadStatus.failure;

  const CollectionState.loading({required this.currency})
    : _dashboard = null,
      selectedTab = CollectionTab.portfolio,
      selectedFolderId = '',
      amountHidden = false,
      searchByTab = const {
        CollectionTab.portfolio: '',
        CollectionTab.wishlist: '',
      },
      sortByTab = const {
        CollectionTab.portfolio: CollectionSort.newest,
        CollectionTab.wishlist: CollectionSort.newest,
      },
      gamesByTab = const {
        CollectionTab.portfolio: <String>{},
        CollectionTab.wishlist: <String>{},
      },
      languagesByTab = const {
        CollectionTab.portfolio: <String>{},
        CollectionTab.wishlist: <String>{},
      },
      performanceItemIds = const [],
      gameOptions = const [],
      isPaged = false,
      summary = null,
      summaryStatus = KandoLoadStatus.loading,
      page = 1,
      total = 0,
      baseCount = null,
      pageSize = 40,
      isLoadingPage = false,
      isLoadingMore = false,
      hasPageFailure = false,
      loadStatus = KandoLoadStatus.loading;

  const CollectionState._({
    required CollectionDashboard? dashboard,
    required this.selectedTab,
    required this.selectedFolderId,
    required this.currency,
    required this.amountHidden,
    required this.searchByTab,
    required this.sortByTab,
    required this.gamesByTab,
    required this.languagesByTab,
    required this.performanceItemIds,
    required this.gameOptions,
    required this.isPaged,
    required this.summary,
    required this.summaryStatus,
    required this.page,
    required this.total,
    required this.baseCount,
    required this.pageSize,
    required this.isLoadingPage,
    required this.isLoadingMore,
    required this.hasPageFailure,
    required this.loadStatus,
  }) : _dashboard = dashboard;

  final CollectionDashboard? _dashboard;
  final CollectionTab selectedTab;
  final String selectedFolderId;
  final AppCurrency currency;
  final bool amountHidden;
  final Map<CollectionTab, String> searchByTab;
  final Map<CollectionTab, CollectionSort> sortByTab;
  final Map<CollectionTab, Set<String>> gamesByTab;
  final Map<CollectionTab, Set<String>> languagesByTab;
  final List<String> performanceItemIds;
  final List<String> gameOptions;
  final bool isPaged;
  final CollectionSummaryResult? summary;
  final KandoLoadStatus summaryStatus;
  final int page;
  final int total;
  final int? baseCount;
  final int pageSize;
  final bool isLoadingPage;
  final bool isLoadingMore;
  final bool hasPageFailure;
  final KandoLoadStatus loadStatus;

  bool get hasMore => isPaged && page * pageSize < total;

  CollectionDashboard get dashboard {
    final dashboard = _dashboard;
    if (dashboard == null) {
      throw StateError('Collection dashboard is unavailable.');
    }
    return dashboard;
  }

  bool get isUnavailable => loadStatus == KandoLoadStatus.failure;
  bool get isLoading => loadStatus == KandoLoadStatus.loading;

  CollectionFolder get selectedFolder {
    return dashboard.folders.firstWhere(
      (folder) => folder.id == selectedFolderId,
      orElse: () => dashboard.defaultFolder,
    );
  }

  String get searchText => searchByTab[selectedTab] ?? '';

  CollectionSort get selectedSort {
    return sortByTab[selectedTab] ?? CollectionSort.newest;
  }

  Set<String> get selectedGames => gamesByTab[selectedTab] ?? const {};

  Set<String> get selectedLanguages => languagesByTab[selectedTab] ?? const {};

  List<CollectionItem> get _baseItems {
    if (selectedTab == CollectionTab.wishlist) {
      return dashboard.wishlistItems;
    }

    return dashboard.portfolioItems
        .where((item) => item.folderId == selectedFolder.id)
        .toList();
  }

  List<CollectionViewItem> get visibleItems {
    if (isPaged) {
      return [
        for (final item in _baseItems)
          CollectionViewItem(
            source: item,
            valueText: _formatMoney(item.marketValueUsd, item.quantity),
            changeText: _formatChange(item),
          ),
      ];
    }
    final query = searchText.trim().toLowerCase();
    final filtered = _baseItems.where((item) {
      final matchesSearch =
          query.isEmpty || item.searchableText.contains(query);
      final matchesGame =
          selectedGames.isEmpty || selectedGames.contains(item.game);
      final matchesLanguage =
          selectedLanguages.isEmpty ||
          selectedLanguages.contains(item.language);
      return matchesSearch && matchesGame && matchesLanguage;
    }).toList();

    final performanceRanks = {
      for (var index = 0; index < performanceItemIds.length; index++)
        performanceItemIds[index]: index,
    };
    filtered.sort((a, b) {
      return switch (selectedSort) {
        CollectionSort.newest => b.addedAtSort.compareTo(a.addedAtSort),
        CollectionSort.valueDesc => _nullableDoubleDesc(
          a.marketValueUsd,
          b.marketValueUsd,
        ),
        CollectionSort.valueAsc => _nullableDoubleAsc(
          a.marketValueUsd,
          b.marketValueUsd,
        ),
        CollectionSort.changeDesc => _nullableDoubleDesc(
          _changePercent(a),
          _changePercent(b),
        ),
        CollectionSort.nameAsc => a.name.compareTo(b.name),
        CollectionSort.performanceDesc => _performanceRankCompare(
          a,
          b,
          performanceRanks,
        ),
      };
    });

    return [
      for (final item in filtered)
        CollectionViewItem(
          source: item,
          valueText: _formatMoney(item.marketValueUsd, item.quantity),
          changeText: _formatChange(item),
        ),
    ];
  }

  CollectionSummary get portfolioSummary {
    if (isPaged) {
      final totals = summary?.folders[selectedFolder.id];
      return CollectionSummary(
        totalValueText: totals?.totalValueUsd == null
            ? '--'
            : _formatPortfolioTotal(totals!.totalValueUsd!),
        cardCount: totals?.cardCount,
        gradedCount: totals?.gradedCount,
      );
    }
    final items = dashboard.portfolioItems
        .where((item) => item.folderId == selectedFolder.id)
        .toList();
    final pricedItems = items
        .where((item) => item.marketValueUsd != null)
        .toList();
    final total = pricedItems.fold<double>(
      0,
      (sum, item) => sum + item.marketValueUsd! * item.quantity,
    );

    return CollectionSummary(
      totalValueText: items.isNotEmpty && pricedItems.isEmpty
          ? '--'
          : _formatPortfolioTotal(total),
      cardCount: items.fold<int>(0, (sum, item) => sum + item.quantity),
      gradedCount: items
          .where((item) => item.isGraded)
          .fold<int>(0, (sum, item) => sum + item.quantity),
    );
  }

  int? get _baseCount =>
      baseCount ??
      (selectedTab == CollectionTab.portfolio
          ? summary?.folders[selectedFolder.id]?.itemCount
          : summary?.wishlistCount);

  bool get isEmpty => isPaged ? _baseCount == 0 : _baseItems.isEmpty;

  bool get isNoMatch => isPaged
      ? _baseCount != null && _baseCount! > 0 && total == 0
      : _baseItems.isNotEmpty && visibleItems.isEmpty;

  List<String> get availableGames {
    return gameOptions;
  }

  List<String> get availableLanguages {
    if (isPaged) {
      return selectedTab == CollectionTab.portfolio
          ? summary?.folders[selectedFolder.id]?.languages ?? const []
          : summary?.wishlistLanguages ?? const [];
    }
    final values = _baseItems.map((item) => item.language).toSet().toList()
      ..sort();
    return values;
  }

  CollectionState copyWith({
    CollectionDashboard? dashboard,
    CollectionTab? selectedTab,
    String? selectedFolderId,
    AppCurrency? currency,
    bool? amountHidden,
    Map<CollectionTab, String>? searchByTab,
    Map<CollectionTab, CollectionSort>? sortByTab,
    Map<CollectionTab, Set<String>>? gamesByTab,
    Map<CollectionTab, Set<String>>? languagesByTab,
    List<String>? performanceItemIds,
    List<String>? gameOptions,
    bool? isPaged,
    CollectionSummaryResult? summary,
    KandoLoadStatus? summaryStatus,
    int? page,
    int? total,
    int? baseCount,
    int? pageSize,
    bool? isLoadingPage,
    bool? isLoadingMore,
    bool? hasPageFailure,
  }) {
    return CollectionState._(
      dashboard: dashboard ?? _dashboard,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      currency: currency ?? this.currency,
      amountHidden: amountHidden ?? this.amountHidden,
      searchByTab: searchByTab ?? this.searchByTab,
      sortByTab: sortByTab ?? this.sortByTab,
      gamesByTab: gamesByTab ?? this.gamesByTab,
      languagesByTab: languagesByTab ?? this.languagesByTab,
      performanceItemIds: performanceItemIds ?? this.performanceItemIds,
      gameOptions: gameOptions ?? this.gameOptions,
      isPaged: isPaged ?? this.isPaged,
      summary: summary ?? this.summary,
      summaryStatus: summaryStatus ?? this.summaryStatus,
      page: page ?? this.page,
      total: total ?? this.total,
      baseCount: baseCount ?? this.baseCount,
      pageSize: pageSize ?? this.pageSize,
      isLoadingPage: isLoadingPage ?? this.isLoadingPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasPageFailure: hasPageFailure ?? this.hasPageFailure,
      loadStatus: loadStatus,
    );
  }

  String _formatPortfolioTotal(double valueUsd) {
    return CurrencyFormatter(
      currency: currency,
    ).formatUsd(valueUsd, hidden: amountHidden);
  }

  int _performanceRankCompare(
    CollectionItem left,
    CollectionItem right,
    Map<String, int> ranks,
  ) {
    final leftRank = ranks[left.id];
    final rightRank = ranks[right.id];
    if (leftRank != null && rightRank != null) {
      return leftRank.compareTo(rightRank);
    }
    if (leftRank != null) return -1;
    if (rightRank != null) return 1;
    return right.addedAtSort.compareTo(left.addedAtSort);
  }

  String _formatMoney(double? valueUsd, int quantity) {
    if (valueUsd == null) {
      return '--';
    }
    return CurrencyFormatter(
      currency: currency,
    ).formatUsd(valueUsd, quantity: quantity);
  }

  String _formatChange(CollectionItem item) {
    return MarketChange.fromPercent(item.increasePercent).percentText;
  }

  double? _changePercent(CollectionItem item) {
    return MarketChange.fromPercent(item.increasePercent).percent;
  }

  static int _nullableDoubleDesc(double? left, double? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return right.compareTo(left);
  }

  static int _nullableDoubleAsc(double? left, double? right) {
    if (left == null && right == null) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  }
}

class CollectionController extends Notifier<CollectionState> {
  Completer<void>? _loadCompleter;
  Timer? _searchDebounce;
  var _loadGeneration = 0;
  var _pageGeneration = 0;

  Future<void> loadNextPage() async {
    if (!state.isPaged ||
        state.isLoading ||
        _loadCompleter?.isCompleted == false ||
        state.isLoadingPage ||
        state.isLoadingMore ||
        state.hasPageFailure ||
        !state.hasMore) {
      return;
    }
    final repository = ref.read(collectionRepositoryProvider);
    final session = ref.read(authControllerProvider).session;
    if (repository is! CollectionPagedRepository || session == null) return;
    final pagedRepository = repository as CollectionPagedRepository;
    final loadGeneration = _loadGeneration;
    final pageGeneration = ++_pageGeneration;
    final nextPage = state.page + 1;
    state = state.copyWith(isLoadingMore: true);
    try {
      final result = await pagedRepository.loadPage(
        session,
        tab: state.selectedTab,
        folderId: state.selectedTab == CollectionTab.portfolio
            ? state.selectedFolderId
            : null,
        query: state.searchText.trim(),
        sort: state.selectedSort,
        page: nextPage,
        games: state.selectedGames,
        languages: state.selectedLanguages,
        performanceItemIds: state.performanceItemIds,
      );
      if (!ref.mounted ||
          loadGeneration != _loadGeneration ||
          pageGeneration != _pageGeneration) {
        return;
      }
      final dashboard = state.dashboard;
      state = state.copyWith(
        dashboard: dashboard.copyWith(
          portfolioItems: state.selectedTab == CollectionTab.portfolio
              ? [
                  ...dashboard.portfolioItems,
                  ...result.dashboard.portfolioItems,
                ]
              : dashboard.portfolioItems,
          wishlistItems: state.selectedTab == CollectionTab.wishlist
              ? [...dashboard.wishlistItems, ...result.dashboard.wishlistItems]
              : dashboard.wishlistItems,
        ),
        page: result.page,
        total: result.total,
        baseCount: result.baseCount,
        pageSize: result.pageSize,
        isLoadingMore: false,
      );
    } catch (_) {
      if (ref.mounted &&
          loadGeneration == _loadGeneration &&
          pageGeneration == _pageGeneration) {
        state = state.copyWith(isLoadingMore: false, hasPageFailure: true);
      }
    }
  }

  Future<void> retryNextPage() {
    if (!state.hasPageFailure) return Future<void>.value();
    if (state.page == 0) {
      _scheduleFirstPage();
      return Future<void>.value();
    }
    state = state.copyWith(hasPageFailure: false);
    return loadNextPage();
  }

  Future<void> get loadComplete {
    return _loadCompleter?.future ?? Future<void>.value();
  }

  @override
  CollectionState build() {
    ref.onDispose(() => _searchDebounce?.cancel());
    ref.listen<AppCurrency>(selectedCurrencyProvider, (previous, next) {
      state = state.copyWith(currency: next);
    });
    ref.listen<String?>(selectedPortfolioFolderProvider, (previous, next) {
      if (next == null || state.isLoading || state.isUnavailable) return;
      if (state.dashboard.folders.any((folder) => folder.id == next)) {
        if (state.selectedFolderId == next) return;
        state = state.copyWith(selectedFolderId: next);
        _scheduleFirstPage();
      }
    });
    ref.listen<bool?>(portfolioAmountHiddenProvider, (previous, next) {
      if (next != null && !state.isLoading && !state.isUnavailable) {
        state = state.copyWith(amountHidden: next);
      }
    });

    final currency = ref.read(selectedCurrencyProvider);
    final authState = ref.watch(authControllerProvider);
    final session = authState.session;
    if (authState.isLoading || session == null) {
      return CollectionState.loading(currency: currency);
    }

    _startLoad(session: session, currency: currency);
    return CollectionState.loading(currency: currency);
  }

  Future<void> refresh() {
    final session = ref.read(authControllerProvider).session;
    if (session == null) {
      state = CollectionState.loading(currency: state.currency);
      return Future<void>.value();
    }

    state = CollectionState.loading(currency: state.currency);
    _startLoad(session: session, currency: state.currency);
    return loadComplete;
  }

  Future<void> refreshPreservingContent() {
    if (state.isLoading || state.isUnavailable) return refresh();
    final session = ref.read(authControllerProvider).session;
    if (session == null) return refresh();

    final previousState = state;
    _startLoad(
      session: session,
      currency: state.currency,
      preserveState: previousState,
    );
    return loadComplete;
  }

  void _startLoad({
    required AuthSession session,
    required AppCurrency currency,
    CollectionState? preserveState,
  }) {
    _searchDebounce?.cancel();
    final completer = Completer<void>();
    final generation = ++_loadGeneration;
    final pageGeneration = ++_pageGeneration;
    _loadCompleter = completer;
    final repository = ref.read(collectionRepositoryProvider);
    if (repository is CollectionPagedRepository &&
        (repository as CollectionPagedRepository).supportsPaging) {
      unawaited(
        Future<void>.microtask(
          () => _loadPagedDashboard(
            repository as CollectionPagedRepository,
            session,
            currency,
            generation,
            pageGeneration,
            completer,
            preserveState,
          ),
        ),
      );
      return;
    }
    unawaited(
      _loadDashboard(session, currency, generation, completer, preserveState),
    );
  }

  void _scheduleFirstPage({bool debounce = false}) {
    if (!state.isPaged) return;
    _searchDebounce?.cancel();
    final generation = ++_pageGeneration;
    state = state.copyWith(
      isLoadingPage: true,
      isLoadingMore: false,
      hasPageFailure: false,
    );
    if (debounce) {
      _searchDebounce = Timer(const Duration(milliseconds: 300), () {
        unawaited(_loadFirstPage(generation));
      });
    } else {
      unawaited(_loadFirstPage(generation));
    }
  }

  Future<void> _loadFirstPage(int generation) async {
    final repository = ref.read(collectionRepositoryProvider);
    final session = ref.read(authControllerProvider).session;
    if (repository is! CollectionPagedRepository || session == null) return;
    final pagedRepository = repository as CollectionPagedRepository;
    final loadGeneration = _loadGeneration;
    final tab = state.selectedTab;
    final folderId = state.selectedFolderId;
    final query = state.searchText.trim();
    final sort = state.selectedSort;
    final games = state.selectedGames;
    final languages = state.selectedLanguages;
    final performanceItemIds = state.performanceItemIds;
    try {
      final result = await pagedRepository.loadPage(
        session,
        tab: tab,
        folderId: tab == CollectionTab.portfolio ? folderId : null,
        query: query,
        sort: sort,
        games: games,
        languages: languages,
        performanceItemIds: performanceItemIds,
      );
      if (!ref.mounted ||
          loadGeneration != _loadGeneration ||
          generation != _pageGeneration) {
        return;
      }
      state = state.copyWith(
        dashboard: result.dashboard,
        page: result.page,
        total: result.total,
        baseCount: result.baseCount,
        pageSize: result.pageSize,
        isLoadingPage: false,
        hasPageFailure: false,
      );
    } catch (_) {
      if (ref.mounted &&
          loadGeneration == _loadGeneration &&
          generation == _pageGeneration) {
        state = state.copyWith(
          dashboard: state.dashboard.copyWith(
            portfolioItems: const [],
            wishlistItems: const [],
          ),
          page: 0,
          total: 0,
          isLoadingPage: false,
          hasPageFailure: true,
        );
      }
    }
  }

  Future<void> _loadPagedDashboard(
    CollectionPagedRepository repository,
    AuthSession session,
    AppCurrency currency,
    int generation,
    int pageGeneration,
    Completer<void> completer,
    CollectionState? preserveState,
  ) async {
    try {
      final previous = preserveState ?? state;
      final tab = previous.selectedTab;
      final sharedFolderId = ref.read(selectedPortfolioFolderProvider);
      final requestedFolderId =
          sharedFolderId ??
          (previous.selectedFolderId.isEmpty
              ? null
              : previous.selectedFolderId);
      final initialSort = preserveState == null
          ? ref.read(collectionInitialSortProvider) ?? CollectionSort.newest
          : previous.selectedSort;
      final initialPerformanceOrder = preserveState == null
          ? ref.read(collectionPerformanceOrderProvider)
          : previous.performanceItemIds;
      final summaryFuture = repository
          .loadSummary(session)
          .then<CollectionSummaryResult?>(
            (value) => value,
            onError: (Object _, StackTrace __) => null,
          );
      final gameOptionsFuture = _loadGameOptions(
        ref.read(collectionRepositoryProvider),
      );
      final result = await repository.loadPage(
        session,
        tab: tab,
        folderId: tab == CollectionTab.portfolio ? requestedFolderId : null,
        query: previous.searchByTab[tab] ?? '',
        sort: preserveState == null
            ? initialSort
            : previous.sortByTab[tab] ?? initialSort,
        games: previous.gamesByTab[tab] ?? const {},
        languages: previous.languagesByTab[tab] ?? const {},
        performanceItemIds: initialPerformanceOrder,
      );
      if (!ref.mounted ||
          generation != _loadGeneration ||
          pageGeneration != _pageGeneration) {
        return;
      }
      final currencyMetadata = AppCurrency.fromCode(
        result.dashboard.currencyCode,
      );
      var preferredCurrency = ref.read(selectedCurrencyProvider);
      if (preferredCurrency.code != currencyMetadata.code ||
          preferredCurrency.usdRate == null) {
        preferredCurrency = currencyMetadata;
      }
      final selectedFolderId =
          result.folderId ??
          requestedFolderId ??
          result.dashboard.defaultFolder.id;
      final amountHidden = ref.read(portfolioAmountHiddenProvider) ?? false;
      ref.read(selectedCurrencyProvider.notifier).select(preferredCurrency);
      state = CollectionState(
        dashboard: result.dashboard,
        selectedTab: tab,
        selectedFolderId: selectedFolderId,
        currency: preferredCurrency,
        amountHidden: amountHidden,
        searchByTab: previous.searchByTab,
        sortByTab:
            preserveState?.sortByTab ??
            {
              CollectionTab.portfolio: initialSort,
              CollectionTab.wishlist: CollectionSort.newest,
            },
        gamesByTab: previous.gamesByTab,
        languagesByTab: previous.languagesByTab,
        performanceItemIds: initialPerformanceOrder,
        gameOptions: previous.gameOptions,
        isPaged: true,
        summary: null,
        summaryStatus: KandoLoadStatus.loading,
        page: result.page,
        total: result.total,
        baseCount: result.baseCount,
        pageSize: result.pageSize,
      );
      if (preserveState == null) {
        ref.read(collectionInitialSortProvider.notifier).clear();
        ref.read(collectionPerformanceOrderProvider.notifier).clear();
      }
      if (sharedFolderId == null) {
        ref
            .read(selectedPortfolioFolderProvider.notifier)
            .select(selectedFolderId);
      }
      if (ref.read(portfolioAmountHiddenProvider) == null) {
        ref.read(portfolioAmountHiddenProvider.notifier).select(amountHidden);
      }
      final currentCurrency = preferredCurrency;
      if (currentCurrency.usdRate == null) {
        unawaited(() async {
          try {
            final rate = await ref
                .read(currencyRateApiProvider)
                .loadUsdRate(currentCurrency.code);
            if (ref.mounted &&
                generation == _loadGeneration &&
                ref.read(selectedCurrencyProvider).code ==
                    currentCurrency.code) {
              final resolved = currentCurrency.withUsdRate(rate);
              ref.read(selectedCurrencyProvider.notifier).select(resolved);
              state = state.copyWith(currency: resolved);
            }
          } catch (_) {
            // Keep prices unavailable until a conversion rate is known.
          }
        }());
      }
      unawaited(
        summaryFuture.then((summary) {
          if (!ref.mounted || generation != _loadGeneration) return;
          state = state.copyWith(
            summary: summary,
            summaryStatus: summary == null
                ? KandoLoadStatus.failure
                : KandoLoadStatus.content,
            gameOptions: state.gameOptions.isEmpty && summary != null
                ? summary.games
                : state.gameOptions,
          );
        }),
      );
      unawaited(
        gameOptionsFuture.then((games) {
          if (ref.mounted &&
              generation == _loadGeneration &&
              games.isNotEmpty) {
            state = state.copyWith(gameOptions: games);
          }
        }),
      );
    } catch (_) {
      if (ref.mounted && generation == _loadGeneration) {
        state = CollectionState.unavailable(currency: currency);
      }
    } finally {
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _loadDashboard(
    AuthSession session,
    AppCurrency currency,
    int generation,
    Completer<void> completer,
    CollectionState? preserveState,
  ) async {
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final dashboardFuture = repository.loadDashboard(session);
      final gameOptionsFuture = _loadGameOptions(repository);
      final dashboard = await dashboardFuture;
      final gameOptions = {
        ...dashboard.portfolioItems.map((item) => item.game),
        ...dashboard.wishlistItems.map((item) => item.game),
      }.toList()..sort();
      if (generation == _loadGeneration) {
        final currencyMetadata = AppCurrency.fromCode(dashboard.currencyCode);
        var preferredCurrency = ref.read(selectedCurrencyProvider);
        if (preferredCurrency.code != currencyMetadata.code ||
            preferredCurrency.usdRate == null) {
          preferredCurrency = currencyMetadata;
        }
        if (generation != _loadGeneration) return;
        final preservedState = preserveState ?? state;
        final sharedFolderId = ref.read(selectedPortfolioFolderProvider);
        final preservedFolderId = preservedState.selectedFolderId;
        final selectedFolderId =
            dashboard.folders.any((folder) => folder.id == preservedFolderId)
            ? preservedFolderId
            : dashboard.folders.any((folder) => folder.id == sharedFolderId)
            ? sharedFolderId!
            : dashboard.defaultFolder.id;
        final amountHidden = ref.read(portfolioAmountHiddenProvider) ?? false;
        final initialSort = preserveState == null
            ? ref.read(collectionInitialSortProvider) ?? CollectionSort.newest
            : null;
        final initialPerformanceOrder = preserveState == null
            ? ref.read(collectionPerformanceOrderProvider)
            : const <String>[];
        ref.read(selectedCurrencyProvider.notifier).select(preferredCurrency);
        state = CollectionState(
          dashboard: dashboard,
          selectedTab: preservedState.selectedTab,
          selectedFolderId: selectedFolderId,
          currency: preferredCurrency,
          amountHidden: amountHidden,
          searchByTab: preservedState.searchByTab,
          sortByTab:
              preserveState?.sortByTab ??
              {
                CollectionTab.portfolio: initialSort!,
                CollectionTab.wishlist: CollectionSort.newest,
              },
          gamesByTab: preservedState.gamesByTab,
          languagesByTab: preservedState.languagesByTab,
          performanceItemIds: preservedState.performanceItemIds.isEmpty
              ? initialPerformanceOrder
              : preservedState.performanceItemIds,
          gameOptions: gameOptions,
        );
        if (preserveState == null) {
          ref.read(collectionInitialSortProvider.notifier).clear();
          ref.read(collectionPerformanceOrderProvider.notifier).clear();
        }
        if (sharedFolderId == null) {
          ref
              .read(selectedPortfolioFolderProvider.notifier)
              .select(selectedFolderId);
        }
        if (ref.read(portfolioAmountHiddenProvider) == null) {
          ref.read(portfolioAmountHiddenProvider.notifier).select(amountHidden);
        }
        if (preferredCurrency.usdRate == null) {
          try {
            final rate = await ref
                .read(currencyRateApiProvider)
                .loadUsdRate(preferredCurrency.code);
            if (generation == _loadGeneration &&
                ref.read(selectedCurrencyProvider).code ==
                    preferredCurrency.code) {
              preferredCurrency = preferredCurrency.withUsdRate(rate);
              ref
                  .read(selectedCurrencyProvider.notifier)
                  .select(preferredCurrency);
              state = state.copyWith(currency: preferredCurrency);
            }
          } catch (_) {
            // Prices remain unavailable in the selected currency until a rate is known.
          }
        }
      }
      final catalogGames = await gameOptionsFuture;
      if (generation == _loadGeneration && catalogGames.isNotEmpty) {
        state = state.copyWith(gameOptions: catalogGames);
      }
    } catch (_) {
      if (generation == _loadGeneration) {
        state = CollectionState.unavailable(currency: currency);
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<List<String>> _loadGameOptions(CollectionRepository repository) async {
    if (repository is! CollectionGameCatalogRepository) {
      return const [];
    }
    final gameCatalogRepository = repository as CollectionGameCatalogRepository;
    try {
      return await gameCatalogRepository.loadGameOptions();
    } catch (_) {
      return const [];
    }
  }

  void selectTab(CollectionTab tab) {
    if (state.isUnavailable) {
      return;
    }
    if (tab == state.selectedTab) return;

    final previousTab = state.selectedTab;
    state = state.copyWith(
      selectedTab: tab,
      searchByTab: {...state.searchByTab, previousTab: ''},
      sortByTab: {...state.sortByTab, previousTab: CollectionSort.newest},
      gamesByTab: {...state.gamesByTab, previousTab: <String>{}},
      languagesByTab: {...state.languagesByTab, previousTab: <String>{}},
    );
    _scheduleFirstPage();
  }

  void showTopPerformers({
    required String folderId,
    required List<String> itemIds,
  }) {
    if (state.isUnavailable || state.isLoading) {
      ref.read(selectedPortfolioFolderProvider.notifier).select(folderId);
      ref
          .read(collectionInitialSortProvider.notifier)
          .select(CollectionSort.performanceDesc);
      ref.read(collectionPerformanceOrderProvider.notifier).select(itemIds);
      return;
    }
    if (!state.dashboard.folders.any((folder) => folder.id == folderId)) return;

    state = state.copyWith(
      selectedTab: CollectionTab.portfolio,
      selectedFolderId: folderId,
      sortByTab: {
        ...state.sortByTab,
        CollectionTab.portfolio: CollectionSort.performanceDesc,
      },
      performanceItemIds: itemIds,
    );
    ref.read(selectedPortfolioFolderProvider.notifier).select(folderId);
    _scheduleFirstPage();
    ref.read(collectionInitialSortProvider.notifier).clear();
    ref.read(collectionPerformanceOrderProvider.notifier).clear();
  }

  Future<bool> selectFolder(String folderId) async {
    if (state.isUnavailable || state.isLoading) {
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

    final previousFolderId = state.selectedFolderId;
    state = state.copyWith(
      selectedFolderId: folderId,
      isLoadingPage: state.isPaged,
    );
    final pageGeneration = state.isPaged ? ++_pageGeneration : _pageGeneration;
    ref.read(selectedPortfolioFolderProvider.notifier).select(folderId);
    try {
      final session = ref.read(authControllerProvider).session!;
      await ref
          .read(collectionRepositoryProvider)
          .updatePreferences(session, lastSelectedFolderId: folderId);
      if (state.isPaged && pageGeneration == _pageGeneration) {
        await _loadFirstPage(pageGeneration);
      }
      return true;
    } catch (_) {
      if (pageGeneration == _pageGeneration &&
          state.selectedFolderId == folderId) {
        state = state.copyWith(
          selectedFolderId: previousFolderId,
          isLoadingPage: false,
        );
        ref
            .read(selectedPortfolioFolderProvider.notifier)
            .select(previousFolderId);
      }
      return false;
    }
  }

  Future<CreateFolderResult> createFolder(String name) async {
    final normalized = name.trim();
    if (state.isUnavailable ||
        state.isLoading ||
        normalized.isEmpty ||
        normalized.length > 50) {
      return const CreateFolderResult(CreateFolderStatus.failed);
    }
    final session = ref.read(authControllerProvider).session!;
    Future<CollectionFolder> request() => ref
        .read(collectionRepositoryProvider)
        .createFolder(
          session,
          normalized,
          localPremiumVerified:
              ref.read(appCommercialPolicyProvider).usesAppleSubscription &&
              ref.read(subscriptionControllerProvider).isPro,
        );
    CreateFolderResult applyFolder(CollectionFolder folder) {
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(
          folders: [...state.dashboard.folders, folder],
        ),
      );
      _invalidateFolderDetails();
      if (state.isPaged) unawaited(refreshPreservingContent());
      return CreateFolderResult(CreateFolderStatus.success, folder: folder);
    }

    try {
      final folder = await request();
      return applyFolder(folder);
    } on PortfolioApiException catch (error) {
      if (error.code == 'PREMIUM_REQUIRED') {
        if (ref.read(appCommercialPolicyProvider).hasFreePremiumFeatures) {
          return const CreateFolderResult(CreateFolderStatus.failed);
        }
        await refreshPreservingContent();
        return const CreateFolderResult(CreateFolderStatus.premiumRequired);
      }
      if (error.statusCode == 409 &&
          error.code == 'ENTITLEMENT_SYNC_REQUIRED') {
        if (ref.read(appCommercialPolicyProvider).hasFreePremiumFeatures) {
          return const CreateFolderResult(
            CreateFolderStatus.entitlementSyncRequired,
          );
        }
        final reconciliation = await ref
            .read(subscriptionControllerProvider.notifier)
            .reconcileServerEntitlement();
        if (reconciliation == EntitlementReconciliationResult.freeConfirmed) {
          await refreshPreservingContent();
          return const CreateFolderResult(CreateFolderStatus.premiumRequired);
        }
        if (reconciliation !=
            EntitlementReconciliationResult.premiumSynchronized) {
          return const CreateFolderResult(
            CreateFolderStatus.entitlementSyncRequired,
          );
        }
        try {
          final folder = await request();
          return applyFolder(folder);
        } on PortfolioApiException catch (retryError) {
          if (retryError.code == 'PREMIUM_REQUIRED') {
            await refreshPreservingContent();
            return const CreateFolderResult(CreateFolderStatus.premiumRequired);
          }
          if (retryError.statusCode == 409 &&
              retryError.code == 'ENTITLEMENT_SYNC_REQUIRED') {
            return const CreateFolderResult(
              CreateFolderStatus.entitlementSyncRequired,
            );
          }
          return const CreateFolderResult(CreateFolderStatus.failed);
        } catch (_) {
          return const CreateFolderResult(CreateFolderStatus.failed);
        }
      }
      return const CreateFolderResult(CreateFolderStatus.failed);
    } catch (_) {
      return const CreateFolderResult(CreateFolderStatus.failed);
    }
  }

  Future<bool> renameFolder(String folderId, String name) async {
    final normalized = name.trim();
    if (state.isUnavailable ||
        state.isLoading ||
        normalized.isEmpty ||
        normalized.length > 50) {
      return false;
    }
    try {
      final session = ref.read(authControllerProvider).session!;
      final updated = await ref
          .read(collectionRepositoryProvider)
          .renameFolder(session, folderId, normalized);
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(
          folders: [
            for (final folder in state.dashboard.folders)
              if (folder.id == folderId) updated else folder,
          ],
        ),
      );
      ref
          .read(homeControllerProvider.notifier)
          .updateFolderName(folderId, updated.name);
      _invalidateFolderDetails();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setDefaultFolder(String folderId) async {
    if (state.isUnavailable || state.isLoading) {
      return false;
    }
    try {
      final session = ref.read(authControllerProvider).session!;
      await ref
          .read(collectionRepositoryProvider)
          .setDefaultFolder(session, folderId);
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(
          folders: [
            for (final folder in state.dashboard.folders)
              folder.copyWith(isDefault: folder.id == folderId),
          ],
        ),
      );
      _invalidateFolderDetails();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> reorderFolders(List<String> folderIds) async {
    final current = state.dashboard.folders;
    if (state.isUnavailable ||
        state.isLoading ||
        folderIds.length != current.length ||
        folderIds.toSet().length != current.length) {
      return false;
    }
    final byId = {for (final folder in current) folder.id: folder};
    if (folderIds.any((id) => !byId.containsKey(id))) {
      return false;
    }
    final reordered = [for (final id in folderIds) byId[id]!];
    state = state.copyWith(
      dashboard: state.dashboard.copyWith(folders: reordered),
    );
    try {
      final session = ref.read(authControllerProvider).session!;
      await ref
          .read(collectionRepositoryProvider)
          .reorderFolders(session, folderIds);
      _invalidateFolderDetails();
      return true;
    } catch (_) {
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(folders: current),
      );
      return false;
    }
  }

  Future<bool> deleteFolder(String folderId) async {
    if (state.isUnavailable || state.isLoading) {
      return false;
    }
    final folder = state.dashboard.folders
        .where((candidate) => candidate.id == folderId)
        .firstOrNull;
    if (folder == null || folder.isDefault) {
      return false;
    }
    try {
      final session = ref.read(authControllerProvider).session!;
      await ref
          .read(collectionRepositoryProvider)
          .deleteFolder(session, folderId);
      final selectionChanged = state.selectedFolderId == folderId;
      final fallbackId = state.dashboard.defaultFolder.id;
      final selectedFolderId = selectionChanged
          ? fallbackId
          : state.selectedFolderId;
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(
          folders: state.dashboard.folders
              .where((candidate) => candidate.id != folderId)
              .toList(),
          portfolioItems: state.dashboard.portfolioItems
              .where((item) => item.folderId != folderId)
              .toList(),
        ),
        selectedFolderId: selectedFolderId,
      );
      if (selectionChanged) {
        ref.read(selectedPortfolioFolderProvider.notifier).select(fallbackId);
      }
      _invalidateFolderDetails();
      if (state.isPaged) unawaited(refreshPreservingContent());
      return true;
    } catch (_) {
      return false;
    }
  }

  void updateSearch(String value) {
    if (state.isUnavailable) {
      return;
    }

    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: value},
    );
    _scheduleFirstPage(debounce: true);
  }

  void applySortAndFilters({
    required CollectionSort sort,
    required Set<String> games,
    required Set<String> languages,
  }) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(
      sortByTab: {...state.sortByTab, state.selectedTab: sort},
      gamesByTab: {...state.gamesByTab, state.selectedTab: games},
      languagesByTab: {...state.languagesByTab, state.selectedTab: languages},
    );
    _scheduleFirstPage();
  }

  void clearFilters() {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(
      sortByTab: {...state.sortByTab, state.selectedTab: CollectionSort.newest},
      gamesByTab: {...state.gamesByTab, state.selectedTab: <String>{}},
      languagesByTab: {...state.languagesByTab, state.selectedTab: <String>{}},
    );
    _scheduleFirstPage();
  }

  Future<bool> toggleAmountHidden() async {
    if (state.isUnavailable || state.isLoading) {
      return false;
    }

    final previous = state.amountHidden;
    final next = !previous;
    state = state.copyWith(amountHidden: next);
    final saved = await ref
        .read(portfolioAmountHiddenProvider.notifier)
        .select(next);
    // Backend persistence is intentionally disabled while visibility is local.
    // try {
    //   final session = ref.read(authControllerProvider).session!;
    //   await ref
    //       .read(collectionRepositoryProvider)
    //       .updatePreferences(session, amountHidden: next);
    // } catch (_) {
    //   state = state.copyWith(amountHidden: previous);
    //   return false;
    // }
    if (!saved && state.amountHidden == next) {
      state = state.copyWith(amountHidden: previous);
    }
    return saved;
  }

  void _invalidateFolderDetails() {
    ref.invalidate(collectionEditorFoldersProvider);
    ref.invalidate(cardDetailControllerProvider);
  }
}
