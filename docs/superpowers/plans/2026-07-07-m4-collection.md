# M4 Collection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the M4-2 Flutter Collection page with Portfolio/Wishlist tabs, mock-backed state, search, sort, filter, amount hiding, empty states, and bottom navigation entry.

**Architecture:** Add a self-contained `features/collection` Flutter module with display models, a mock repository, a Riverpod controller, and a page. Keep all data in memory for M4-2; later tasks can replace the repository with Workers API calls without changing the UI contract.

**Tech Stack:** Flutter, Dart, Material 3, Riverpod `NotifierProvider`, go_router, Flutter unit/widget tests.

---

## Execution Constraints

- M4-2 has already been started in `docs/superpowers/execution-status.md`; do not rerun the start hook in this worktree.
- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/workers-api/src/db/schema.ts`, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not modify `apps/admin-web` or any Admin/M7 API code.
- Do not introduce new dependencies or code generation.
- Do not run Flutter tests concurrently.
- Use TDD: write the failing test, run it, implement the minimum code, rerun the test, then commit.

## File Structure

- Create: `apps/flutter-app/lib/features/collection/collection_models.dart`
  - Collection tab, sort, filter, folder, summary, and item display models.
- Create: `apps/flutter-app/lib/features/collection/collection_repository.dart`
  - `CollectionRepository` interface and deterministic mock data.
- Create: `apps/flutter-app/lib/features/collection/collection_controller.dart`
  - Riverpod providers, `CollectionState`, derived lists, search/sort/filter interactions, amount hiding.
- Create: `apps/flutter-app/lib/features/collection/collection_page.dart`
  - Material UI for Collection, Portfolio/Wishlist tabs, bottom sheets, list rows, empty states, bottom navigation.
- Create: `apps/flutter-app/test/collection_controller_test.dart`
  - Unit tests for state and derived behavior.
- Create: `apps/flutter-app/test/widget/collection_page_test.dart`
  - Widget tests for page structure and interactions.
- Modify: `apps/flutter-app/lib/app/router.dart`
  - Add `/collection`.
- Modify: `apps/flutter-app/lib/features/home/home_page.dart`
  - Route Collection bottom tab to `/collection`.
- Modify: `apps/flutter-app/test/widget/home_page_test.dart`
  - Change the Collection bottom tab boundary test to expect route navigation.
- Modify: `docs/superpowers/execution-status.md`
  - Stop hook only after final validation passes.

---

### Task 1: Collection State Model and Controller

**Files:**
- Create: `apps/flutter-app/test/collection_controller_test.dart`
- Create: `apps/flutter-app/lib/features/collection/collection_models.dart`
- Create: `apps/flutter-app/lib/features/collection/collection_repository.dart`
- Create: `apps/flutter-app/lib/features/collection/collection_controller.dart`

- [ ] **Step 1: Write failing controller tests**

Create `apps/flutter-app/test/collection_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/collection/collection_controller.dart';
import 'package:kando_app/features/collection/collection_models.dart';

void main() {
  test('defaults to Portfolio tab and Main folder summary', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(collectionControllerProvider);

    expect(state.selectedTab, CollectionTab.portfolio);
    expect(state.selectedFolder.name, 'Main');
    expect(state.portfolioSummary.totalValueText, r'$1,245');
    expect(state.portfolioSummary.cardCount, 3);
    expect(state.portfolioSummary.gradedCount, 2);
    expect(state.visibleItems.map((item) => item.name), [
      'Charizard ex',
      'Umbreon VMAX',
      'Pikachu Promo',
    ]);
  });

  test('switching folders changes only Portfolio scoped items', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.selectFolder('sealed');
    final sealed = container.read(collectionControllerProvider);

    expect(sealed.selectedFolder.name, 'Sealed');
    expect(sealed.visibleItems.map((item) => item.name), [
      'Evolving Skies Booster Box',
    ]);

    controller.selectTab(CollectionTab.wishlist);
    final wishlist = container.read(collectionControllerProvider);

    expect(wishlist.visibleItems.map((item) => item.name), [
      'Lorcana Elsa',
      'One Piece Manga Luffy',
    ]);
  });

  test('search is scoped per tab and current folder', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.updateSearch('umbreon');
    expect(
      container.read(collectionControllerProvider).visibleItems.single.name,
      'Umbreon VMAX',
    );

    controller.selectTab(CollectionTab.wishlist);
    expect(container.read(collectionControllerProvider).searchText, '');

    controller.updateSearch('luffy');
    expect(
      container.read(collectionControllerProvider).visibleItems.single.name,
      'One Piece Manga Luffy',
    );
  });

  test('sort and filters combine for the selected tab', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.applySortAndFilters(
      sort: CollectionSort.valueDesc,
      games: {'Pokemon'},
      languages: {'English'},
    );
    final filtered = container.read(collectionControllerProvider);

    expect(filtered.visibleItems.map((item) => item.name), [
      'Umbreon VMAX',
      'Charizard ex',
    ]);
  });

  test('amount hiding masks money but leaves percentages readable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.toggleAmountHidden();
    final state = container.read(collectionControllerProvider);

    expect(state.portfolioSummary.totalValueText, '••••••');
    expect(state.visibleItems.first.valueText, '••••••');
    expect(state.visibleItems.first.changeText, '+8.1%');
  });

  test('empty and no-match states are distinct', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(collectionControllerProvider.notifier);

    controller.selectFolder('empty');
    expect(container.read(collectionControllerProvider).isEmpty, isTrue);
    expect(container.read(collectionControllerProvider).isNoMatch, isFalse);

    controller.selectFolder('main');
    controller.updateSearch('missing');
    expect(container.read(collectionControllerProvider).isEmpty, isFalse);
    expect(container.read(collectionControllerProvider).isNoMatch, isTrue);
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run from `apps/flutter-app`:

```powershell
flutter test test/collection_controller_test.dart
```

Expected result: FAIL because `features/collection/*` does not exist.

- [ ] **Step 3: Add Collection models**

Create `apps/flutter-app/lib/features/collection/collection_models.dart`:

```dart
enum CollectionTab { portfolio, wishlist }

enum CollectionSort { newest, valueDesc, changeDesc, nameAsc }

class CollectionFolder {
  const CollectionFolder({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;
}

class CollectionItem {
  const CollectionItem({
    required this.id,
    required this.folderId,
    required this.name,
    required this.setName,
    required this.number,
    required this.game,
    required this.language,
    required this.finish,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.quantity,
    required this.marketValueUsd,
    required this.change30dPercent,
    required this.createdAtSort,
  });

  final String id;
  final String? folderId;
  final String name;
  final String setName;
  final String number;
  final String game;
  final String language;
  final String finish;
  final String grader;
  final String? condition;
  final double? grade;
  final int quantity;
  final double? marketValueUsd;
  final double? change30dPercent;
  final int createdAtSort;

  bool get isGraded => grader != 'Raw';

  String get statusText {
    if (isGraded) {
      return '$grader ${grade?.toStringAsFixed(0) ?? '-'}';
    }
    return 'Raw · ${condition ?? '-'}';
  }

  String get searchableText {
    return '$name $setName $number $game'.toLowerCase();
  }
}

class CollectionDashboard {
  const CollectionDashboard({
    required this.folders,
    required this.portfolioItems,
    required this.wishlistItems,
  });

  final List<CollectionFolder> folders;
  final List<CollectionItem> portfolioItems;
  final List<CollectionItem> wishlistItems;

  CollectionFolder get defaultFolder {
    return folders.firstWhere((folder) => folder.isDefault);
  }
}
```

- [ ] **Step 4: Add the mock repository**

Create `apps/flutter-app/lib/features/collection/collection_repository.dart`:

```dart
import 'collection_models.dart';

abstract interface class CollectionRepository {
  CollectionDashboard loadDashboard();
}

class MockCollectionRepository implements CollectionRepository {
  const MockCollectionRepository();

  @override
  CollectionDashboard loadDashboard() {
    return const CollectionDashboard(
      folders: [
        CollectionFolder(id: 'main', name: 'Main', isDefault: true),
        CollectionFolder(id: 'sealed', name: 'Sealed', isDefault: false),
        CollectionFolder(id: 'empty', name: 'Empty', isDefault: false),
      ],
      portfolioItems: [
        CollectionItem(
          id: 'item-charizard',
          folderId: 'main',
          name: 'Charizard ex',
          setName: 'Obsidian Flames',
          number: '#223',
          game: 'Pokemon',
          language: 'English',
          finish: 'Holofoil',
          grader: 'PSA',
          condition: null,
          grade: 10,
          quantity: 1,
          marketValueUsd: 780,
          change30dPercent: 8.1,
          createdAtSort: 3,
        ),
        CollectionItem(
          id: 'item-umbreon',
          folderId: 'main',
          name: 'Umbreon VMAX',
          setName: 'Evolving Skies',
          number: '#215',
          game: 'Pokemon',
          language: 'English',
          finish: 'Alternate Art',
          grader: 'BGS',
          condition: null,
          grade: 9,
          quantity: 1,
          marketValueUsd: 410,
          change30dPercent: 12.2,
          createdAtSort: 2,
        ),
        CollectionItem(
          id: 'item-pikachu',
          folderId: 'main',
          name: 'Pikachu Promo',
          setName: 'Scarlet & Violet Promos',
          number: '#088',
          game: 'Pokemon',
          language: 'Japanese',
          finish: 'Promo',
          grader: 'Raw',
          condition: 'Near Mint',
          grade: null,
          quantity: 2,
          marketValueUsd: 27.5,
          change30dPercent: -1.4,
          createdAtSort: 1,
        ),
        CollectionItem(
          id: 'item-sealed-box',
          folderId: 'sealed',
          name: 'Evolving Skies Booster Box',
          setName: 'Sword & Shield',
          number: '36 Packs',
          game: 'Pokemon',
          language: 'English',
          finish: 'Sealed',
          grader: 'Raw',
          condition: 'Sealed',
          grade: null,
          quantity: 1,
          marketValueUsd: 620,
          change30dPercent: 5.4,
          createdAtSort: 4,
        ),
      ],
      wishlistItems: [
        CollectionItem(
          id: 'wish-elsa',
          folderId: null,
          name: 'Lorcana Elsa',
          setName: 'The First Chapter',
          number: '#212',
          game: 'Lorcana',
          language: 'English',
          finish: 'Enchanted',
          grader: 'Raw',
          condition: 'Near Mint',
          grade: null,
          quantity: 1,
          marketValueUsd: 480,
          change30dPercent: 6.7,
          createdAtSort: 2,
        ),
        CollectionItem(
          id: 'wish-luffy',
          folderId: null,
          name: 'One Piece Manga Luffy',
          setName: 'Romance Dawn',
          number: '#001',
          game: 'One Piece',
          language: 'Japanese',
          finish: 'Manga',
          grader: 'Raw',
          condition: 'Near Mint',
          grade: null,
          quantity: 1,
          marketValueUsd: 330,
          change30dPercent: 7.6,
          createdAtSort: 1,
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Add the controller**

Create `apps/flutter-app/lib/features/collection/collection_controller.dart`:

```dart
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
  CollectionSort get selectedSort => sortByTab[selectedTab] ?? CollectionSort.newest;
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
      final matchesSearch = query.isEmpty || item.searchableText.contains(query);
      final matchesGame = selectedGames.isEmpty || selectedGames.contains(item.game);
      final matchesLanguage =
          selectedLanguages.isEmpty || selectedLanguages.contains(item.language);
      return matchesSearch && matchesGame && matchesLanguage;
    }).toList();

    filtered.sort((a, b) {
      return switch (selectedSort) {
        CollectionSort.newest => b.createdAtSort.compareTo(a.createdAtSort),
        CollectionSort.valueDesc => _nullableDoubleDesc(a.marketValueUsd, b.marketValueUsd),
        CollectionSort.changeDesc =>
          _nullableDoubleDesc(a.change30dPercent, b.change30dPercent),
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
      totalValueText: amountHidden ? hiddenCollectionAmountText : _formatUsd(total),
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
    return '\$${buffer.toString()}';
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
        CollectionTab.portfolio: {},
        CollectionTab.wishlist: {},
      },
      languagesByTab: const {
        CollectionTab.portfolio: {},
        CollectionTab.wishlist: {},
      },
    );
  }

  void selectTab(CollectionTab tab) {
    state = state.copyWith(selectedTab: tab);
  }

  void selectFolder(String folderId) {
    final exists = state.dashboard.folders.any((folder) => folder.id == folderId);
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
```

- [ ] **Step 6: Format and run controller tests**

Run from `apps/flutter-app`:

```powershell
dart format lib/features/collection test/collection_controller_test.dart
flutter test test/collection_controller_test.dart
```

Expected result: PASS.

- [ ] **Step 7: Commit Task 1**

```powershell
git add apps/flutter-app/lib/features/collection apps/flutter-app/test/collection_controller_test.dart
git commit -m "feat: add Collection state model"
```

---

### Task 2: Collection Page UI

**Files:**
- Create: `apps/flutter-app/test/widget/collection_page_test.dart`
- Create: `apps/flutter-app/lib/features/collection/collection_page.dart`

- [ ] **Step 1: Write failing widget tests**

Create `apps/flutter-app/test/widget/collection_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/collection/collection_page.dart';

void main() {
  testWidgets('Collection shows Portfolio summary and rows by default', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    expect(find.text('Collection'), findsOneWidget);
    expect(find.text('Portfolio'), findsWidgets);
    expect(find.text('Wishlist'), findsOneWidget);
    expect(find.text('Main'), findsOneWidget);
    expect(find.text(r'$1,245'), findsOneWidget);
    expect(find.text('3 cards'), findsOneWidget);
    expect(find.text('2 graded'), findsOneWidget);
    expect(find.text('Charizard ex'), findsOneWidget);
    expect(find.text('Qty: 2'), findsOneWidget);
  });

  testWidgets('folder picker changes Portfolio list', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.tap(find.text('Main'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sealed').last);
    await tester.pumpAndSettle();

    expect(find.text('Sealed'), findsOneWidget);
    expect(find.text('Evolving Skies Booster Box'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });

  testWidgets('Wishlist tab uses wishlist copy and hides quantity', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.tap(find.text('Wishlist'));
    await tester.pumpAndSettle();

    expect(find.text('Lorcana Elsa'), findsOneWidget);
    expect(find.text('One Piece Manga Luffy'), findsOneWidget);
    expect(find.textContaining('Qty:'), findsNothing);
  });

  testWidgets('search no-match state is distinct from empty state', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No matching cards found.'), findsOneWidget);
    expect(find.text('No cards in this portfolio yet.'), findsNothing);
  });

  testWidgets('amount toggle masks collection money', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.tap(find.byKey(const Key('collection-hide-amount')));
    await tester.pumpAndSettle();

    expect(find.text('••••••'), findsWidgets);
    expect(find.text(r'$1,245'), findsNothing);
    expect(find.text('+8.1%'), findsOneWidget);
  });

  testWidgets('filter sheet applies Game and Language filters', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: _CollectionTestApp()));

    await tester.tap(find.byKey(const Key('collection-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Japanese'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Pikachu Promo'), findsOneWidget);
    expect(find.text('Charizard ex'), findsNothing);
  });
}

class _CollectionTestApp extends StatelessWidget {
  const _CollectionTestApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: CollectionPage());
  }
}
```

- [ ] **Step 2: Run the widget tests and confirm they fail**

Run from `apps/flutter-app`:

```powershell
flutter test test/widget/collection_page_test.dart
```

Expected result: FAIL because `collection_page.dart` does not exist.

- [ ] **Step 3: Add the page**

Create `apps/flutter-app/lib/features/collection/collection_page.dart` with this structure:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'collection_controller.dart';
import 'collection_models.dart';

class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectionControllerProvider);
    final controller = ref.read(collectionControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CollectionHeader(
              state: state,
              onFolderPressed: () => _showFolderSheet(context, ref),
              onHidePressed: controller.toggleAmountHidden,
            ),
            const SizedBox(height: 16),
            SegmentedButton<CollectionTab>(
              segments: const [
                ButtonSegment(value: CollectionTab.portfolio, label: Text('Portfolio')),
                ButtonSegment(value: CollectionTab.wishlist, label: Text('Wishlist')),
              ],
              selected: {state.selectedTab},
              onSelectionChanged: (selection) => controller.selectTab(selection.single),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search cards',
                border: OutlineInputBorder(),
              ),
              onChanged: controller.updateSearch,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _SummaryText(state: state)),
                IconButton(
                  key: const Key('collection-filter-button'),
                  onPressed: () => _showFilterSheet(context, ref),
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CollectionContent(state: state),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (index) {
          if (index == 0) {
            context.go('/');
          } else if (index == 4) {
            context.go('/profile');
          } else if (index != 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This section is coming soon.')),
            );
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.collections_bookmark_outlined), label: 'Collection'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner_outlined), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.search_outlined), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
```

Continue in the same file with focused private widgets and helper functions:

```dart
class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.state,
    required this.onFolderPressed,
    required this.onHidePressed,
  });

  final CollectionState state;
  final VoidCallback onFolderPressed;
  final VoidCallback onHidePressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Collection', style: Theme.of(context).textTheme.headlineMedium),
              TextButton(onPressed: onFolderPressed, child: Text(state.selectedFolder.name)),
            ],
          ),
        ),
        IconButton(
          key: const Key('collection-hide-amount'),
          onPressed: onHidePressed,
          icon: Icon(state.amountHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ],
    );
  }
}

class _SummaryText extends StatelessWidget {
  const _SummaryText({required this.state});

  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    if (state.selectedTab == CollectionTab.wishlist) {
      return Text('${state.visibleItems.length} wishlist cards');
    }
    final summary = state.portfolioSummary;
    return Wrap(
      spacing: 10,
      children: [
        Text(summary.totalValueText),
        Text('${summary.cardCount} cards'),
        Text('${summary.gradedCount} graded'),
      ],
    );
  }
}

class _CollectionContent extends StatelessWidget {
  const _CollectionContent({required this.state});

  final CollectionState state;

  @override
  Widget build(BuildContext context) {
    if (state.isNoMatch) {
      return const _MessageBlock(title: 'No matching cards found.');
    }
    if (state.isEmpty && state.selectedTab == CollectionTab.portfolio) {
      return const _MessageBlock(
        title: 'No cards in this portfolio yet.',
        body: 'Scan or search cards to start tracking your collection.',
        primary: 'Scan a Card',
        secondary: 'Search Cards',
      );
    }
    if (state.isEmpty) {
      return const _MessageBlock(
        title: 'Your wishlist is empty.',
        body: 'Save cards you want to collect later and keep an eye on their market value.',
        primary: 'Search Cards',
      );
    }
    return Column(
      children: [
        for (final item in state.visibleItems)
          _CollectionCardRow(
            item: item,
            showQuantity: state.selectedTab == CollectionTab.portfolio,
          ),
      ],
    );
  }
}

class _CollectionCardRow extends StatelessWidget {
  const _CollectionCardRow({required this.item, required this.showQuantity});

  final CollectionViewItem item;
  final bool showQuantity;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                  Text('${item.setName} · ${item.number}'),
                  Text('${item.language} · ${item.finish} · ${item.statusText}'),
                  if (showQuantity) Text('Qty: ${item.quantity}'),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(item.valueText),
                Text(item.changeText),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({
    required this.title,
    this.body,
    this.primary,
    this.secondary,
  });

  final String title;
  final String? body;
  final String? primary;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!),
            ],
            if (primary != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: () {}, child: Text(primary!)),
            ],
            if (secondary != null) TextButton(onPressed: () {}, child: Text(secondary!)),
          ],
        ),
      ),
    );
  }
}
```

Add bottom sheets in the same file:

```dart
Future<void> _showFolderSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(collectionControllerProvider);
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final folder in state.dashboard.folders)
            ListTile(
              title: Text(folder.name),
              trailing: folder.id == state.selectedFolder.id ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(collectionControllerProvider.notifier).selectFolder(folder.id);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    ),
  );
}

Future<void> _showFilterSheet(BuildContext context, WidgetRef ref) {
  final state = ref.read(collectionControllerProvider);
  var sort = state.selectedSort;
  final games = {...state.selectedGames};
  final languages = {...state.selectedLanguages};

  return showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          void toggle(Set<String> target, String value) {
            setModalState(() {
              if (target.contains(value)) {
                target.remove(value);
              } else {
                target.add(value);
              }
            });
          }

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Sort'),
                for (final option in CollectionSort.values)
                  RadioListTile<CollectionSort>(
                    title: Text(_sortLabel(option)),
                    value: option,
                    groupValue: sort,
                    onChanged: (value) => setModalState(() => sort = value!),
                  ),
                const Text('Game / IP'),
                for (final game in const ['Pokemon', 'Lorcana', 'One Piece'])
                  CheckboxListTile(
                    title: Text(game),
                    value: games.contains(game),
                    onChanged: (_) => toggle(games, game),
                  ),
                const Text('Language'),
                for (final language in const ['English', 'Japanese'])
                  CheckboxListTile(
                    title: Text(language),
                    value: languages.contains(language),
                    onChanged: (_) => toggle(languages, language),
                  ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        ref.read(collectionControllerProvider.notifier).clearFilters();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () {
                        ref.read(collectionControllerProvider.notifier).applySortAndFilters(
                              sort: sort,
                              games: games,
                              languages: languages,
                            );
                        Navigator.of(context).pop();
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _sortLabel(CollectionSort sort) {
  return switch (sort) {
    CollectionSort.newest => 'Newest',
    CollectionSort.valueDesc => 'Value high to low',
    CollectionSort.changeDesc => '30D gain high to low',
    CollectionSort.nameAsc => 'Name A-Z',
  };
}
```

- [ ] **Step 4: Format and run Collection page tests**

Run from `apps/flutter-app`:

```powershell
dart format lib/features/collection test/widget/collection_page_test.dart
flutter test test/widget/collection_page_test.dart
```

Expected result: PASS.

- [ ] **Step 5: Rerun controller tests**

Run from `apps/flutter-app`:

```powershell
flutter test test/collection_controller_test.dart
```

Expected result: PASS.

- [ ] **Step 6: Commit Task 2**

```powershell
git add apps/flutter-app/lib/features/collection/collection_page.dart apps/flutter-app/test/widget/collection_page_test.dart
git commit -m "feat: add Collection page UI"
```

---

### Task 3: Route Collection and Update Navigation Boundaries

**Files:**
- Modify: `apps/flutter-app/lib/app/router.dart`
- Modify: `apps/flutter-app/lib/features/home/home_page.dart`
- Modify: `apps/flutter-app/test/widget/home_page_test.dart`
- Modify: `apps/flutter-app/test/widget/collection_page_test.dart`

- [ ] **Step 1: Write failing route/navigation tests**

In `apps/flutter-app/test/widget/home_page_test.dart`, change the unfinished tab test to prove Collection navigates:

```dart
testWidgets('Collection bottom tab navigates to Collection page', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: _HomeTestAppWithRoutes()));

  await tester.tap(find.text('Collection'));
  await tester.pumpAndSettle();

  expect(find.text('Collection'), findsOneWidget);
  expect(find.text('Portfolio'), findsWidgets);
  expect(find.text('This section is coming soon.'), findsNothing);
});
```

Update `_HomeTestAppWithRoutes` routes:

```dart
GoRoute(path: '/collection', builder: (context, state) => const CollectionPage()),
```

Add import:

```dart
import 'package:kando_app/features/collection/collection_page.dart';
```

In `apps/flutter-app/test/widget/collection_page_test.dart`, add routed navigation coverage:

```dart
testWidgets('Collection bottom navigation can return Home and Profile', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: _CollectionTestAppWithRoutes()));

  await tester.tap(find.text('Home'));
  await tester.pumpAndSettle();
  expect(find.text('Overview'), findsOneWidget);

  await tester.tap(find.text('Collection'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Profile'));
  await tester.pumpAndSettle();
  expect(find.text('Guest session'), findsOneWidget);
});
```

Add routed test app:

```dart
class _CollectionTestAppWithRoutes extends StatelessWidget {
  const _CollectionTestAppWithRoutes();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/collection',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomePage()),
          GoRoute(path: '/collection', builder: (context, state) => const CollectionPage()),
          GoRoute(path: '/profile', builder: (context, state) => const ProfilePage()),
        ],
      ),
    );
  }
}
```

Add imports:

```dart
import 'package:go_router/go_router.dart';
import 'package:kando_app/features/home/home_page.dart';
import 'package:kando_app/features/profile/profile_page.dart';
```

- [ ] **Step 2: Run affected widget tests and confirm route failures**

Run from `apps/flutter-app`:

```powershell
flutter test test/widget/home_page_test.dart
flutter test test/widget/collection_page_test.dart
```

Expected result: FAIL because app router/Home navigation do not yet include `/collection`.

- [ ] **Step 3: Update app router**

Modify `apps/flutter-app/lib/app/router.dart`:

```dart
import '../features/collection/collection_page.dart';
```

Add the route after `/`:

```dart
GoRoute(
  path: '/collection',
  builder: (context, state) => const CollectionPage(),
),
```

- [ ] **Step 4: Update Home bottom navigation**

In `apps/flutter-app/lib/features/home/home_page.dart`, change `onDestinationSelected`:

```dart
onDestinationSelected: (index) {
  if (index == 1) {
    context.go('/collection');
    return;
  }
  if (index == 4) {
    context.go('/profile');
    return;
  }
  if (index != 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This section is coming soon.')),
    );
  }
},
```

- [ ] **Step 5: Format and run affected tests**

Run from `apps/flutter-app`:

```powershell
dart format lib/app/router.dart lib/features/home/home_page.dart test/widget/home_page_test.dart test/widget/collection_page_test.dart
flutter test test/widget/home_page_test.dart
flutter test test/widget/collection_page_test.dart
```

Expected result: PASS.

- [ ] **Step 6: Commit Task 3**

```powershell
git add apps/flutter-app/lib/app/router.dart apps/flutter-app/lib/features/home/home_page.dart apps/flutter-app/test/widget/home_page_test.dart apps/flutter-app/test/widget/collection_page_test.dart
git commit -m "feat: route Collection tab"
```

---

### Task 4: Final Verification and Status Update

**Files:**
- Modify: `docs/superpowers/execution-status.md` via task status hook.

- [ ] **Step 1: Run focused Flutter tests**

Run from `apps/flutter-app`:

```powershell
flutter test test/collection_controller_test.dart
flutter test test/widget/collection_page_test.dart
flutter test test/widget/home_page_test.dart
```

Expected result: all pass.

- [ ] **Step 2: Run all Flutter tests**

Run from repository root:

```powershell
dart run melos run test
```

Expected result: all Flutter workspace tests pass.

- [ ] **Step 3: Run Flutter analysis**

Run from `apps/flutter-app`:

```powershell
flutter analyze
```

Expected result: no analysis issues.

- [ ] **Step 4: Check formatting**

Run from `apps/flutter-app`:

```powershell
dart format --set-exit-if-changed lib test
```

Expected result: exit code 0.

- [ ] **Step 5: Confirm no forbidden files changed**

Run from repository root:

```powershell
git diff --name-only HEAD
```

Expected changed paths are limited to:

```text
apps/flutter-app/lib/app/router.dart
apps/flutter-app/lib/features/home/home_page.dart
apps/flutter-app/lib/features/collection/*
apps/flutter-app/test/collection_controller_test.dart
apps/flutter-app/test/widget/collection_page_test.dart
apps/flutter-app/test/widget/home_page_test.dart
docs/superpowers/execution-status.md
```

If any `apps/admin-web/**`, `apps/workers-api/src/db/**`, migration, `wrangler.toml`, `drizzle.config.ts`, or `docs/tcg-card/**` file appears, stop and inspect before continuing.

- [ ] **Step 6: Stop the task status hook after validation passes**

Run from repository root with UTF-8-safe PowerShell input:

```powershell
$json = '{"summary":"[M4-2] Implement Collection page"}'
$json | python .claude\hooks\task_status.py stop
```

Expected result: `docs/superpowers/execution-status.md` records M4-2 as completed only after validation passes.

- [ ] **Step 7: Review final diff**

Run from repository root:

```powershell
git status --short --branch
git diff --stat
git diff --check
```

Expected result:

- M4-2 Flutter files and `docs/superpowers/execution-status.md` are the only changed files.
- `git diff --check` reports no whitespace errors. CRLF warnings must be called out if present.

- [ ] **Step 8: Commit Task 4**

```powershell
git add apps/flutter-app docs/superpowers/execution-status.md
git commit -m "feat: implement M4 Collection page"
```

## Self-Review Checklist

- Spec coverage:
  - `/collection` route: Task 3.
  - Home bottom navigation enters Collection: Task 3.
  - Portfolio/Wishlist tabs: Task 2.
  - Folder-scoped Portfolio: Tasks 1 and 2.
  - Wishlist independent from folder: Task 1.
  - Search: Tasks 1 and 2.
  - Sort/filter: Tasks 1 and 2.
  - Amount hiding: Tasks 1 and 2.
  - Portfolio/Wishlist/no-match empty states: Tasks 1 and 2.
  - No M7/admin/schema/docs-tcg changes: Task 4.
  - Validation and hook stop: Task 4.
- Placeholder scan: no banned placeholder markers or vague unexpanded steps.
- Type consistency:
  - `CollectionTab`, `CollectionSort`, `CollectionFolder`, `CollectionItem`, `CollectionDashboard`, `CollectionState`, `CollectionViewItem`, and `CollectionSummary` are defined before use.
  - Route paths are consistently `/`, `/collection`, and `/profile`.
  - Widget tests import the pages they route to.
