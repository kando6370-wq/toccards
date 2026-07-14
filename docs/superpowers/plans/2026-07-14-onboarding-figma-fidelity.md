# Startup Onboarding Figma Fidelity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the five-state first-launch flow as native Flutter UI matching Figma at 390 x 844 while preserving authentication and completion behavior.

**Architecture:** Keep the existing repository/controller/gate boundary. Add bundled visual assets and transient splash/page state inside `OnboardingPage`; reuse `showAuthSheet()` for authentication and complete onboarding only after a user session or explicit anonymous skip.

**Tech Stack:** Flutter, Riverpod, GoRouter, flutter_test, Figma MCP, Flutter Web browser verification

---

### Task 1: Lock First-Launch Intent in Tests

**Files:**
- Modify: `apps/flutter-app/test/widget/onboarding_page_test.dart`
- Modify: `apps/flutter-app/test/widget_test.dart`

- [ ] **Step 1: Add failing tests for splash and five-state navigation**

Add tests using `tester.view.physicalSize = const Size(390, 844)` and reset it with `addTearDown`. Assert `onboarding-splash` is initially present, remains before 1.2 seconds, then guide page 1 appears. Tap `Skip`, assert `onboarding-entry` appears and Home is still absent.

```dart
expect(find.byKey(const ValueKey('onboarding-splash')), findsOneWidget);
await tester.pump(const Duration(milliseconds: 1199));
expect(find.byKey(const ValueKey('onboarding-splash')), findsOneWidget);
await tester.pump(const Duration(milliseconds: 1));
await tester.pumpAndSettle();
expect(find.byKey(const ValueKey('onboarding-guide-0')), findsOneWidget);
await tester.tap(find.text('Skip'));
await tester.pumpAndSettle();
expect(find.byKey(const ValueKey('onboarding-entry')), findsOneWidget);
```

- [ ] **Step 2: Add failing tests for completion semantics**

Assert that `Skip and start now` persists completion and reveals Home. Assert opening and dismissing the Auth sheet does not mark storage complete.

```dart
await tester.tap(find.text('Sign in or create account'));
await tester.pumpAndSettle();
expect(find.text('Continue with Google'), findsOneWidget);
await tester.tapAt(const Offset(10, 10));
await tester.pumpAndSettle();
expect(storage.readCompleted(), isFalse);
```

- [ ] **Step 3: Run focused tests and confirm RED**

Run: `flutter test test/widget/onboarding_page_test.dart test/widget_test.dart`

Expected: FAIL because splash/entry keys and the final entry actions do not exist.

- [ ] **Step 4: Commit the RED tests**

```bash
git add apps/flutter-app/test/widget/onboarding_page_test.dart apps/flutter-app/test/widget_test.dart
git commit -m "test(flutter): define onboarding fidelity flow"
```

### Task 2: Add Bundled Onboarding Assets and State Model

**Files:**
- Create: `apps/flutter-app/assets/onboarding/`
- Modify: `apps/flutter-app/pubspec.yaml`
- Modify: `apps/flutter-app/lib/features/onboarding/onboarding_repository.dart`
- Test: `apps/flutter-app/test/widget/onboarding_page_test.dart`

- [ ] **Step 1: Export the splash background, logo, and three illustration layers**

Read the individual Figma child frames and use the checked-in SVGs only as source references. Store runtime assets under `assets/onboarding/` with semantic names and no baked-in buttons or text.

- [ ] **Step 2: Register the asset directory**

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/onboarding/
```

- [ ] **Step 3: Extend slide data without changing the repository contract**

Use bundled asset paths for defaults while retaining `imageUrl` for configured remote images.

```dart
const OnboardingSlide(
  imageUrl: 'asset://assets/onboarding/guide-collection.png',
  title: 'Track your collection',
  body: 'Keep your cards, folders, and wishlist organized in one place.',
)
```

- [ ] **Step 4: Run focused repository/widget tests**

Run: `flutter test test/widget/onboarding_page_test.dart`

Expected: still FAIL only on the missing page implementation, not asset registration.

- [ ] **Step 5: Commit assets and model changes**

```bash
git add apps/flutter-app/assets/onboarding apps/flutter-app/pubspec.yaml apps/flutter-app/lib/features/onboarding/onboarding_repository.dart
git commit -m "feat(flutter): add onboarding design assets"
```

### Task 3: Implement Splash, Guides, and Entry

**Files:**
- Modify: `apps/flutter-app/lib/features/onboarding/onboarding_page.dart`
- Test: `apps/flutter-app/test/widget/onboarding_page_test.dart`
- Test: `apps/flutter-app/test/widget_test.dart`

- [ ] **Step 1: Add transient presentation state**

In `initState`, wait for both a 1.2-second delay and the existing
`AuthController.startupComplete` future. Do not add a second auth
initialization path.

```dart
var _showSplash = true;

@override
void initState() {
  super.initState();
  unawaited(_finishSplash());
}

Future<void> _finishSplash() async {
  await Future.wait([
    Future<void>.delayed(const Duration(milliseconds: 1200)),
    ref.read(authControllerProvider.notifier).startupComplete,
  ]);
  if (mounted) setState(() => _showSplash = false);
}
```

- [ ] **Step 2: Build the native splash and guide composition**

Use stable aspect-ratio containers, Figma spacing, existing `KandoColors`, semantic keys, and explicit asset fallback. At 390 x 844 the content must match the individual Figma frames; at 320 x 700 it must scroll or compress without overflow.

- [ ] **Step 3: Add the final entry and Auth handoff**

Import `showAuthSheet`. Guide `Skip` sets the local page to entry. The primary action awaits the sheet, checks `authControllerProvider`, and completes only for a user session. The anonymous action calls `_complete()` directly.

```dart
await showAuthSheet(context);
if (!mounted) return;
if (ref.read(authControllerProvider).session?.isUser ?? false) {
  _complete();
}
```

- [ ] **Step 4: Run focused tests and confirm GREEN**

Run: `flutter test test/widget/onboarding_page_test.dart test/widget_test.dart`

Expected: PASS with no pending timers or overflow exceptions.

- [ ] **Step 5: Commit the implementation**

```bash
git add apps/flutter-app/lib/features/onboarding/onboarding_page.dart apps/flutter-app/test/widget/onboarding_page_test.dart apps/flutter-app/test/widget_test.dart
git commit -m "feat(flutter): rebuild startup onboarding flow"
```

### Task 4: Fidelity and Regression Gate

**Files:**
- Modify only files from Tasks 1-3 when evidence shows a mismatch

- [ ] **Step 1: Format and analyze**

Run: `dart format lib/features/onboarding test/widget/onboarding_page_test.dart test/widget_test.dart`

Run: `flutter analyze`

Expected: exit 0 with no errors.

- [ ] **Step 2: Run the complete Flutter test suite**

Run: `flutter test`

Expected: all tests pass; no tests are skipped.

- [ ] **Step 3: Capture all five states at 390 x 844**

Reload `http://127.0.0.1:3000/`, capture splash, guide pages 1-3, and entry, and compare each against its individual Figma frame. Check geometry, font weight, color, asset crop, safe area, pagination, and button states.

- [ ] **Step 4: Verify the 320 x 700 constraint**

Repeat the flow at 320 x 700 and confirm no clipped labels, overlapping controls, or Flutter overflow logs.

- [ ] **Step 5: Commit evidence-driven refinements**

```bash
git add apps/flutter-app/lib/features/onboarding apps/flutter-app/assets/onboarding apps/flutter-app/pubspec.yaml apps/flutter-app/test/widget/onboarding_page_test.dart apps/flutter-app/test/widget_test.dart
git commit -m "style(flutter): align onboarding with figma"
```
