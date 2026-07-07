# M4 Scan Placeholder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the v1.0 Scan Tab placeholder page and wire bottom navigation to it.

**Architecture:** Add a small `ScanPage` under `features/scan`, register `/scan` in the app router, and route existing bottom Scan tabs to it. Keep the page static and mock-first; no camera or permissions are requested.

**Tech Stack:** Flutter, Dart, GoRouter, Flutter widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not modify `apps/admin-web` or M7/Admin code.
- Do not implement true scanning, camera permissions, camera preview, flash, recognition, batch scans, or review flow.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Add Scan Placeholder Page

**Files:**
- Create: `apps/flutter-app/lib/features/scan/scan_page.dart`
- Create: `apps/flutter-app/test/widget/scan_page_test.dart`

- [ ] **Step 1: Write failing Scan page tests**

Cover:
- `ScanPage` renders `扫描功能即将上线`, explanatory copy, and `Search Cards`.
- Tapping `Search Cards` navigates to Search and renders `Squirtle`.
- Bottom nav from Scan can open Home, Collection, Search, and Profile.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/widget/scan_page_test.dart
```

Expected: FAIL because `features/scan/scan_page.dart` does not exist.

- [ ] **Step 3: Implement Scan page**

Create `ScanPage` as a `ConsumerWidget` or `StatelessWidget` with:
- `Scaffold`
- centered body content
- headline `扫描功能即将上线`
- short English helper copy `Scan is coming soon. Use Search to find cards manually for now.`
- `FilledButton` labeled `Search Cards` that calls `context.go('/search')`
- `NavigationBar(selectedIndex: 2)` with Home / Collection / Scan / Search / Profile destinations
- destination handlers matching existing pages

- [ ] **Step 4: Format and run Scan page test**

```powershell
dart format lib/features/scan test/widget/scan_page_test.dart
flutter test test/widget/scan_page_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/scan apps/flutter-app/test/widget/scan_page_test.dart
git commit -m "feat: add Scan placeholder page"
```

## Task 2: Wire Scan Route and Bottom Tabs

**Files:**
- Modify: `apps/flutter-app/lib/app/router.dart`
- Modify: `apps/flutter-app/lib/features/home/home_page.dart`
- Modify: `apps/flutter-app/lib/features/collection/collection_page.dart`
- Modify: `apps/flutter-app/lib/features/search/search_page.dart`
- Modify: `apps/flutter-app/test/widget/home_page_test.dart`
- Modify: `apps/flutter-app/test/widget/collection_page_test.dart`
- Modify: `apps/flutter-app/test/widget/search_page_test.dart`

- [ ] **Step 1: Write failing route/page tests**

Update existing page tests:
- Home: tapping `Scan` bottom tab should render `扫描功能即将上线` instead of a Toast.
- Collection: tapping `Scan` bottom tab should render `扫描功能即将上线` instead of a Toast.
- Search: tapping `Scan` bottom tab should render `扫描功能即将上线`.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/widget/home_page_test.dart
flutter test test/widget/collection_page_test.dart
flutter test test/widget/search_page_test.dart
```

Expected: FAIL because `/scan` is not registered and bottom tabs still show a Toast.

- [ ] **Step 3: Wire route and navigation**

Add `ScanPage` import and route:

```dart
GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
```

Update Home / Collection / Search bottom navigation:

```dart
if (index == 2) {
  context.go('/scan');
  return;
}
```

Keep Search page scanner icon as coming-soon Toast because it is not the bottom Scan Tab.

- [ ] **Step 4: Format and run page tests**

```powershell
dart format lib/app lib/features/home lib/features/collection lib/features/search test/widget/home_page_test.dart test/widget/collection_page_test.dart test/widget/search_page_test.dart
flutter test test/widget/home_page_test.dart
flutter test test/widget/collection_page_test.dart
flutter test test/widget/search_page_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/app/router.dart apps/flutter-app/lib/features/home apps/flutter-app/lib/features/collection apps/flutter-app/lib/features/search apps/flutter-app/test/widget/home_page_test.dart apps/flutter-app/test/widget/collection_page_test.dart apps/flutter-app/test/widget/search_page_test.dart
git commit -m "feat: wire Scan tab navigation"
```

## Task 3: Final Verification and Status

- [ ] Run focused tests:

```powershell
flutter test test/widget/scan_page_test.dart
flutter test test/widget/home_page_test.dart
flutter test test/widget/collection_page_test.dart
flutter test test/widget/search_page_test.dart
```

- [ ] Run full verification:

```powershell
flutter pub get
dart run melos run test
flutter analyze
dart format --set-exit-if-changed lib test
```

- [ ] Stop hook:

```powershell
cmd /c "echo [M4-8] Implement Scan Tab placeholder| python .claude\hooks\task_status.py stop"
```

- [ ] Commit and push:

```powershell
git add docs/superpowers/execution-status.md
git commit -m "docs: complete M4 Scan placeholder status"
git push origin codex/m2-data-adapter
```
