# M5 CardDetail Owned State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build M5-2 so CardDetail can show owned Collection Item records for Portfolio cards and switch to owned state after quick Collect.

**Architecture:** Extend the existing Flutter `features/card_detail` model, repository, controller, and page created in M5-1. Keep owned state local and mock-first; do not introduce backend API calls or shared Collection mutations in this slice.

**Tech Stack:** Flutter, Dart, Riverpod `NotifierProvider.family`, GoRouter, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Keep this slice mock-first; do not add real API clients.
- Do not implement Collection Item edit/delete, Price Tab charts, sold listing details, or Home refresh behavior.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Add Owned CardDetail State

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_models.dart`
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_repository.dart`
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
- Modify: `apps/flutter-app/test/card_detail_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Add tests for owned state and quick Collect owned transition:

```dart
test('owned detail exposes collection item rows', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final state = container.read(cardDetailControllerProvider('charizard-ex'));

  expect(state.detail.isCollected, isTrue);
  expect(state.detail.quantity, 1);
  expect(state.collectionItemRows.single.portfolioName, 'Main');
  expect(state.collectionItemRows.single.quantityText, 'Qty: 1');
  expect(state.collectionItemRows.single.statusText, 'PSA 10');
  expect(state.collectionItemRows.single.purchasePriceText, r'$650.00');
  expect(state.collectionItemRows.single.notes, contains('Obsidian Flames'));
});

test('quick Collect creates a default collection item and clears Wishlist', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final provider = cardDetailControllerProvider('one-piece-luffy');

  container.read(provider.notifier).quickCollect();
  final state = container.read(provider);

  expect(state.detail.isCollected, isTrue);
  expect(state.detail.isWishlisted, isFalse);
  expect(state.collectionItemRows.single.portfolioName, 'Main');
  expect(state.collectionItemRows.single.statusText, 'Raw / Near Mint');
  expect(state.collectionItemRows.single.purchasePriceText, '--');
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/card_detail_controller_test.dart
```

Expected: FAIL because `charizard-ex`, `collectionItemRows`, and owned item fields do not exist yet.

- [ ] **Step 3: Implement minimal owned model**

Add `CardCollectionItem` with:

- `id`
- `portfolioName`
- `quantity`
- `grader`
- `condition`
- `grade`
- `purchasePriceUsd`
- `notes`

Add `collectionItems` to `CardDetail`, update `isCollected` to use owned items,
and update `copyWith` so quick Collect can replace quantity, Wishlist state, and
collection items.

- [ ] **Step 4: Implement owned mock data and derived rows**

Add `charizard-ex` to `MockCardDetailRepository` with one owned item:

- portfolio `Main`
- quantity `1`
- grader `PSA`
- grade `10`
- purchase price `650`
- notes `Pulled from Obsidian Flames binder.`

Add `CardCollectionItemRow` in the controller with formatted quantity, status,
purchase price, and notes. `Raw` items should render `Raw / Near Mint`; graded
items should render `PSA 10`.

- [ ] **Step 5: Update quick Collect**

When quick Collect runs on an uncollected card, set quantity to `1`, clear
Wishlist, and attach one default item:

- portfolio `Main`
- grader `Raw`
- condition `Near Mint`
- purchase price `null`
- notes `Quick collected from CardDetail.`

- [ ] **Step 6: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/card_detail test/card_detail_controller_test.dart
flutter test test/card_detail_controller_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```powershell
git add apps/flutter-app/lib/features/card_detail apps/flutter-app/test/card_detail_controller_test.dart
git commit -m "feat: add CardDetail owned state"
```

## Task 2: Render Owned CardDetail UI

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_page.dart`
- Modify: `apps/flutter-app/test/widget/card_detail_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add tests that prove:

- `CardDetailPage(cardId: 'charizard-ex')` shows `Collection Item`, `Main`,
  `PSA 10`, `Purchase price`, `$650.00`, and notes.
- owned detail hides the Wishlist heart and does not show an enabled `Collect`
  action.
- tapping or selecting Price shows the existing `Price overview`.
- quick Collect on `one-piece-luffy` switches from uncollected UI to owned
  Collection Item content.

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/card_detail_page_test.dart
```

Expected: FAIL because owned Collection Item UI does not exist yet.

- [ ] **Step 3: Implement owned UI**

For collected cards:

- Show a share icon in the header instead of the Wishlist heart.
- Keep the `Collected` button disabled and show total quantity.
- Render a two-tab detail area with `Collection Item` first and `Price` second.
- In `Collection Item`, render one card per `collectionItemRows` with portfolio,
  quantity, status, purchase price, and notes.
- In `Price`, reuse `_PriceOverview`.

For uncollected cards, keep the M5-1 layout.

- [ ] **Step 4: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/card_detail test/widget/card_detail_page_test.dart
flutter test test/widget/card_detail_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/card_detail apps/flutter-app/test/widget/card_detail_page_test.dart
git commit -m "feat: render CardDetail owned items"
```

## Task 3: Verify Owned Entry from Search

**Files:**
- Modify: `apps/flutter-app/test/widget/search_page_test.dart`

- [ ] **Step 1: Write failing Search route test**

Add a test that pumps `_SearchTestAppWithRoutes`, taps `search-card-charizard-ex`,
and expects owned CardDetail content:

```dart
expect(find.text('Card Detail'), findsOneWidget);
expect(find.text('Charizard ex'), findsOneWidget);
expect(find.text('Collection Item'), findsOneWidget);
expect(find.text('Main'), findsOneWidget);
expect(find.text('PSA 10'), findsOneWidget);
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/search_page_test.dart
```

Expected: FAIL until the owned repository/page behavior is implemented.

- [ ] **Step 3: Keep Search code unchanged unless the test exposes a route gap**

Search already routes card bodies to `/cards/:cardId`. If the test fails because
the owned card data is missing, fix CardDetail data, not Search navigation.

- [ ] **Step 4: Run GREEN**

```powershell
cd apps/flutter-app
dart format test/widget/search_page_test.dart
flutter test test/widget/search_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/test/widget/search_page_test.dart
git commit -m "test: cover owned CardDetail from Search"
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
cmd /c "echo [M5-2] Implement CardDetail owned state| python .claude\hooks\task_status.py stop"
```

- [ ] Commit and push status:

```powershell
git add docs/superpowers/execution-status.md
git commit -m "docs: complete M5 CardDetail owned status"
git push origin codex/m2-data-adapter
```
