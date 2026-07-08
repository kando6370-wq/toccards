# M6-2 Profile Signed-In State Design

## Scope

Build the M6-2 signed-in Profile slice for the Flutter app. Signed-in users
should see their account identity on Profile, keep access to Account, support,
rating, sharing, policy entries, logout, delete account, and the existing
version footer. The Account page should show the signed-in account details that
the current Flutter session already owns.

This slice is Flutter-only. It does not add a backend account refresh, does not
extend the database schema, does not implement native App Store rating or native
sharing, and does not touch M7/Admin files.

## Existing State

`ProfilePage` already reads `authControllerProvider` and can distinguish
anonymous and user sessions. The signed-in path currently renders:

- `Signed in`
- email, or user id fallback
- Account entry
- Customer Support
- Score
- Share With Friends
- Terms Of Use
- Privacy Policy
- Version footer

`AccountPage` already renders email, user id, login method, logout, and delete
account for user sessions.

The visible M6-2 gaps are:

- Profile signed-in state does not show user id as its own visible line.
- Profile signed-in state does not expose the bottom `Log Out` entry described
  by the PRD.
- Existing widget coverage verifies Account details, but not the Profile
  signed-in action surface or version footer.

## Recommended Approach

Keep the current Profile/Auth structure and add only the missing signed-in
surface:

- In `profile_page.dart`, derive `emailText` and `userIdText` from
  `AuthSession.email` and `AuthSession.userId`.
- For signed-in users, show email and `ID: <userId>` near the top of Profile.
- Keep the Account card subtitle on the same identity string, with no new
  controller or model.
- Add a signed-in `Log Out` button to Profile that calls the existing
  `AuthController.logout()` and leaves the app on the main route, matching the
  Account page behavior.
- Keep Account page fields backed by `email` and `userId`. Do not add
  `displayName` until a real data source exists.

## Alternatives Considered

1. Add `displayName` to `AuthSession` now. This matches the future
   `display_name` API field, but no current Flutter repository or storage source
   can populate it. Adding it now would create a decorative model field.
2. Build a Profile view model/controller. The current page only composes auth
   state and direct actions, so a new layer would be extra structure without a
   current behavioral need.
3. Implement native rating and sharing now. M6-2 only needs the signed-in entry
   surface; real native rating/share depends on iOS/App Store configuration and
   belongs to a later platform integration slice.

The selected approach is the smallest UI completion that makes the signed-in
Profile contract visible while preserving later M6 and M7 boundaries.

## Behavior

For a signed-in session with `email = person@example.com` and
`userId = user-1`, Profile renders:

- `Signed in`
- `person@example.com`
- `ID: user-1`
- `Account`
- `Customer Support`
- `Score`
- `Share With Friends`
- `Terms Of Use`
- `Privacy Policy`
- `Log Out`
- `Version 1.0.0`

It does not render `Sign in / Sign up` in signed-in state.

Clicking `Account` continues to navigate to Account details. Clicking `Log Out`
uses the existing auth controller logout behavior and returns to guest state.

## Testing

Use TDD:

- First strengthen `user profile navigates to account details` so it expects
  the signed-in Profile surface before navigation.
- Confirm RED because Profile does not show `ID: user-1` or `Log Out`.
- Add the minimal Profile rendering and logout action.
- Run the focused widget test and full Flutter verification.

Completion verification:

- `flutter test test/widget/auth_profile_test.dart`
- `flutter test test/auth_controller_test.dart`
- `flutter pub get`
- `dart run melos run test`
- `flutter analyze`
- `dart format --set-exit-if-changed lib test`
