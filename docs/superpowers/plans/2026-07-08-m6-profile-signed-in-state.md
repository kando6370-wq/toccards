# M6-2 Profile Signed-In State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M6-2 so Flutter Profile signed-in state exposes account identity, Account navigation, support/policy actions, logout, and the existing Account detail fields.

**Architecture:** Keep `ProfilePage` reading `authControllerProvider` directly. Reuse `AuthSession.email` and `AuthSession.userId`; do not add a Profile controller, backend call, database change, or admin surface.

**Tech Stack:** Flutter, Dart, Riverpod, Material widgets, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not add `displayName` until a real Flutter data source exists.
- Do not implement native rating, native sharing, or external policy links in this slice.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Cover Signed-In Profile Surface

**Files:**
- Modify: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [ ] **Step 1: Write the failing widget test**

In `user profile navigates to account details`, add these expectations before
tapping `Account`:

```dart
expect(find.text('Signed in'), findsOneWidget);
expect(find.text('person@example.com'), findsWidgets);
expect(find.text('ID: user-1'), findsOneWidget);
expect(find.text('Account'), findsOneWidget);
expect(find.text('Customer Support'), findsOneWidget);
expect(find.text('Score'), findsOneWidget);
expect(find.text('Share With Friends'), findsOneWidget);
expect(find.text('Terms Of Use'), findsOneWidget);
expect(find.text('Privacy Policy'), findsOneWidget);
expect(find.text('Log Out'), findsOneWidget);
expect(find.text('Sign in / Sign up'), findsNothing);
await tester.scrollUntilVisible(find.text('Version 1.0.0'), 200);
expect(find.text('Version 1.0.0'), findsOneWidget);
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart --name "user profile navigates to account details"
```

Expected: FAIL because `ID: user-1` and Profile-level `Log Out` are not rendered
before navigating to Account.

## Task 2: Render Signed-In Profile Details

**Files:**
- Modify: `apps/flutter-app/lib/features/profile/profile_page.dart`

- [ ] **Step 1: Implement minimal signed-in Profile UI**

In `_ProfileContent.build`, derive signed-in display values:

```dart
final emailText = session?.email ?? 'Unknown email';
final userIdText = session?.userId ?? 'Unknown user';
final identity = isUser ? emailText : (session?.anonymousId ?? 'Anonymous guest');
```

After the main identity `Text`, add the user id line only for user sessions:

```dart
if (isUser) ...[
  const SizedBox(height: 4),
  Text('ID: $userIdText', style: Theme.of(context).textTheme.bodyMedium),
],
```

After the policy entries and before the version footer, add Profile-level logout
for signed-in users while keeping guest delete unchanged:

```dart
if (isUser) ...[
  const SizedBox(height: 12),
  FilledButton(
    onPressed: () async {
      await ref.read(authControllerProvider.notifier).logout();
      if (context.mounted) {
        context.go('/');
      }
    },
    child: const Text('Log Out'),
  ),
] else ...[
  const SizedBox(height: 12),
  OutlinedButton(
    onPressed: () {
      _confirmAndDelete(context, ref);
    },
    child: const Text('Delete account'),
  ),
],
```

- [ ] **Step 2: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/profile/profile_page.dart test/widget/auth_profile_test.dart
flutter test test/widget/auth_profile_test.dart --name "user profile navigates to account details"
```

Expected: PASS.

## Task 3: Verify M6-2 Regression Surface

**Files:**
- Modify: `docs/superpowers/execution-status.md`

- [ ] **Step 1: Run focused Flutter tests**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart
flutter test test/auth_controller_test.dart
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
cmd /c "echo [M6-2] Implement Profile signed-in state| python .claude\hooks\task_status.py stop"
```

Expected: `docs/superpowers/execution-status.md` records M6-2 as completed only
after verification passes.

- [ ] **Step 4: Commit**

```powershell
git add apps/flutter-app/lib/features/profile/profile_page.dart apps/flutter-app/test/widget/auth_profile_test.dart docs/superpowers/execution-status.md docs/superpowers/specs/2026-07-08-m6-profile-signed-in-state-design.md docs/superpowers/plans/2026-07-08-m6-profile-signed-in-state.md
git commit -m "feat: complete Profile signed-in state"
```
