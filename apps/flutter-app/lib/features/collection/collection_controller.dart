import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/market/market_change.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/ui/load_state.dart';

import 'collection_models.dart';
import 'collection_repository.dart';

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return HttpCollectionRepository(ref.watch(portfolioApiClientProvider));
});

final collectionControllerProvider =
    NotifierProvider<CollectionController, CollectionState>(
      CollectionController.new,
    );

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
        CollectionSort.newest => b.createdAtSort.compareTo(a.createdAtSort),
        CollectionSort.valueDesc => _nullableDoubleDesc(
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
    final items = dashboard.portfolioItems
        .where((item) => item.folderId == selectedFolder.id)
        .toList();
    final total = items.fold<double>(0, (sum, item) {
      final value = item.marketValueUsd;
      if (value == null || value <= 0) {
        return sum;
      }
      return sum + value * item.quantity;
    });

    return CollectionSummary(
      totalValueText: _formatPortfolioTotal(total),
      cardCount: items.length,
      gradedCount: items.where((item) => item.isGraded).length,
    );
  }

  bool get isEmpty => _baseItems.isEmpty;

  bool get isNoMatch => _baseItems.isNotEmpty && visibleItems.isEmpty;

  CollectionState copyWith({
    CollectionTab? selectedTab,
    String? selectedFolderId,
    AppCurrency? currency,
    bool? amountHidden,
    Map<CollectionTab, String>? searchByTab,
    Map<CollectionTab, CollectionSort>? sortByTab,
    Map<CollectionTab, Set<String>>? gamesByTab,
    Map<CollectionTab, Set<String>>? languagesByTab,
  }) {
    return CollectionState._(
      dashboard: _dashboard,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      currency: currency ?? this.currency,
      amountHidden: amountHidden ?? this.amountHidden,
      searchByTab: searchByTab ?? this.searchByTab,
      sortByTab: sortByTab ?? this.sortByTab,
      gamesByTab: gamesByTab ?? this.gamesByTab,
      languagesByTab: languagesByTab ?? this.languagesByTab,
      loadStatus: loadStatus,
    );
  }

  String _formatPortfolioTotal(double valueUsd) {
    return CurrencyFormatter(
      currency: currency,
    ).formatUsd(valueUsd, hidden: amountHidden);
  }

  String _formatMoney(double? valueUsd, int quantity) {
    if (amountHidden) {
      return hiddenMoneyText;
    }
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

    final currency = ref.watch(selectedCurrencyProvider);
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
      final dashboard = await ref
          .read(collectionRepositoryProvider)
          .loadDashboard(session);
      if (generation == _loadGeneration) {
        state = CollectionState(
          dashboard: dashboard,
          selectedTab: CollectionTab.portfolio,
          selectedFolderId: dashboard.defaultFolder.id,
          currency: currency,
          amountHidden: false,
          searchByTab: const {
            CollectionTab.portfolio: '',
            CollectionTab.wishlist: '',
          },
          sortByTab: const {
            CollectionTab.portfolio: CollectionSort.newest,
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
        );
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

  void selectTab(CollectionTab tab) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(selectedTab: tab);
  }

  void selectFolder(String folderId) {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    final exists = state.dashboard.folders.any(
      (folder) => folder.id == folderId,
    );
    if (!exists) {
      return;
    }

    state = state.copyWith(selectedFolderId: folderId);
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

  void toggleAmountHidden() {
    if (state.isUnavailable || state.isLoading) {
      return;
    }

    state = state.copyWith(amountHidden: !state.amountHidden);
  }
}
