# M6-1 Profile Guest State Design

## Scope

Build the M6-1 Profile guest-state slice. The Profile page should show the
current anonymous account identity, provide the `Sign in / Sign up` entry point,
show the PRD support and policy entries, expose guest account deletion, hide
`Log Out`, and show `Version 1.0.0`.

This slice is Flutter-only and stays within the existing Profile/Auth UI. It
does not implement logged-in Profile polish, Account details changes, customer
support submission, onboarding, subscription cleanup, backend routes, database
changes, or M7/Admin work.

## Existing State

The current `ProfilePage` already renders most guest behavior:

- `Guest session`
- anonymous id text
- `Sign in / Sign up`
- `Customer Support`
- `Score`
- `Share With Friends`
- `Terms Of Use`
- `Privacy Policy`
- guest `Delete account` with confirmation
- no guest `Log Out`

The visible gap for M6-1 is the PRD footer version text.

## Recommended Approach

Keep the existing page structure and add a small version footer:

- Add one constant in `profile_page.dart`: `profileVersionText`.
- Render `Version 1.0.0` at the bottom of the existing guest and user profile
  list. M6-1 tests focus on guest state; reusing the footer for both states is
  simpler and matches the PRD, which lists version in both guest and logged-in
  profile pages.
- Strengthen the existing guest widget test so it verifies anonymous identity
  and version text, not only the action list.

## Alternatives Considered

1. Add `package_info_plus` and read runtime version. This is more dynamic but
   adds a dependency for one PRD string while the app version is already fixed in
   `apps/flutter-app/pubspec.yaml`.
2. Create a dedicated Profile controller. The page currently reads auth state
   directly and this slice does not introduce enough behavior to justify a new
   state layer.
3. Redesign Profile sections with headers and cards now. This is visual polish
   and would broaden M6-1 beyond the minimal guest-state contract.

The selected approach is a small, testable UI completion with minimal conflict
risk for later M6 tasks.

## Behavior

For an anonymous session such as `anon-existing`, Profile guest state renders:

- `Guest session`
- `anon-existing`
- `Sign in / Sign up`
- `Customer Support`
- `Score`
- `Share With Friends`
- `Terms Of Use`
- `Privacy Policy`
- `Delete account`
- `Version 1.0.0`

It does not render `Log Out` in guest state.

Clicking `Delete account` continues to use the existing confirmation dialog.
Clicking `Sign in / Sign up` continues to use the existing auth sheet.

## Testing

Use TDD:

- Update the guest profile widget test first to expect `Guest session`, the
  anonymous id, and `Version 1.0.0`.
- Run the test and confirm RED because the version text is missing.
- Add the smallest UI change to render the footer.
- Run the focused widget test and full Flutter verification.

Completion verification remains:

- `flutter test test/widget/auth_profile_test.dart`
- `flutter pub get`
- `dart run melos run test`
- `flutter analyze`
- `dart format --set-exit-if-changed lib test`
