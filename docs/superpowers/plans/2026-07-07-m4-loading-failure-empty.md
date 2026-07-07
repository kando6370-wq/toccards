# M4 Loading Failure Empty States Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shared Flutter loading/failure/empty UI and wire page-level failure + Refresh into Home, Collection, and Search.

**Architecture:** Add a small shared UI module with constants, a load status enum, and reusable loading/failure/empty widgets. Each existing synchronous mock controller catches repository load exceptions, exposes a failure state, and provides a `refresh()` method that reloads only that page. Existing successful empty states stay distinct from failures.

**Tech Stack:** Flutter, Dart, Riverpod, Flutter unit/widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not modify `apps/admin-web` or M7/Admin code.
- Do not implement M4-7 Toast or M4-8 Scan Tab.
- Keep repositories mock-first and synchronous for this task.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Shared Load State UI

**Files:**
- Create: `apps/flutter-app/lib/shared/ui/load_state.dart`
- Create: `apps/flutter-app/test/load_state_test.dart`

- [ ] **Step 1: Write failing tests**

Cover:
- `noContentAvailableText == 'No content available'`
- `refreshText == 'Refresh'`
- `KandoLoadingBlock` renders `CircularProgressIndicator`
- `KandoFailureBlock` renders `No content available`, `Refresh`, and calls `onRefresh`
- `KandoEmptyBlock` renders supplied title/body/action text

- [ ] **Step 2: Run RED**

```powershell
flutter test test/load_state_test.dart
```

Expected: FAIL because `shared/ui/load_state.dart` does not exist.

- [ ] **Step 3: Implement shared UI**

Create:

```dart
const noContentAvailableText = 'No content available';
const refreshText = 'Refresh';

enum KandoLoadStatus { loading, content, failure }
```

Add `KandoLoadingBlock`, `KandoFailureBlock`, and `KandoEmptyBlock` as small stateless widgets. Use `Card` only for local framed blocks; for full-page use, callers can center the same widgets.

- [ ] **Step 4: Format and run shared UI test**

```powershell
dart format lib/shared test/load_state_test.dart
flutter test test/load_state_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/shared/ui/load_state.dart apps/flutter-app/test/load_state_test.dart
git commit -m "feat: add shared load state widgets"
```

## Task 2: Wire Home Failure State

**Files:**
- Modify: `apps/flutter-app/lib/features/home/home_controller.dart`
- Modify: `apps/flutter-app/lib/features/home/home_page.dart`
- Modify: `apps/flutter-app/test/home_controller_test.dart`
- Modify: `apps/flutter-app/test/widget/home_page_test.dart`

- [ ] **Step 1: Write failing Home tests**

Add controller test with a repository that throws once, then succeeds:

```dart
class _FailingThenSuccessfulHomeRepository implements HomeRepository {
  var calls = 0;

  @override
  HomeDashboard loadDashboard() {
    calls += 1;
    if (calls == 1) {
      throw StateError('mock home unavailable');
    }
    return const MockHomeRepository().loadDashboard();
  }
}
```

Expect initial `state.loadStatus == KandoLoadStatus.failure`, `state.isUnavailable == true`, then `refresh()` restores `KandoLoadStatus.content` and `$12,840.00`.

Add widget test overriding the repository to fail first and assert `No content available`, `Refresh`, no blank page, and Refresh restores `Overview`.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/home_controller_test.dart
flutter test test/widget/home_page_test.dart
```

- [ ] **Step 3: Implement Home wiring**

Add `KandoLoadStatus loadStatus` and nullable `HomeDashboard? dashboard` to `HomeState`, guard content getters behind `dashboard!`, and add `bool get isUnavailable => loadStatus == KandoLoadStatus.failure`.

In `HomeController`, factor load into a private method:

```dart
HomeState _loadDashboard({AppCurrency? currency}) {
  final selectedCurrency = currency ?? ref.read(selectedCurrencyProvider);
  try {
    final dashboard = ref.read(homeRepositoryProvider).loadDashboard();
    return HomeState(... loadStatus: KandoLoadStatus.content, dashboard: dashboard);
  } catch (_) {
    return HomeState.unavailable(currency: selectedCurrency);
  }
}
```

Add `void refresh() { state = _loadDashboard(currency: state.currency); }`.

In `HomePage`, if `state.isUnavailable`, render a centered `KandoFailureBlock(onRefresh: controller.refresh)` inside the existing scaffold body and keep bottom navigation.

- [ ] **Step 4: Format and run Home tests**

```powershell
dart format lib/features/home test/home_controller_test.dart test/widget/home_page_test.dart
flutter test test/home_controller_test.dart
flutter test test/widget/home_page_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/home apps/flutter-app/test/home_controller_test.dart apps/flutter-app/test/widget/home_page_test.dart
git commit -m "feat: add Home loading failure state"
```

## Task 3: Wire Collection Failure State

**Files:**
- Modify: `apps/flutter-app/lib/features/collection/collection_controller.dart`
- Modify: `apps/flutter-app/lib/features/collection/collection_page.dart`
- Modify: `apps/flutter-app/test/collection_controller_test.dart`
- Modify: `apps/flutter-app/test/widget/collection_page_test.dart`

- [ ] **Step 1: Write failing Collection tests**

Add `_FailingThenSuccessfulCollectionRepository` that throws on first `loadDashboard()` and returns `MockCollectionRepository` data on second call.

Expect initial failure state, `refresh()` restores content, and existing successful empty/no-match tests still pass.

Widget test should assert `No content available`, `Refresh`, and after tapping `Refresh`, `Collection` and `$1,245.00` render.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/collection_controller_test.dart
flutter test test/widget/collection_page_test.dart
```

- [ ] **Step 3: Implement Collection wiring**

Mirror the Home pattern:
- Add `KandoLoadStatus loadStatus`.
- Make `CollectionDashboard? dashboard` nullable.
- Add `CollectionState.unavailable({required AppCurrency currency})`.
- Add `CollectionController.refresh()`.
- In `CollectionPage`, render `KandoFailureBlock(onRefresh: controller.refresh)` before normal content when unavailable.
- Replace `_MessageBlock` empty-state rendering with `KandoEmptyBlock` where it preserves existing titles and body copy.

- [ ] **Step 4: Format and run Collection tests**

```powershell
dart format lib/features/collection test/collection_controller_test.dart test/widget/collection_page_test.dart
flutter test test/collection_controller_test.dart
flutter test test/widget/collection_page_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/collection apps/flutter-app/test/collection_controller_test.dart apps/flutter-app/test/widget/collection_page_test.dart
git commit -m "feat: add Collection loading failure state"
```

## Task 4: Wire Search Failure State

**Files:**
- Modify: `apps/flutter-app/lib/features/search/search_controller.dart`
- Modify: `apps/flutter-app/lib/features/search/search_page.dart`
- Modify: `apps/flutter-app/test/search_controller_test.dart`
- Modify: `apps/flutter-app/test/widget/search_page_test.dart`

- [ ] **Step 1: Write failing Search tests**

Add `_FailingThenSuccessfulSearchRepository` that throws on first `loadCatalog()` and returns `MockSearchRepository` data on second call.

Expect initial failure state, `refresh()` restores `Pokemon` cards, and no-match search still displays `No matching results found.` rather than failure.

Widget test should assert `No content available`, `Refresh`, and after tapping `Refresh`, `Squirtle` renders.

- [ ] **Step 2: Run RED**

```powershell
flutter test test/search_controller_test.dart
flutter test test/widget/search_page_test.dart
```

- [ ] **Step 3: Implement Search wiring**

Mirror the page-level pattern:
- Add `KandoLoadStatus loadStatus`.
- Make `SearchCatalog? catalog` nullable.
- Add `SearchState.unavailable()`.
- Add `SearchController.refresh()`.
- In `SearchPage`, render `KandoFailureBlock(onRefresh: controller.refresh)` before search controls when unavailable.
- Use `KandoEmptyBlock(title: 'No matching results found.')` for no-match results.

- [ ] **Step 4: Format and run Search tests**

```powershell
dart format lib/features/search test/search_controller_test.dart test/widget/search_page_test.dart
flutter test test/search_controller_test.dart
flutter test test/widget/search_page_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/search apps/flutter-app/test/search_controller_test.dart apps/flutter-app/test/widget/search_page_test.dart
git commit -m "feat: add Search loading failure state"
```

## Task 5: Final Verification and Status

- [ ] Run focused tests:

```powershell
flutter test test/load_state_test.dart
flutter test test/home_controller_test.dart
flutter test test/collection_controller_test.dart
flutter test test/search_controller_test.dart
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
cmd /c "echo [M4-6] Implement loading failure empty states| python .claude\hooks\task_status.py stop"
```

- [ ] Commit and push:

```powershell
git add docs/superpowers/execution-status.md
git commit -m "docs: complete M4 loading failure empty status"
git push origin codex/m2-data-adapter
```
