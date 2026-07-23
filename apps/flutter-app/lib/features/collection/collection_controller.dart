import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/card_detail/card_detail_controller.dart';
import 'package:kando_app/features/home/home_controller.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
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

class CollectionSummary {
  const CollectionSummary({
    required this.totalValueText,
    required this.cardCount,
    required this.gradedCount,
  });

  final String totalValueText;
  final int cardCount;
  final int gradedCount;
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
    this.gameOptions = const [],
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
      gameOptions = const [],
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
      gameOptions = const [],
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
    required this.gameOptions,
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
  final List<String> gameOptions;
  final KandoLoadStatus loadStatus;

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
    final items = visibleItems.map((item) => item.source).toList();
    final total = items.fold<double>(0, (sum, item) {
      final value = item.marketValueUsd;
      if (value == null || value <= 0) {
        return sum;
      }
      return sum + value * item.quantity;
    });

    return CollectionSummary(
      totalValueText: _formatPortfolioTotal(total),
      cardCount: items.fold(0, (sum, item) => sum + item.quantity),
      gradedCount: items
          .where((item) => item.isGraded)
          .fold(0, (sum, item) => sum + item.quantity),
    );
  }

  bool get isEmpty => _baseItems.isEmpty;

  bool get isNoMatch => _baseItems.isNotEmpty && visibleItems.isEmpty;

  List<String> get availableGames {
    return gameOptions;
  }

  List<String> get availableLanguages {
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
    List<String>? gameOptions,
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
      gameOptions: gameOptions ?? this.gameOptions,
      loadStatus: loadStatus,
    );
  }

  String _formatPortfolioTotal(double valueUsd) {
    return CurrencyFormatter(
      currency: currency,
    ).formatUsd(valueUsd, hidden: amountHidden);
  }

  String _formatMoney(double? valueUsd, int quantity) {
    if (valueUsd == null || valueUsd <= 0) {
      return '--';
    }
    return CurrencyFormatter(
      currency: currency,
    ).formatUsd(valueUsd, quantity: quantity);
  }

  String _formatChange(CollectionItem item) {
    return MarketChange.fromPrices(
      current: item.marketValueUsd,
      previous: item.previous30dPriceUsd,
    ).percentText;
  }

  double? _changePercent(CollectionItem item) {
    return MarketChange.fromPrices(
      current: item.marketValueUsd,
      previous: item.previous30dPriceUsd,
    ).percent;
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
  var _loadGeneration = 0;

  Future<void> get loadComplete {
    return _loadCompleter?.future ?? Future<void>.value();
  }

  @override
  CollectionState build() {
    ref.listen<AppCurrency>(selectedCurrencyProvider, (previous, next) {
      state = state.copyWith(currency: next);
    });
    ref.listen<String?>(selectedPortfolioFolderProvider, (previous, next) {
      if (next == null || state.isLoading || state.isUnavailable) return;
      if (state.dashboard.folders.any((folder) => folder.id == next)) {
        state = state.copyWith(selectedFolderId: next);
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

  void _startLoad({
    required AuthSession session,
    required AppCurrency currency,
  }) {
    final completer = Completer<void>();
    final generation = ++_loadGeneration;
    _loadCompleter = completer;
    unawaited(_loadDashboard(session, currency, generation, completer));
  }

  Future<void> _loadDashboard(
    AuthSession session,
    AppCurrency currency,
    int generation,
    Completer<void> completer,
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
          preferredCurrency = AppCurrency.usd;
          if (currencyMetadata.code != 'USD') {
            try {
              final rate = await ref
                  .read(currencyRateApiProvider)
                  .loadUsdRate(currencyMetadata.code);
              preferredCurrency = currencyMetadata.withUsdRate(rate);
            } catch (_) {
              // Keep USD until the provider can prove a conversion rate.
            }
          }
        }
        if (generation != _loadGeneration) return;
        final sharedFolderId = ref.read(selectedPortfolioFolderProvider);
        final selectedFolderId =
            dashboard.folders.any((folder) => folder.id == sharedFolderId)
            ? sharedFolderId!
            : dashboard.defaultFolder.id;
        final amountHidden =
            ref.read(portfolioAmountHiddenProvider) ?? dashboard.amountHidden;
        final initialSort =
            ref.read(collectionInitialSortProvider) ?? CollectionSort.newest;
        ref.read(selectedCurrencyProvider.notifier).select(preferredCurrency);
        state = CollectionState(
          dashboard: dashboard,
          selectedTab: CollectionTab.portfolio,
          selectedFolderId: selectedFolderId,
          currency: preferredCurrency,
          amountHidden: amountHidden,
          searchByTab: const {
            CollectionTab.portfolio: '',
            CollectionTab.wishlist: '',
          },
          sortByTab: {
            CollectionTab.portfolio: initialSort,
            CollectionTab.wishlist: CollectionSort.newest,
          },
          gamesByTab: const {
            CollectionTab.portfolio: <String>{},
            CollectionTab.wishlist: <String>{},
          },
          languagesByTab: const {
            CollectionTab.portfolio: <String>{},
            CollectionTab.wishlist: <String>{},
          },
          gameOptions: gameOptions,
        );
        ref.read(collectionInitialSortProvider.notifier).clear();
        if (sharedFolderId == null) {
          ref
              .read(selectedPortfolioFolderProvider.notifier)
              .select(selectedFolderId);
        }
        if (ref.read(portfolioAmountHiddenProvider) == null) {
          ref.read(portfolioAmountHiddenProvider.notifier).select(amountHidden);
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
    if (state.isUnavailable || state.isLoading) {
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

    final previousFolderId = state.selectedFolderId;
    state = state.copyWith(selectedFolderId: folderId);
    try {
      final session = ref.read(authControllerProvider).session!;
      await ref
          .read(collectionRepositoryProvider)
          .updatePreferences(session, lastSelectedFolderId: folderId);
      ref.read(selectedPortfolioFolderProvider.notifier).select(folderId);
      return true;
    } catch (_) {
      state = state.copyWith(selectedFolderId: previousFolderId);
      return false;
    }
  }

  Future<CollectionFolder?> createFolder(String name) async {
    final normalized = name.trim();
    if (state.isUnavailable ||
        state.isLoading ||
        normalized.isEmpty ||
        normalized.length > 50) {
      return null;
    }
    try {
      final session = ref.read(authControllerProvider).session!;
      final folder = await ref
          .read(collectionRepositoryProvider)
          .createFolder(session, normalized);
      state = state.copyWith(
        dashboard: state.dashboard.copyWith(
          folders: [...state.dashboard.folders, folder],
        ),
      );
      _invalidateFolderConsumers();
      return folder;
    } catch (_) {
      return null;
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
      _invalidateFolderConsumers();
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
      _invalidateFolderConsumers();
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
      _invalidateFolderConsumers();
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
      final fallbackId = state.dashboard.defaultFolder.id;
      final selectedFolderId = state.selectedFolderId == folderId
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
      if (selectedFolderId == fallbackId) {
        ref.read(selectedPortfolioFolderProvider.notifier).select(fallbackId);
      }
      _invalidateFolderConsumers();
      return true;
    } catch (_) {
      return false;
    }
  }

  void updateSearch(String value) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: value},
    );
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
  }

  Future<bool> toggleAmountHidden() async {
    if (state.isUnavailable || state.isLoading) {
      return false;
    }

    final previous = state.amountHidden;
    state = state.copyWith(amountHidden: !previous);
    try {
      final session = ref.read(authControllerProvider).session!;
      await ref
          .read(collectionRepositoryProvider)
          .updatePreferences(session, amountHidden: !previous);
      ref.read(portfolioAmountHiddenProvider.notifier).select(!previous);
      return true;
    } catch (_) {
      state = state.copyWith(amountHidden: previous);
      return false;
    }
  }

  void _invalidateFolderConsumers() {
    ref.invalidate(homeControllerProvider);
    ref.invalidate(cardDetailControllerProvider);
  }
}
