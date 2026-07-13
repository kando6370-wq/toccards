# M6-6 Subscription Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M6-6 by proving Flutter has no subscription-related visible UI and adding a regression test that guards the Profile/Account/Customer Support surfaces.

**Architecture:** Keep production Flutter code unchanged unless the regression test or source scan finds subscription UI. Add widget-level coverage in the existing Profile test suite because the relevant surfaces already live there.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, widget tests, ripgrep source scans.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not add subscription stubs, placeholders, or future-facing restore UI.
- Do not run Flutter tests concurrently.

## Task 1: Source Scan

**Files:**
- Inspect: `apps/flutter-app/lib/**`

- [x] **Step 1: Scan for subscription terms**

```powershell
rg -n -i "Upgrade to Pro|Subscribe|Subscription|PRO\b|Unlock All|Go unlock|Restore|premium|billing" apps/flutter-app/lib
```

Expected: no subscription UI matches. Internal auth restore helpers are allowed
false positives; remove or hide only matching visible subscription UI.

## Task 2: Add Regression Test

**Files:**
- Modify: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [x] **Step 1: Add subscription absence widget test**

Add a test that opens guest Profile, signed-in Profile, Account, and Customer
Support, then asserts these strings are absent:

```dart
const subscriptionCopy = [
  'Upgrade to Pro',
  'Subscribe',
  'Subscription',
  'PRO',
  'Unlock All',
  'Go unlock',
  'Restore',
];

for (final copy in subscriptionCopy) {
  expect(find.text(copy), findsNothing);
}
```

- [x] **Step 2: Run the regression test**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart --name "subscription"
```

Expected: PASS. If it fails, remove the visible subscription UI and rerun.

## Task 3: Verify And Complete Status

**Files:**
- Modify: `docs/superpowers/execution-status.md`

- [x] **Step 1: Run focused Flutter tests**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart
```

Expected: command passes.

- [x] **Step 2: Run full Flutter verification**

```powershell
flutter pub get
dart run melos run test
cd apps/flutter-app
flutter analyze
dart format --set-exit-if-changed lib test
```

Expected: all commands exit 0.

- [x] **Step 3: Stop status hook**

```powershell
cmd /c "echo [M6-6] Verify subscription surfaces hidden before M7 admin.| python .claude\hooks\task_status.py stop"
```

- [x] **Step 4: Commit and push**

```powershell
git add apps/flutter-app/test/widget/auth_profile_test.dart docs/superpowers/execution-status.md docs/superpowers/specs/2026-07-08-m6-subscription-removal-design.md docs/superpowers/plans/2026-07-08-m6-subscription-removal.md
git commit -m "test: guard subscription removal"
git push origin codex/m2-data-adapter
```
