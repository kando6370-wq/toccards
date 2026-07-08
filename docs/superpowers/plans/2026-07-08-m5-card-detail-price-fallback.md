# M5 CardDetail Price Fallback States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build M5-5 so CardDetail Price Tab shows explicit empty-data fallback copy while preserving existing `--` and `-/-` price fallbacks.

**Architecture:** Extend only the existing Flutter `features/card_detail` controller-derived state and page rendering. Keep `CardDetail` model and mock repository contracts unchanged; no backend clients, database changes, Admin code, or new dependencies.

**Tech Stack:** Flutter, Dart, Riverpod `NotifierProvider.family`, Material widgets, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Keep this slice mock-first and local to CardDetail.
- Do not add real API clients, chart dependencies, or section-level async loading.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Add Price Fallback State

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
- Modify: `apps/flutter-app/test/card_detail_controller_test.dart`

- [ ] **Step 1: Write the failing controller test**

Add this test after `missing price and change use CardDetail fallback copy`:

```dart
test('missing Price Tab data exposes section fallback state', () {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  final state = container.read(cardDetailControllerProvider('mystery-promo'));

  expect(state.priceTabMarketRows.single.label, 'Raw');
  expect(state.priceTabMarketRows.single.priceText, '--');
  expect(state.priceTabMarketRows.single.changeText, '-/-');
  expect(state.priceSeriesRows, isEmpty);
  expect(state.hasPriceSeriesRows, isFalse);
  expect(state.priceSeriesFallbackText, 'No price data available.');
  expect(state.soldListingRows, isEmpty);
  expect(state.hasSoldListingRows, isFalse);
  expect(state.soldListingsFallbackText, 'No sold listings available.');
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/card_detail_controller_test.dart
```

Expected: FAIL because `hasPriceSeriesRows`, `priceSeriesFallbackText`, `hasSoldListingRows`, and `soldListingsFallbackText` do not exist.

- [ ] **Step 3: Implement minimal controller fallback state**

In `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`, add
private constants near the existing validation copy:

```dart
const _priceSeriesFallbackText = 'No price data available.';
const _soldListingsFallbackText = 'No sold listings available.';
```

Inside `CardDetailState`, add these getters after `priceSeriesRows` and
`soldListingRows` respectively:

```dart
bool get hasPriceSeriesRows {
  return priceSeriesRows.isNotEmpty;
}

String get priceSeriesFallbackText {
  return _priceSeriesFallbackText;
}

bool get hasSoldListingRows {
  return soldListingRows.isNotEmpty;
}

String get soldListingsFallbackText {
  return _soldListingsFallbackText;
}
```

- [ ] **Step 4: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/card_detail test/card_detail_controller_test.dart
flutter test test/card_detail_controller_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/card_detail/card_detail_controller.dart apps/flutter-app/test/card_detail_controller_test.dart
git commit -m "feat: add CardDetail price fallback state"
```

## Task 2: Render Price Tab Empty Sections

**Files:**
- Modify: `apps/flutter-app/lib/features/card_detail/card_detail_page.dart`
- Modify: `apps/flutter-app/test/widget/card_detail_page_test.dart`

- [ ] **Step 1: Write the failing widget test**

Add this test after `uncollected CardDetail renders identity and price overview`:

```dart
testWidgets('Price Tab missing data renders fallback copy', (tester) async {
  await tester.pumpWidget(
    const ProviderScope(child: _CardDetailTestApp(cardId: 'mystery-promo')),
  );

  await tester.scrollUntilVisible(find.text('Price overview'), 400);

  expect(find.text('Price series'), findsOneWidget);
  expect(find.text('No price data available.'), findsOneWidget);
  expect(find.text('Market Prices'), findsOneWidget);
  expect(find.text('Raw'), findsWidgets);
  expect(find.text('--'), findsWidgets);
  expect(find.text('7D -/-'), findsOneWidget);
  expect(find.text('Sold listings'), findsOneWidget);
  expect(find.text('No sold listings available.'), findsOneWidget);
  expect(find.text(noContentAvailableText), findsNothing);
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/card_detail_page_test.dart
```

Expected: FAIL because the Price Tab currently renders no empty-state copy for missing series or sold listings.

- [ ] **Step 3: Implement minimal UI fallback rendering**

In `_PriceOverview.build`, replace the price-series `for` loop with:

```dart
if (state.hasPriceSeriesRows)
  for (final row in state.priceSeriesRows)
    Card(
      child: ListTile(
        title: Text(row.dateLabel),
        trailing: Text(row.priceText),
      ),
    )
else
  Text(state.priceSeriesFallbackText),
```

Replace the sold-listings `for` loop with:

```dart
if (state.hasSoldListingRows)
  for (final row in state.soldListingRows)
    Card(
      child: ListTile(
        title: Text(row.title),
        subtitle: Text('${row.dateText} - ${row.platform}'),
        trailing: Text(row.priceText),
      ),
    )
else
  Text(state.soldListingsFallbackText),
```

Do not change non-empty market row rendering.

- [ ] **Step 4: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/card_detail test/widget/card_detail_page_test.dart
flutter test test/widget/card_detail_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/card_detail/card_detail_page.dart apps/flutter-app/test/widget/card_detail_page_test.dart
git commit -m "feat: render CardDetail price fallback states"
```

## Task 3: Final Verification And Status

**Files:**
- Modify: `docs/superpowers/execution-status.md`

- [ ] **Step 1: Run focused tests**

```powershell
cd apps/flutter-app
flutter test test/card_detail_controller_test.dart
flutter test test/widget/card_detail_page_test.dart
flutter test test/widget/search_page_test.dart
```

Expected: PASS for all focused tests.

- [ ] **Step 2: Run full Flutter verification**

```powershell
flutter pub get
dart run melos run test
cd apps/flutter-app
flutter analyze
dart format --set-exit-if-changed lib test
```

Expected: all commands exit 0.

- [ ] **Step 3: Stop hook**

```powershell
cmd /c "echo [M5-5] Implement CardDetail price fallback states| python .claude\hooks\task_status.py stop"
```

- [ ] **Step 4: Commit and push status**

```powershell
git add docs/superpowers/execution-status.md
git commit -m "docs: complete M5 CardDetail price fallback status"
git push origin codex/m2-data-adapter
```
