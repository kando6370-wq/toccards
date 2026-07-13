# M5 CardDetail Uncollected State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build M5-1 so Search results can open an uncollected CardDetail page with basic info, price overview, and quick Collect/Wishlist actions.

**Architecture:** Add a new `features/card_detail` Flutter feature with small model, repository, controller, and page files. Register `/cards/:cardId` in GoRouter and make Search card bodies navigate there while leaving existing quick-action buttons unchanged.

**Tech Stack:** Flutter, Dart, Riverpod `NotifierProvider.family`, GoRouter, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or any M7/Admin implementation.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Keep this slice mock-first; do not add real API clients.
- Do not implement owned Collection Item edit/delete, Price Tab charts, sold listing details, or Home refresh behavior in this task.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Add CardDetail Models, Repository, and Controller

**Files:**
- Create: `apps/flutter-app/lib/features/card_detail/card_detail_models.dart`
- Create: `apps/flutter-app/lib/features/card_detail/card_detail_repository.dart`
- Create: `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
- Create: `apps/flutter-app/test/card_detail_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Cover:
- `squirtle` loads as an uncollected card with PRD basic fields.
- selected currency changes the visible market price.
- missing price data displays `--` and `-/-`.
- quick Collect sets quantity to 1 and clears Wishlist.
- repository failure displays shared failure state and Refresh can recover.

Expected test shape:

```dart
test('uncollected detail exposes card identity and price overview', () {
  final container = ProviderContainer.test();
  addTearDown(container.dispose);

  final state = container.read(cardDetailControllerProvider('squirtle'));

  expect(state.isUnavailable, isFalse);
  expect(state.detail.name, 'Squirtle');
  expect(state.detail.game, 'Pokemon');
  expect(state.detail.setName, 'Mega Evolution Promos');
  expect(state.detail.identityLine, 'Promo #039');
  expect(state.detail.finish, 'Holofoil');
  expect(state.detail.language, 'English');
  expect(state.marketPriceText, r'$32.13');
  expect(state.changeText, '+4.76%');
  expect(state.detail.isCollected, isFalse);
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/card_detail_controller_test.dart
```

Expected: FAIL because `features/card_detail/*` does not exist.

- [ ] **Step 3: Implement minimal model and repository**

Create a model with these responsibilities:

```dart
enum CardDetailType { tcg, sports, sealed, other }

class CardMarketPrice {
  const CardMarketPrice({
    required this.label,
    required this.priceUsd,
    required this.previous30dPriceUsd,
  });

  final String label;
  final double? priceUsd;
  final double? previous30dPriceUsd;
}

class CardDetail {
  const CardDetail({
    required this.id,
    required this.type,
    required this.name,
    required this.game,
    required this.setName,
    required this.identityLine,
    required this.finish,
    required this.language,
    required this.quantity,
    required this.isWishlisted,
    required this.marketPrices,
  });

  final String id;
  final CardDetailType type;
  final String name;
  final String game;
  final String setName;
  final String identityLine;
  final String finish;
  final String language;
  final int quantity;
  final bool isWishlisted;
  final List<CardMarketPrice> marketPrices;

  bool get isCollected => quantity > 0;

  CardDetail copyWith({int? quantity, bool? isWishlisted}) {
    return CardDetail(
      id: id,
      type: type,
      name: name,
      game: game,
      setName: setName,
      identityLine: identityLine,
      finish: finish,
      language: language,
      quantity: quantity ?? this.quantity,
      isWishlisted: isWishlisted ?? this.isWishlisted,
      marketPrices: marketPrices,
    );
  }
}
```

Mock repository data must include at least:

- `squirtle`: uncollected, USD 32.13, previous 30D 30.67, Raw Near Mint row.
- `mystery-promo`: uncollected, missing price and missing previous price.

- [ ] **Step 4: Implement minimal controller**

Use provider family:

```dart
final cardDetailRepositoryProvider = Provider<CardDetailRepository>((ref) {
  return const MockCardDetailRepository();
});

final cardDetailControllerProvider =
    NotifierProvider.family<CardDetailController, CardDetailState, String>(
      CardDetailController.new,
    );
```

Controller behavior:

- `build()` loads by `cardId`.
- `refresh()` reloads by the same id.
- `quickCollect()` changes quantity to 1 and `isWishlisted` to false.
- `toggleWishlist()` toggles only when not collected.
- `marketPriceText` uses `CurrencyFormatter`.
- `changeText` uses `MarketChange`.
- repository errors create `CardDetailState.unavailable(cardId: cardId)`.

- [ ] **Step 5: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/card_detail test/card_detail_controller_test.dart
flutter test test/card_detail_controller_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add apps/flutter-app/lib/features/card_detail apps/flutter-app/test/card_detail_controller_test.dart
git commit -m "feat: add CardDetail uncollected state"
```

## Task 2: Add CardDetail Page and Route

**Files:**
- Create: `apps/flutter-app/lib/features/card_detail/card_detail_page.dart`
- Create: `apps/flutter-app/test/widget/card_detail_page_test.dart`
- Modify: `apps/flutter-app/lib/app/router.dart`

- [ ] **Step 1: Write failing widget tests**

Cover:
- `CardDetailPage(cardId: 'squirtle')` renders title, basic fields, market price, 30D change, `Collect`, and Wishlist button.
- The uncollected page does not show `Collection Item` or `Remove from Portfolio`.
- tapping `Collect` changes the visible action to `Collected`, shows `Qty: 1`, and clears a selected Wishlist state.
- unknown card id renders `No content available` and `Refresh`.

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/card_detail_page_test.dart
```

Expected: FAIL because the page does not exist.

- [ ] **Step 3: Implement page**

Build:

- `Scaffold` with `AppBar`
- back button using `context.pop()` when possible, otherwise `context.go('/search')`
- body with a non-network image stand-in block
- basic information rows
- Price overview section from `state.detail.marketPrices`
- `FilledButton` for `Collect` / `Collected`
- Wishlist `IconButton`
- failure state using `KandoFailureBlock(onRefresh: controller.refresh)`

Do not add a bottom navigation bar to CardDetail. It is a drill-in page.

- [ ] **Step 4: Register route**

In `apps/flutter-app/lib/app/router.dart`, import the page and add:

```dart
GoRoute(
  path: '/cards/:cardId',
  builder: (context, state) {
    return CardDetailPage(cardId: state.pathParameters['cardId'] ?? '');
  },
),
```

- [ ] **Step 5: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/app lib/features/card_detail test/widget/card_detail_page_test.dart
flutter test test/widget/card_detail_page_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add apps/flutter-app/lib/app/router.dart apps/flutter-app/lib/features/card_detail apps/flutter-app/test/widget/card_detail_page_test.dart
git commit -m "feat: add CardDetail uncollected page"
```

## Task 3: Wire Search Result Navigation

**Files:**
- Modify: `apps/flutter-app/lib/features/search/search_page.dart`
- Modify: `apps/flutter-app/test/widget/search_page_test.dart`

- [ ] **Step 1: Write failing Search route test**

Add a test that pumps `_SearchTestAppWithRoutes`, taps the `search-card-squirtle`
card body, and expects `Squirtle`, `Mega Evolution Promos`, `Price overview`, and
`Collect` on the detail page.

The test router must include:

```dart
GoRoute(
  path: '/cards/:cardId',
  builder: (context, state) {
    return CardDetailPage(cardId: state.pathParameters['cardId'] ?? '');
  },
),
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/search_page_test.dart
```

Expected: FAIL because tapping the card body does not navigate yet.

- [ ] **Step 3: Implement Search card navigation**

Wrap the card body in a tap target:

```dart
return Card(
  key: Key('search-card-${card.id}'),
  child: InkWell(
    onTap: () => context.go('/cards/${card.id}'),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: ...
    ),
  ),
);
```

Keep the existing Collect and Wishlist callbacks unchanged.

- [ ] **Step 4: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/search test/widget/search_page_test.dart
flutter test test/widget/search_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/search/search_page.dart apps/flutter-app/test/widget/search_page_test.dart
git commit -m "feat: open CardDetail from Search"
```

## Task 4: Final Verification and Status

- [ ] Run focused tests:

```powershell
cd apps/flutter-app
flutter test test/card_detail_controller_test.dart
flutter test test/widget/card_detail_page_test.dart
flutter test test/widget/search_page_test.dart
```

- [ ] Run full Flutter verification:

```powershell
flutter pub get
dart run melos run test
cd apps/flutter-app
flutter analyze
dart format --set-exit-if-changed lib test
```

- [ ] Stop hook:

```powershell
cmd /c "echo [M5-1] Implement CardDetail uncollected state| python .claude\hooks\task_status.py stop"
```

- [ ] Commit and push status:

```powershell
git add docs/superpowers/execution-status.md
git commit -m "docs: complete M5 CardDetail uncollected status"
git push origin codex/m2-data-adapter
```
