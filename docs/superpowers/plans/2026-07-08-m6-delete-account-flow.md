# M6-5 Delete Account Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M6-5 so confirmed delete account actions call an explicit auth repository delete operation, return to guest Profile on success, and show the dedicated failure Toast without clearing account state on failure.

**Architecture:** Extend the existing Flutter auth repository/controller seam with `deleteCurrentAccount(AuthSession session)`. Keep the implementation local and mock-first; UI pages handle success routing and failure Toasts.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, Material widgets, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not implement a real Workers `DELETE /auth/account` client in this slice.
- Do not run Flutter tests concurrently.

## Task 1: Controller Delete RED Tests

**Files:**
- Modify: `apps/flutter-app/test/auth_controller_test.dart`

- [ ] **Step 1: Add failing controller tests**

Add tests that prove:

```dart
test('user delete calls repository delete and returns to a fresh guest', () async {
  final repository = _AuthRepository(
    initialSession: _userSession(),
    createdAnonymousIds: ['anon-after-delete'],
  );
  final container = _container(repository);
  addTearDown(container.dispose);

  await container.read(authControllerProvider.notifier).startupComplete;
  await container.read(authControllerProvider.notifier).deleteAccount();

  expect(repository.deletedSessions, [_userSession()]);
  expect(container.read(authControllerProvider).session?.anonymousId, 'anon-after-delete');
});

test('delete failure keeps current user state because account deletion did not complete', () async {
  final repository = _AuthRepository(
    initialSession: _userSession(),
    deleteError: Exception('delete failed'),
  );
  final container = _container(repository);
  addTearDown(container.dispose);

  await container.read(authControllerProvider.notifier).startupComplete;

  await expectLater(
    container.read(authControllerProvider.notifier).deleteAccount(),
    throwsException,
  );

  expect(container.read(authControllerProvider).session?.userId, 'user-1');
  expect(repository.createdAnonymousSessions, isEmpty);
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/auth_controller_test.dart --name "delete"
```

Expected: FAIL because `AuthRepository` has no semantic delete method yet.

## Task 2: Widget Delete RED Tests

**Files:**
- Modify: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [ ] **Step 1: Update and add widget tests**

Update the signed-in delete test to expect guest Profile after deletion:

```dart
expect(find.text('Guest session'), findsOneWidget);
expect(find.text('anon-after-delete'), findsOneWidget);
```

Add tests for:

- signed-in Account delete failure shows
  `Unable to complete this action. Please try again later.` and keeps Account
  details visible
- guest Profile delete failure shows the same Toast and keeps the old anonymous
  id visible

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart --name "delete"
```

Expected: FAIL because failure Toasts and Account success routing are not
implemented.

## Task 3: Minimal Delete Implementation

**Files:**
- Modify: `apps/flutter-app/lib/features/auth/auth_repository.dart`
- Modify: `apps/flutter-app/lib/features/auth/auth_controller.dart`
- Modify: `apps/flutter-app/lib/features/profile/account_page.dart`
- Modify: `apps/flutter-app/lib/features/profile/profile_page.dart`
- Modify: `apps/flutter-app/test/auth_controller_test.dart`
- Modify: `apps/flutter-app/test/widget/auth_profile_test.dart`
- Modify: `apps/flutter-app/test/widget_test.dart`

- [ ] **Step 1: Add repository delete method**

Add `Future<void> deleteCurrentAccount(AuthSession session);` to
`AuthRepository` and implement it in `LocalPlaceholderAuthRepository` by
clearing the matching local session.

- [ ] **Step 2: Update controller**

Call `deleteCurrentAccount(session)` before guest replacement. Preserve current
state if the repository throws.

- [ ] **Step 3: Update UI pages**

Catch delete errors in Profile and Account. Show
`Unable to complete this action. Please try again later.` via shared Toast.
Route Account success to `/profile`.

- [ ] **Step 4: Update test repositories**

Implement `deleteCurrentAccount` in widget and startup test doubles.

- [ ] **Step 5: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/auth lib/features/profile test/auth_controller_test.dart test/widget/auth_profile_test.dart test/widget_test.dart
flutter test test/auth_controller_test.dart --name "delete"
flutter test test/widget/auth_profile_test.dart --name "delete"
```

Expected: focused delete tests pass.

## Task 4: Verify And Complete Status

**Files:**
- Modify: `docs/superpowers/execution-status.md`

- [ ] **Step 1: Run focused Flutter tests**

```powershell
cd apps/flutter-app
flutter test test/auth_controller_test.dart
flutter test test/widget/auth_profile_test.dart
```

Expected: both commands pass.

- [ ] **Step 2: Run full Flutter verification**

```powershell
flutter pub get
dart run melos run test
cd apps/flutter-app
flutter analyze
dart format --set-exit-if-changed lib test
```

Expected: all commands exit 0.

- [ ] **Step 3: Stop status hook**

```powershell
cmd /c "echo [M6-5] Implement delete account flow mock-first before M7 admin.| python .claude\hooks\task_status.py stop"
```

- [ ] **Step 4: Commit and push**

```powershell
git add apps/flutter-app/lib/features/auth apps/flutter-app/lib/features/profile apps/flutter-app/test/auth_controller_test.dart apps/flutter-app/test/widget/auth_profile_test.dart apps/flutter-app/test/widget_test.dart docs/superpowers/execution-status.md docs/superpowers/specs/2026-07-08-m6-delete-account-flow-design.md docs/superpowers/plans/2026-07-08-m6-delete-account-flow.md
git commit -m "feat: complete delete account flow"
git push origin codex/m2-data-adapter
```
