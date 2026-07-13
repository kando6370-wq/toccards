# M4 Market Change Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement shared Flutter market change calculations and make Home, Collection, and Search use the same PRD formula and fallback display.

**Architecture:** Add a small shared market utility with pure Dart calculation and formatting helpers. Existing mock repositories will provide current and previous 30D prices/values, while controllers derive display text instead of storing precomputed percentages.

**Tech Stack:** Flutter, Dart, Riverpod controllers, Flutter unit/widget tests.

---

## Execution Constraints

- M4-4 has already been started in `docs/superpowers/execution-status.md`; do not rerun the start hook.
- Do not modify `docs/tcg-card/**`.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not modify `apps/admin-web` or M7/Admin code.
- Do not implement M4-5 currency conversion, M4-6 loading/failure states, or M4-7 Toast.
- Use TDD and do not run Flutter tests concurrently.

## File Structure

- Create: `apps/flutter-app/lib/shared/market/market_change.dart`
  - Pure Dart formula and display formatting.
- Create: `apps/flutter-app/test/market_change_test.dart`
  - Formula, fallback, tiny percentage, and quantity behavior.
- Modify Home:
  - `apps/flutter-app/lib/features/home/home_models.dart`
  - `apps/flutter-app/lib/features/home/home_repository.dart`
  - `apps/flutter-app/lib/features/home/home_controller.dart`
  - `apps/flutter-app/lib/features/home/home_page.dart`
  - `apps/flutter-app/test/home_controller_test.dart`
  - `apps/flutter-app/test/widget/home_page_test.dart`
- Modify Collection:
  - `apps/flutter-app/lib/features/collection/collection_models.dart`
  - `apps/flutter-app/lib/features/collection/collection_repository.dart`
  - `apps/flutter-app/lib/features/collection/collection_controller.dart`
  - `apps/flutter-app/test/collection_controller_test.dart`
  - `apps/flutter-app/test/widget/collection_page_test.dart`
- Modify Search:
  - `apps/flutter-app/lib/features/search/search_models.dart`
  - `apps/flutter-app/lib/features/search/search_repository.dart`
  - `apps/flutter-app/test/search_controller_test.dart`
  - `apps/flutter-app/test/widget/search_page_test.dart`
- Modify: `docs/superpowers/execution-status.md`
  - Stop hook after final verification.

---

### Task 1: Shared Market Change Utility

**Files:**
- Create: `apps/flutter-app/test/market_change_test.dart`
- Create: `apps/flutter-app/lib/shared/market/market_change.dart`

- [ ] **Step 1: Write failing utility tests**

Create `apps/flutter-app/test/market_change_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/market/market_change.dart';

void main() {
  test('calculates amount and percent from current and previous prices', () {
    final change = MarketChange.fromPrices(current: 120, previous: 100);

    expect(change.amount, 20);
    expect(change.percent, 20);
    expect(change.amountText, r'$20.00');
    expect(change.percentText, '+20.00%');
  });

  test('quantity changes amount but not percentage', () {
    final change = MarketChange.fromPrices(current: 120, previous: 100, quantity: 3);

    expect(change.amount, 60);
    expect(change.percent, 20);
    expect(change.amountText, r'$60.00');
    expect(change.percentText, '+20.00%');
  });

  test('missing or invalid previous price falls back loudly', () {
    for (final previous in <double?>[null, 0, -1]) {
      final change = MarketChange.fromPrices(current: 120, previous: previous);

      expect(change.amountText, '--');
      expect(change.percentText, '-/-');
    }
  });

  test('missing or invalid current price falls back loudly', () {
    for (final current in <double?>[null, 0, -1]) {
      final change = MarketChange.fromPrices(current: current, previous: 100);

      expect(change.currentValueText, '--');
      expect(change.amountText, '--');
      expect(change.percentText, '-/-');
    }
  });

  test('tiny non-zero percentage uses less-than display', () {
    final up = MarketChange.fromPrices(current: 100.004, previous: 100);
    final down = MarketChange.fromPrices(current: 99.996, previous: 100);

    expect(up.percentText, '<0.01%');
    expect(down.percentText, '-<0.01%');
  });
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run from `apps/flutter-app`:

```powershell
flutter test test/market_change_test.dart
```

Expected: FAIL because `shared/market/market_change.dart` does not exist.

- [ ] **Step 3: Add utility implementation**

Create `apps/flutter-app/lib/shared/market/market_change.dart` with:

- `MarketChange.fromPrices({double? current, double? previous, int quantity = 1})`.
- `currentValue = current * quantity` when current is positive.
- `amount = (current - previous) * quantity` only when both prices are positive.
- `percent = (current - previous) / previous * 100` only when both prices are positive.
- `currentValueText`, `amountText`, and `percentText`.
- Money formatting with two decimals and leading minus before `$`.
- Percent formatting with two decimals, `+` for positive, and tiny non-zero display.

- [ ] **Step 4: Format and run utility tests**

Run from `apps/flutter-app`:

```powershell
dart format lib/shared test/market_change_test.dart
flutter test test/market_change_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```powershell
git add apps/flutter-app/lib/shared/market/market_change.dart apps/flutter-app/test/market_change_test.dart
git commit -m "feat: add market change calculator"
```

---

### Task 2: Wire Home to Shared Calculation

**Files:**
- Modify: Home model/repository/controller/page/tests listed above.

- [ ] **Step 1: Update failing Home tests first**

Change Home tests so main portfolio percentage expects `+3.38%`, while amount remains `$420 in the last 30 days`. Add a test case where previous total value is zero and percent is `-/-`.

- [ ] **Step 2: Run Home tests and confirm failure**

Run from `apps/flutter-app`:

```powershell
flutter test test/home_controller_test.dart
flutter test test/widget/home_page_test.dart
```

Expected: FAIL because Home still uses stored one-decimal percentage.

- [ ] **Step 3: Update Home models and controller**

Add `previous30dValueUsd` to `HomePortfolio` and `previousPriceUsd` to `HomeHighlightCard` / `TrendingCard`. Use `MarketChange.fromPrices` in `HomeState.changeAmountText`, `HomeState.changePercentText`, and `_percentText` usage where possible.

- [ ] **Step 4: Format and run Home tests**

Run from `apps/flutter-app`:

```powershell
dart format lib/features/home test/home_controller_test.dart test/widget/home_page_test.dart
flutter test test/home_controller_test.dart
flutter test test/widget/home_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 2**

```powershell
git add apps/flutter-app/lib/features/home apps/flutter-app/test/home_controller_test.dart apps/flutter-app/test/widget/home_page_test.dart
git commit -m "feat: use market change calculator in Home"
```

---

### Task 3: Wire Collection and Search to Shared Calculation

**Files:**
- Modify Collection and Search files/tests listed above.

- [ ] **Step 1: Update failing Collection/Search tests first**

Update expected percent strings to two decimals:

- Collection first card: `+8.10%`.
- Search Squirtle: `+4.76%`.
- Search Charizard: `+8.10%`.

Keep missing Search card as `--` and `-/-`.

- [ ] **Step 2: Run affected tests and confirm failure**

Run from `apps/flutter-app`:

```powershell
flutter test test/collection_controller_test.dart
flutter test test/widget/collection_page_test.dart
flutter test test/search_controller_test.dart
flutter test test/widget/search_page_test.dart
```

Expected: FAIL because Collection and Search still use stored percentages or one-decimal formatting.

- [ ] **Step 3: Update Collection and Search models/repositories/controllers**

Replace `change30dPercent` mock fields with `previous30dPriceUsd`. Use previous values that preserve existing intended changes:

- Squirtle current `32.13`, previous `30.67`.
- Charizard current `780`, previous `721.58`.
- Collection Charizard current `780`, previous `721.55`.
- Missing cards use `previous30dPriceUsd: null`.

Use `MarketChange.fromPrices` for `changeText` in both modules.

- [ ] **Step 4: Format and run affected tests**

Run from `apps/flutter-app`:

```powershell
dart format lib/features/collection lib/features/search test/collection_controller_test.dart test/search_controller_test.dart test/widget/collection_page_test.dart test/widget/search_page_test.dart
flutter test test/collection_controller_test.dart
flutter test test/widget/collection_page_test.dart
flutter test test/search_controller_test.dart
flutter test test/widget/search_page_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit Task 3**

```powershell
git add apps/flutter-app/lib/features/collection apps/flutter-app/lib/features/search apps/flutter-app/test/collection_controller_test.dart apps/flutter-app/test/search_controller_test.dart apps/flutter-app/test/widget/collection_page_test.dart apps/flutter-app/test/widget/search_page_test.dart
git commit -m "feat: use market change calculator in Collection and Search"
```

---

### Task 4: Final Verification and Status Update

**Files:**
- Modify: `docs/superpowers/execution-status.md` via task status hook.

- [ ] **Step 1: Run focused tests**

Run from `apps/flutter-app`:

```powershell
flutter test test/market_change_test.dart
flutter test test/home_controller_test.dart
flutter test test/collection_controller_test.dart
flutter test test/search_controller_test.dart
flutter test test/widget/home_page_test.dart
flutter test test/widget/collection_page_test.dart
flutter test test/widget/search_page_test.dart
```

Expected: all pass.

- [ ] **Step 2: Run all Flutter tests**

Run from repository root:

```powershell
dart run melos run test
```

Expected: all Flutter workspace tests pass.

- [ ] **Step 3: Run analysis and format check**

Run from `apps/flutter-app`:

```powershell
flutter analyze
dart format --set-exit-if-changed lib test
```

Expected: no analysis issues and 0 changed files.

- [ ] **Step 4: Stop status hook**

Run from repository root:

```powershell
cmd /c "echo [M4-4] Implement market change algorithm| python .claude\hooks\task_status.py stop"
```

Scan status for hook encoding pollution:

```powershell
Select-String -Path docs\superpowers\execution-status.md -Pattern '锘|縶|\{\"summary\"'
```

Expected: no output.

- [ ] **Step 5: Review diff, commit, and push**

Run:

```powershell
git diff --name-only HEAD
git diff --check
git add apps/flutter-app docs/superpowers/execution-status.md
git commit -m "feat: implement M4 market change algorithm"
git push origin codex/m2-data-adapter
```

Expected changed paths stay within Flutter app and execution status only.

## Self-Review Checklist

- Formula from `global-rules.md §一` is represented in `MarketChange.fromPrices`.
- Quantity affects amount/current value, not percentage.
- Missing/zero/negative current or previous price falls back to `--` and `-/-`.
- Percent formatting uses two decimals and tiny non-zero display.
- Home, Collection, and Search all use shared calculation.
- No M4-5 currency conversion, M4-6 loading/failure, M4-7 Toast, M7/admin, schema, migration, or `docs/tcg-card/**` changes.
