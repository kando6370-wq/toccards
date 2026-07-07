import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collection_models.dart';
import 'collection_repository.dart';

const hiddenCollectionAmountText = '••••••';

final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return const MockCollectionRepository();
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
    required this.dashboard,
    required this.selectedTab,
    required this.selectedFolderId,
    required this.amountHidden,
    required this.searchByTab,
    required this.sortByTab,
    required this.gamesByTab,
    required this.languagesByTab,
  });

  final CollectionDashboard dashboard;
  final CollectionTab selectedTab;
  final String selectedFolderId;
  final bool amountHidden;
  final Map<CollectionTab, String> searchByTab;
  final Map<CollectionTab, CollectionSort> sortByTab;
  final Map<CollectionTab, Set<String>> gamesByTab;
  final Map<CollectionTab, Set<String>> languagesByTab;

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
          a.change30dPercent,
          b.change30dPercent,
        ),
        CollectionSort.nameAsc => a.name.compareTo(b.name),
      };
    });

    return [
      for (final item in filtered)
        CollectionViewItem(
          source: item,
          valueText: _formatMoney(item.marketValueUsd, item.quantity),
          changeText: _formatPercent(item.change30dPercent),
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
      totalValueText: amountHidden
          ? hiddenCollectionAmountText
          : _formatUsd(total),
      cardCount: items.length,
      gradedCount: items.where((item) => item.isGraded).length,
    );
  }

  bool get isEmpty => _baseItems.isEmpty;

  bool get isNoMatch => _baseItems.isNotEmpty && visibleItems.isEmpty;

  CollectionState copyWith({
    CollectionTab? selectedTab,
    String? selectedFolderId,
    bool? amountHidden,
    Map<CollectionTab, String>? searchByTab,
    Map<CollectionTab, CollectionSort>? sortByTab,
    Map<CollectionTab, Set<String>>? gamesByTab,
    Map<CollectionTab, Set<String>>? languagesByTab,
  }) {
    return CollectionState(
      dashboard: dashboard,
      selectedTab: selectedTab ?? this.selectedTab,
      selectedFolderId: selectedFolderId ?? this.selectedFolderId,
      amountHidden: amountHidden ?? this.amountHidden,
      searchByTab: searchByTab ?? this.searchByTab,
      sortByTab: sortByTab ?? this.sortByTab,
      gamesByTab: gamesByTab ?? this.gamesByTab,
      languagesByTab: languagesByTab ?? this.languagesByTab,
    );
  }

  String _formatMoney(double? valueUsd, int quantity) {
    if (amountHidden) {
      return hiddenCollectionAmountText;
    }
    if (valueUsd == null || valueUsd <= 0) {
      return '--';
    }
    return _formatUsd(valueUsd * quantity);
  }

  String _formatPercent(double? value) {
    if (value == null) {
      return '-/-';
    }

    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)}%';
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

  static String _formatUsd(double value) {
    final rounded = value.round();
    final source = rounded.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < source.length; index++) {
      final remaining = source.length - index;
      buffer.write(source[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return r'$' + buffer.toString();
  }
}

class CollectionController extends Notifier<CollectionState> {
  @override
  CollectionState build() {
    final dashboard = ref.watch(collectionRepositoryProvider).loadDashboard();
    return CollectionState(
      dashboard: dashboard,
      selectedTab: CollectionTab.portfolio,
      selectedFolderId: dashboard.defaultFolder.id,
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

  void selectTab(CollectionTab tab) {
    state = state.copyWith(selectedTab: tab);
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

  void updateSearch(String value) {
    state = state.copyWith(
      searchByTab: {...state.searchByTab, state.selectedTab: value},
    );
  }

  void applySortAndFilters({
    required CollectionSort sort,
    required Set<String> games,
    required Set<String> languages,
  }) {
    state = state.copyWith(
      sortByTab: {...state.sortByTab, state.selectedTab: sort},
      gamesByTab: {...state.gamesByTab, state.selectedTab: games},
      languagesByTab: {...state.languagesByTab, state.selectedTab: languages},
    );
  }

  void clearFilters() {
    state = state.copyWith(
      sortByTab: {...state.sortByTab, state.selectedTab: CollectionSort.newest},
      gamesByTab: {...state.gamesByTab, state.selectedTab: <String>{}},
      languagesByTab: {...state.languagesByTab, state.selectedTab: <String>{}},
    );
  }

  void toggleAmountHidden() {
    state = state.copyWith(amountHidden: !state.amountHidden);
  }
}
