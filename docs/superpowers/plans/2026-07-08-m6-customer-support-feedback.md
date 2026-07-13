# M6-3 Customer Support Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M6-3 so Flutter users can submit Customer Support feedback with validation, optional Type/Function chips, success Toast, and return-to-Profile behavior.

**Architecture:** Add a Profile-local feedback page and repository interface. Keep submission mock-first via `LocalFeedbackRepository`; do not touch Workers, D1 schema, admin web, or `docs/tcg-card/**`.

**Tech Stack:** Flutter, Dart, Riverpod, go_router, Material widgets, widget tests.

---

## Constraints

- Do not modify `docs/tcg-card/**`.
- Do not modify `apps/admin-web/**` or M7/Admin code.
- Do not modify Workers schema, migrations, `wrangler.toml`, or `drizzle.config.ts`.
- Do not implement the Workers `POST /feedbacks` route in this slice.
- Do not include `Subscription` as a Function option.
- Use TDD and do not run Flutter tests concurrently.

## Task 1: Customer Support Happy Path Test

**Files:**
- Modify: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [ ] **Step 1: Add failing happy-path widget test**

Add a `FeedbackRepository` test double override and a test that:

```dart
testWidgets('customer support submits signed-in feedback and returns to Profile', (tester) async {
  final authRepository = _WidgetAuthRepository(initialSession: _userSession());
  final feedbackRepository = _WidgetFeedbackRepository();

  await tester.pumpWidget(_testApp(authRepository, feedbackRepository: feedbackRepository));
  await tester.pumpAndSettle();
  await _openProfileTab(tester);
  await tester.tap(find.text('Customer Support'));
  await tester.pumpAndSettle();

  expect(find.text('Customer Support'), findsOneWidget);
  expect(find.text('Bug Report'), findsOneWidget);
  expect(find.text('Feature Request'), findsOneWidget);
  expect(find.text('Improvement'), findsOneWidget);
  expect(find.text('Other'), findsWidgets);
  expect(find.text('Subscription'), findsNothing);
  expect(find.widgetWithText(TextFormField, 'person@example.com'), findsOneWidget);

  await tester.tap(find.text('Bug Report'));
  await tester.tap(find.text('Search'));
  await tester.enterText(find.byKey(const ValueKey('feedback-message-field')), 'Prices look stale.');
  await tester.tap(find.widgetWithText(FilledButton, 'Submit Feedback'));
  await tester.pumpAndSettle();

  expect(feedbackRepository.submissions, [
    const _FeedbackSubmissionRecord(
      email: 'person@example.com',
      types: ['Bug Report'],
      functions: ['Search'],
      message: 'Prices look stale.',
    ),
  ]);
  expect(find.text('Feedback submitted. Thank you.'), findsOneWidget);
  expect(find.text('Profile'), findsOneWidget);
});
```

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart --name "customer support submits signed-in feedback and returns to Profile"
```

Expected: FAIL because the route, page, and repository do not exist yet.

## Task 2: Customer Support Validation Test

**Files:**
- Modify: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [ ] **Step 1: Add failing validation widget test**

Add a guest-state validation test that verifies:

- opening Customer Support leaves email empty
- submit with empty email shows `Please enter your email.`
- invalid email shows `Please enter a valid email address.`
- valid email with empty message shows `Please enter your feedback.`
- a 1001-character message shows `Message must be 1000 characters or less.`
  and disables `Submit Feedback`

- [ ] **Step 2: Run RED**

```powershell
cd apps/flutter-app
flutter test test/widget/auth_profile_test.dart --name "customer support validates guest feedback before submit"
```

Expected: FAIL because validation UI does not exist yet.

## Task 3: Implement Repository And Page

**Files:**
- Create: `apps/flutter-app/lib/features/profile/feedback_repository.dart`
- Create: `apps/flutter-app/lib/features/profile/customer_support_page.dart`
- Modify: `apps/flutter-app/lib/app/router.dart`
- Modify: `apps/flutter-app/lib/features/profile/profile_page.dart`

- [ ] **Step 1: Add feedback repository**

Create a Riverpod provider and local placeholder implementation. The repository
stores the request shape and returns a local receipt.

- [ ] **Step 2: Add Customer Support page**

Use `ConsumerStatefulWidget`, local form state, `FilterChip` for multi-select
Type/Function fields, email/message `TextFormField`s, and a disabled submit
button for messages over 1000 characters.

- [ ] **Step 3: Wire route and Profile entry**

Register `/customer-support` and make the Profile entry push that route.

- [ ] **Step 4: Run GREEN**

```powershell
cd apps/flutter-app
dart format lib/features/profile/feedback_repository.dart lib/features/profile/customer_support_page.dart lib/app/router.dart lib/features/profile/profile_page.dart test/widget/auth_profile_test.dart
flutter test test/widget/auth_profile_test.dart --name "customer support"
```

Expected: PASS for both Customer Support widget tests.

## Task 4: Verify And Complete Status

**Files:**
- Modify: `docs/superpowers/execution-status.md`

- [ ] **Step 1: Run focused tests**

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
cmd /c "echo [M6-3] Implement Customer Support feedback submission| python .claude\hooks\task_status.py stop"
```

- [ ] **Step 4: Commit and push**

```powershell
git add apps/flutter-app/lib/features/profile apps/flutter-app/lib/app/router.dart apps/flutter-app/test/widget/auth_profile_test.dart docs/superpowers/execution-status.md docs/superpowers/specs/2026-07-08-m6-customer-support-feedback-design.md docs/superpowers/plans/2026-07-08-m6-customer-support-feedback.md
git commit -m "feat: add Customer Support feedback submission"
git push origin codex/m2-data-adapter
```
