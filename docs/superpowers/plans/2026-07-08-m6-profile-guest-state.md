# M6 Profile Guest State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M6-1 so Flutter Profile guest state shows anonymous identity, guest actions, no logout, and `Version 1.0.0`.

**Architecture:** Keep the existing `ProfilePage` reading `authControllerProvider` directly. Add a small visible version footer and strengthen the existing widget test; do not introduce a Profile controller or any backend/API changes.

**Tech Stack:** Flutter, Dart, Riverpod, Material widgets, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not implement M6-2 logged-in Profile polish, M6-3 feedback submission, M6-4 onboarding, M6-5 delete flow changes, or M6-6 subscription cleanup in this slice.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Complete Profile Guest Footer

**Files:**
- Modify: `apps/flutter-app/lib/features/profile/profile_page.dart`
- Modify: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [ ] **Step 1: Write the failing widget test**

In `guest profile exposes account deletion through confirmation but not logout`,
add these expectations after `_openProfileTab(tester)`:

```dart
expect(find.text('Guest session'), findsOneWidget);
expect(find.text('anon-existing'), findsOneWidget);
```

Add this expectation with the other guest visible entries:

```dart
expect(find.text('Version 1.0.0'), findsOneWidget);
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart
```

Expected: FAIL because `Version 1.0.0` is not rendered on Profile.

- [ ] **Step 3: Implement minimal Profile footer**

In `apps/flutter-app/lib/features/profile/profile_page.dart`, add a file-level
constant near the imports:

```dart
const profileVersionText = 'Version 1.0.0';
```

At the bottom of `_ProfileContent`'s `ListView` children, after the guest delete
button block, add:

```dart
const SizedBox(height: 24),
Text(
  profileVersionText,
  style: Theme.of(context).textTheme.bodySmall,
),
```

Keep the existing `Sign in / Sign up`, support entries, policy entries, and
delete confirmation behavior unchanged.

- [ ] **Step 4: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/profile/profile_page.dart test/widget/auth_profile_test.dart
flutter test test/widget/auth_profile_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add apps/flutter-app/lib/features/profile/profile_page.dart apps/flutter-app/test/widget/auth_profile_test.dart
git commit -m "feat: complete Profile guest state"
```

## Task 2: Final Verification And Status

**Files:**
- Modify: `docs/superpowers/execution-status.md`

- [ ] **Step 1: Run focused regression tests**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart
flutter test test/auth_controller_test.dart
```

Expected: PASS for both focused tests.

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
cmd /c "echo [M6-1] Implement Profile guest state| python .claude\hooks\task_status.py stop"
```

- [ ] **Step 4: Commit and push status**

```powershell
git add docs/superpowers/execution-status.md
git commit -m "docs: complete M6 Profile guest state status"
git push origin codex/m2-data-adapter
```
