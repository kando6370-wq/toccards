# M6-4 Onboarding Design

## Scope

Build the Flutter first-launch onboarding slice before M7/Admin work begins.
On first app startup, users see onboarding pages sourced through an
`app_config.onboarding_images`-shaped repository. After Skip or Get Started,
the app enters Home. Subsequent startups with the same local storage skip
onboarding.

This slice is Flutter-only. It does not add Workers routes, does not change D1
schema or migrations, does not touch admin web, and does not modify
`docs/tcg-card/**`.

## Existing State

`KandoApp` uses `MaterialApp.router` and the root route `/` renders `HomePage`.
There is no onboarding feature, no app-config client, and no durable local
preference package in the Flutter app. Existing unfinished integrations use
small Riverpod providers and local placeholder repositories.

## Recommended Approach

Add a small `features/onboarding` module:

- `onboarding_repository.dart` defines `OnboardingSlide`,
  `OnboardingRepository`, and an in-memory local implementation.
- `onboarding_controller.dart` reads slides and completion state from the
  repository and marks onboarding complete.
- `onboarding_page.dart` renders a PageView with image URL support and
  fallback placeholders.
- `onboarding_gate.dart` wraps the root route: show onboarding when incomplete,
  otherwise show Home.

The local repository returns placeholder slide URLs today, but the public
interface is shaped so a future app-config-backed repository can replace it
without changing the page.

## Alternatives Considered

1. Implement a real `GET /app-config` client now. This is more complete but
   crosses into backend/config work that belongs with M7/M8 and risks conflict
   with the admin worktree.
2. Add `shared_preferences` now. It would make completion durable across process
   restarts, but introduces dependency churn for a mock-first slice. The current
   app already uses in-memory storage for auth placeholders.
3. Put onboarding logic directly in `router.dart`. This is fewer files, but it
   makes route setup own feature state. A tiny feature module matches the
   existing repository/provider pattern and keeps the root route simple.

The selected approach satisfies M6-4 with the smallest Flutter-only surface.

## Behavior

On first startup:

- `/` renders onboarding instead of Home.
- Each slide shows an image area, title, and body.
- `Skip` marks onboarding complete from any slide and enters Home.
- `Next` advances pages.
- The final page shows `Get Started`, marks onboarding complete, and enters
  Home.

When completion is already stored, `/` renders Home immediately.

If a configured image URL fails to load, the page keeps the slide visible with a
local placeholder and does not show a Toast.

## Testing

Use TDD:

- Update the startup widget test so onboarding appears before Home, completing
  it enters Home, and the same storage skips onboarding on the next app startup.
- Add a focused widget test that overrides onboarding slides and verifies slide
  content is sourced from the repository.
- Run the new tests RED before adding production onboarding files.
- Implement only enough Flutter code to pass.
- Run focused tests, full Melos Flutter tests, `flutter analyze`, and Dart
  formatting before marking `[M6-4]` complete.
