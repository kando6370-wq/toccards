# M6-5 Delete Account Flow Design

## Scope

Complete the Flutter delete-account flow for Profile and Account before M7/Admin
work begins. Both guest and signed-in delete actions must require the shared
confirmation dialog. On success, the app returns to a guest Profile state. On
failure, the current account state is preserved and the dedicated failure Toast
is shown.

This slice is Flutter-only. It does not add or modify Workers routes, does not
change D1 schema or migrations, does not touch admin web, and does not modify
`docs/tcg-card/**`.

## Existing State

Profile and Account already render `Delete account` and show the shared
confirmation dialog. `AuthController.deleteAccount()` clears local user or
anonymous storage and creates/restores a guest session. The gaps are:

- Account delete success routes to `/`, which now opens Home rather than Profile.
- Delete failures bubble out without a user-facing Toast.
- The repository interface has no explicit delete-account operation, so the
  behavior is hidden behind storage-clear methods.

## Recommended Approach

Keep the existing local auth repository pattern and add the smallest explicit
delete seam:

- Add `deleteCurrentAccount(AuthSession session)` to `AuthRepository`.
- Have `AuthController.deleteAccount()` call it before switching to the next
  guest state.
- Keep local placeholder deletion mapped to local storage clearing.
- Catch failures in Profile and Account pages and show
  `Unable to complete this action. Please try again later.`
- Route Account delete success to `/profile`; keep guest Profile delete on the
  same Profile page.

## Alternatives Considered

1. Wire a real Workers `DELETE /auth/account` client now. That would be closer
   to production but expands this M6 Flutter slice into backend/API work.
2. Only change Account routing to `/profile`. That fixes the happy path but
   leaves the failure behavior and repository semantics below PRD.
3. Split user and guest deletion into separate controller methods. The PRD uses
   the same confirmation dialog and endpoint shape, so one controller method is
   simpler and matches current code.

The selected approach completes the visible M6-5 flow while keeping backend
integration replaceable later.

## Behavior

- Guest Profile delete:
  - Tap `Delete account`.
  - Confirm dialog shows `Delete Account?`,
    `This action is permanent and can't be undone.`, `Cancel`, and `Delete`.
  - Cancel leaves the same guest session.
  - Delete calls repository deletion, creates a fresh guest, and stays on Profile.

- Signed-in Account delete:
  - Tap `Delete account`.
  - Cancel leaves the user session and Account page.
  - Delete calls repository deletion, switches to guest, and routes to Profile.

- Failure:
  - If repository deletion fails, keep the current session, stay on the current
    page, and show `Unable to complete this action. Please try again later.`

## Testing

Use TDD:

- Add controller tests proving delete calls the repository, preserves state on
  failure, creates a fresh guest after anonymous deletion, and routes user
  deletion through the same semantic operation.
- Update widget tests so signed-in Account deletion lands on guest Profile
  instead of Home.
- Add widget tests for delete failure Toast from Account and guest Profile.
- Run RED before implementation, then focused tests and full Flutter
  verification before marking `[M6-5]` complete.
