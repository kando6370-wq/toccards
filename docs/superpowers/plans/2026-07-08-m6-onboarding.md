# M6-4 Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M6-4 so Flutter shows first-launch onboarding from an app-config-shaped local repository and skips it after completion.

**Architecture:** Add a small `features/onboarding` module with repository, controller, page, and root-route gate. Keep storage in memory for this mock-first slice; do not touch Workers, D1 schema, admin web, or `docs/tcg-card/**`.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, Material widgets, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not add a real app-config API client in this slice.
- Do not run Flutter tests concurrently.

## Task 1: Startup Onboarding RED Test

**Files:**
- Modify: `apps/flutter-app/test/widget_test.dart`

- [ ] **Step 1: Change the startup widget test**

Replace the old immediate-Home expectation with a test that:

```dart
testWidgets('KandoApp shows onboarding before the startup home page', (tester) async {
  final storage = InMemoryOnboardingStorage();

  await tester.pumpWidget(_testApp(storage));
  await tester.pumpAndSettle();

  expect(find.text('Track your collection'), findsOneWidget);
  expect(find.text('Overview'), findsNothing);

  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();

  expect(find.text('Overview'), findsOneWidget);
  expect(find.text('PORTFOLIO'), findsOneWidget);

  await tester.pumpWidget(_testApp(storage));
  await tester.pumpAndSettle();

  expect(find.text('Track your collection'), findsNothing);
  expect(find.text('Overview'), findsOneWidget);
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget_test.dart --name "KandoApp shows onboarding before the startup home page"
```

Expected: FAIL because onboarding storage, repository, and UI do not exist yet.

## Task 2: Configured Slides RED Test

**Files:**
- Create: `apps/flutter-app/test/widget/onboarding_page_test.dart`

- [ ] **Step 1: Add a focused widget test**

Add a test that overrides `onboardingRepositoryProvider` with two configured
slides and verifies the page renders the first slide, advances to the second
slide, and completes on `Get Started`.

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/onboarding_page_test.dart
```

Expected: FAIL because the onboarding module does not exist yet.

## Task 3: Minimal Onboarding Implementation

**Files:**
- Create: `apps/flutter-app/lib/features/onboarding/onboarding_repository.dart`
- Create: `apps/flutter-app/lib/features/onboarding/onboarding_controller.dart`
- Create: `apps/flutter-app/lib/features/onboarding/onboarding_page.dart`
- Create: `apps/flutter-app/lib/features/onboarding/onboarding_gate.dart`
- Modify: `apps/flutter-app/lib/app/router.dart`
- Modify: `apps/flutter-app/test/widget_test.dart`
- Create: `apps/flutter-app/test/widget/onboarding_page_test.dart`

- [ ] **Step 1: Add repository and storage**

Create `OnboardingSlide`, `InMemoryOnboardingStorage`,
`OnboardingRepository`, and `LocalOnboardingRepository` with local placeholder
slides.

- [ ] **Step 2: Add controller**

Create `OnboardingController` with `complete()` and state derived from the
repository.

- [ ] **Step 3: Add page and gate**

Render a PageView, image URL area with fallback placeholder, `Skip`, `Next`, and
`Get Started`. `OnboardingGate` shows onboarding until completion, then Home.

- [ ] **Step 4: Wire root route**

Change the `/` route builder to `OnboardingGate(home: HomePage())`.

- [ ] **Step 5: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/onboarding lib/app/router.dart test/widget_test.dart test/widget/onboarding_page_test.dart
flutter test test/widget_test.dart --name "KandoApp shows onboarding before the startup home page"
flutter test test/widget/onboarding_page_test.dart
```

Expected: both focused commands pass.

## Task 4: Verify And Complete Status

**Files:**
- Modify: `docs/superpowers/execution-status.md`

- [ ] **Step 1: Run focused Flutter tests**

```powershell
cd apps/flutter-app
flutter test test/widget_test.dart
flutter test test/widget/onboarding_page_test.dart
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
cmd /c "echo [M6-4] Implement onboarding mock-first before M7 admin.| python .claude\hooks\task_status.py stop"
```

- [ ] **Step 4: Commit and push**

```powershell
git add apps/flutter-app/lib/features/onboarding apps/flutter-app/lib/app/router.dart apps/flutter-app/test/widget_test.dart apps/flutter-app/test/widget/onboarding_page_test.dart docs/superpowers/execution-status.md docs/superpowers/specs/2026-07-08-m6-onboarding-design.md docs/superpowers/plans/2026-07-08-m6-onboarding.md
git commit -m "feat: add startup onboarding"
git push origin codex/m2-data-adapter
```
