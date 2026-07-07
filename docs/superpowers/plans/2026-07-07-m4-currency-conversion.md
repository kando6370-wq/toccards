# M4 Currency Conversion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shared mock currency conversion for Flutter and make Home and Collection render money in the selected currency.

**Architecture:** Introduce a small shared currency module with supported currencies, mock USD rates, formatting, and a Riverpod selected-currency provider. Home and Collection will call the shared formatter instead of private rate/symbol code. CardDetail is not implemented yet, so the shared utility becomes the future integration point.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter unit/widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not modify `apps/admin-web` or M7/Admin code.
- Do not implement M4-6 loading/failure, M4-7 Toast, or M5 CardDetail.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Shared Currency Utility

**Files:**
- Create: `apps/flutter-app/lib/shared/currency/currency.dart`
- Create: `apps/flutter-app/test/currency_test.dart`

- [ ] **Step 1: Write failing tests**

Cover:
- USD `$12,840.00`.
- EUR `€11,684.40` from USD 12,840 at rate 0.91.
- Negative amount `-€382.20`.
- Missing amount `--`.
- Hidden amount `••••••`.
- Supported currency codes exactly `USD, EUR, JPY, GBP, CAD, AUD, NZD, SGD`.

- [ ] **Step 2: Run RED**

Run from `apps/flutter-app`:

```powershell
flutter test test/currency_test.dart
```

Expected: FAIL because `shared/currency/currency.dart` does not exist.

- [ ] **Step 3: Implement utility**

Add `AppCurrency`, `MockCurrencyRates`, `CurrencyFormatter`, and `selectedCurrencyProvider`.

- [ ] **Step 4: Format and run utility test**

```powershell
dart format lib/shared test/currency_test.dart
flutter test test/currency_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/shared/currency/currency.dart apps/flutter-app/test/currency_test.dart
git commit -m "feat: add currency conversion helper"
```

## Task 2: Wire Home

**Files:**
- Modify: `apps/flutter-app/lib/features/home/home_controller.dart`
- Modify: `apps/flutter-app/lib/features/home/home_page.dart`
- Modify: `apps/flutter-app/test/home_controller_test.dart`
- Modify: `apps/flutter-app/test/widget/home_page_test.dart`

- [ ] **Step 1: Update failing Home tests**

Expect money with two decimals, PRD currencies in picker, EUR conversion, and unchanged percentages.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/home_controller_test.dart
flutter test test/widget/home_page_test.dart
```

- [ ] **Step 3: Implement Home wiring**

Read `selectedCurrencyProvider` in `HomeController.build`, remove private rate/symbol switch, and make the currency sheet list `AppCurrency.values`.

- [ ] **Step 4: Format and run Home tests**

```powershell
dart format lib/features/home test/home_controller_test.dart test/widget/home_page_test.dart
flutter test test/home_controller_test.dart
flutter test test/widget/home_page_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/home apps/flutter-app/test/home_controller_test.dart apps/flutter-app/test/widget/home_page_test.dart
git commit -m "feat: use shared currency conversion in Home"
```

## Task 3: Wire Collection

**Files:**
- Modify: `apps/flutter-app/lib/features/collection/collection_controller.dart`
- Modify: `apps/flutter-app/lib/features/collection/collection_page.dart`
- Modify: `apps/flutter-app/test/collection_controller_test.dart`
- Modify: `apps/flutter-app/test/widget/collection_page_test.dart`

- [ ] **Step 1: Update failing Collection tests**

Expect two-decimal USD money, EUR converted money when the shared provider is overridden or changed from Home, and unchanged percentages.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/collection_controller_test.dart
flutter test test/widget/collection_page_test.dart
```

- [ ] **Step 3: Implement Collection wiring**

Read `selectedCurrencyProvider` in `CollectionController.build` and format portfolio summary/list money with `CurrencyFormatter`.

- [ ] **Step 4: Format and run Collection tests**

```powershell
dart format lib/features/collection test/collection_controller_test.dart test/widget/collection_page_test.dart
flutter test test/collection_controller_test.dart
flutter test test/widget/collection_page_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/collection apps/flutter-app/test/collection_controller_test.dart apps/flutter-app/test/widget/collection_page_test.dart
git commit -m "feat: use shared currency conversion in Collection"
```

## Task 4: Final Verification and Status

- [ ] Run focused tests:

```powershell
flutter test test/currency_test.dart
flutter test test/home_controller_test.dart
flutter test test/collection_controller_test.dart
flutter test test/widget/home_page_test.dart
flutter test test/widget/collection_page_test.dart
```

- [ ] Run full verification:

```powershell
dart run melos run test
flutter analyze
dart format --set-exit-if-changed lib test
```

- [ ] Stop hook:

```powershell
cmd /c "echo [M4-5] Implement currency conversion display| python .claude\hooks\task_status.py stop"
```

- [ ] Commit and push:

```powershell
git add apps/flutter-app docs/superpowers/execution-status.md
git commit -m "feat: implement M4 currency conversion display"
git push origin codex/m2-data-adapter
```
