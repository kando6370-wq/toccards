# M5 CardDetail Price Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build M5-3 so CardDetail Price Tab exposes range-switchable price series, market prices, and sold listings with mock data.

**Architecture:** Extend the existing Flutter `features/card_detail` model, repository, controller, and page. Keep all data mock-first and local to CardDetail; do not add new dependencies, backend clients, database changes, or Admin code.

**Tech Stack:** Flutter, Dart, Riverpod `NotifierProvider.family`, Material widgets, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Keep this slice mock-first; do not add real API clients.
- Do not implement Collection Item edit/delete, Home refresh behavior, or public-data-unavailable specialty states.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Add Price Tab State

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_models.dart`
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_repository.dart`
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
- Modify: `apps/flutter-app/test/card_detail_controller_test.dart`

- [ ] **Step 1: Write failing controller tests**

Add tests:

```dart
test('price tab exposes default range series, market rows, and sold listings', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final state = container.read(cardDetailControllerProvider('charizard-ex'));

  expect(state.selectedPriceRange, CardPriceRange.thirty);
  expect(state.priceSeriesRows.last.dateLabel, 'Today');
  expect(state.priceSeriesRows.last.priceText, r'$780.00');
  expect(state.priceTabMarketRows.first.label, 'PSA 10');
  expect(state.priceTabMarketRows.first.changeText, startsWith('+'));
  expect(state.soldListingRows.first.platform, 'eBay');
  expect(state.soldListingRows.first.priceText, r'$780.00');
});

test('selecting a price range changes only the visible series rows', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  final provider = cardDetailControllerProvider('charizard-ex');

  container.read(provider.notifier).selectPriceRange(CardPriceRange.seven);
  final state = container.read(provider);

  expect(state.selectedPriceRange, CardPriceRange.seven);
  expect(state.priceSeriesRows.first.dateLabel, '7 days ago');
  expect(state.priceSeriesRows.last.priceText, r'$780.00');
  expect(state.priceTabMarketRows.first.label, 'PSA 10');
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/card_detail_controller_test.dart
```

Expected: FAIL because price ranges and derived Price Tab rows do not exist.

- [ ] **Step 3: Implement minimal model**

Add:

- `CardPriceRange` enum with `seven`, `thirty`, `ninety`, `oneEighty`, `year`.
- `CardPricePoint` with `dateLabel` and `priceUsd`.
- `CardSoldListing` with `dateText`, `title`, `priceUsd`, `platform`.
- `priceSeriesByRange` and `soldListings` fields on `CardDetail`.
- optional `previous7dPriceUsd` on `CardMarketPrice` for Price Tab change text.

- [ ] **Step 4: Add mock data**

For `charizard-ex`, add series data for all ranges and at least two sold listings.
For `squirtle`, add a smaller series and one sold listing. Existing mock cards
without series can keep empty lists.

- [ ] **Step 5: Implement controller derived rows**

Add:

- `selectedPriceRange` on `CardDetailState`, default `CardPriceRange.thirty`.
- `priceSeriesRows`, `priceTabMarketRows`, and `soldListingRows`.
- `selectPriceRange(CardPriceRange range)` on `CardDetailController`.

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
git commit -m "feat: add CardDetail price tab state"
```

## Task 2: Render Full Price Tab

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_page.dart`
- Modify: `apps/flutter-app/test/widget/card_detail_page_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add tests:

```dart
testWidgets('uncollected Price Tab renders series, market prices, and sold listings', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: _CardDetailTestApp(cardId: 'squirtle')),
  );

  await tester.scrollUntilVisible(find.text('Price overview'), 400);

  expect(find.text('Price range'), findsOneWidget);
  expect(find.text('30D'), findsOneWidget);
  expect(find.text('Market Prices'), findsOneWidget);
  expect(find.text('Sold listings'), findsOneWidget);
});

testWidgets('owned Price Tab range selector updates visible series rows', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: _CardDetailTestApp(cardId: 'charizard-ex')),
  );

  await tester.scrollUntilVisible(find.text('Price'), 400);
  await tester.tap(find.text('Price'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('7D'));
  await tester.pumpAndSettle();

  expect(find.text('7 days ago'), findsOneWidget);
  expect(find.text('Today'), findsOneWidget);
  expect(find.text('Sold listings'), findsOneWidget);
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/card_detail_page_test.dart
```

Expected: FAIL because the full Price Tab UI is not rendered yet.

- [ ] **Step 3: Implement Price Tab UI**

Replace the simple `_PriceOverview` internals with a full reusable Price Tab:

- `Price overview` heading.
- `Price range` segmented selector using all `CardPriceRange` values.
- `Price series` card/list from `state.priceSeriesRows`.
- `Market Prices` list from `state.priceTabMarketRows`.
- `Sold listings` list from `state.soldListingRows`.

Use the existing Material widgets and keep the owned tab container structure.

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
git commit -m "feat: render CardDetail price tab"
```

## Task 3: Final Verification and Status

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
cmd /c "echo [M5-3] Implement CardDetail Price Tab| python .claude\hooks\task_status.py stop"
```

- [ ] Commit and push status:

```powershell
git add docs/superpowers/execution-status.md
git commit -m "docs: complete M5 CardDetail Price Tab status"
git push origin codex/m2-data-adapter
```
