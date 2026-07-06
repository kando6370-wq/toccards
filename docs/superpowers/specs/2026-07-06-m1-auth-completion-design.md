# M1 Auth Completion Design

## Background

M1 already has the backend foundations for anonymous accounts, Email registration, Email login, forgot password, token refresh, logout, and current-account lookup.

This design completes the remaining M1 auth scope from M1-6 through M1-12 as an overall plan, while keeping implementation split into small verified slices. The selected execution path is backend-first: stabilize Workers API behavior and tests before building Flutter Auth UI and client state.

OAuth uses a mock-first approach for M1. Real Google and Apple credentials and network provider implementations are deferred to the M8 production integration milestone.

## Current State

Already implemented and included in final M1 regression:

- `POST /auth/anonymous`
- `POST /auth/register/send-code`
- `POST /auth/register/verify`
- `POST /auth/login`
- `POST /auth/forgot-password/send-code`
- `POST /auth/forgot-password/verify-code`
- `POST /auth/forgot-password/reset`
- `POST /auth/token/refresh`
- `POST /auth/logout`
- `GET /auth/me`

Still to implement:

- `POST /auth/oauth/google/callback`
- `POST /auth/oauth/apple/callback`
- `DELETE /auth/account`
- `POST /auth/migrate-assets`
- Flutter Auth app baseline, Profile/Auth UI, Auth session state, and guest upgrade handling.

The Flutter app is currently a generated counter app. M1-11 and M1-12 therefore require a minimal Auth application shell before individual Auth screens can be wired.

## Scope

Included:

- Workers backend Google OAuth callback with a mock provider.
- Workers backend Apple OAuth callback with a mock provider.
- Shared OAuth account flow for existing identity login and new OAuth-only user registration.
- Shared guest migration logic reused by Email registration, OAuth new-user registration, and the standalone migration endpoint.
- Account deletion for both `user` and `anonymous` JWT owners through `DELETE /auth/account`.
- Standalone `POST /auth/migrate-assets` for retrying guest asset migration after registration or OAuth success.
- Flutter Auth shell using Riverpod, go_router, Dio, and a replaceable OAuth authorizer.
- Flutter anonymous boot, user session restore, logout, delete account, Email auth UI, forgot password UI, and mock Google/Apple UI paths.
- End-to-end M1 regression using mock-first OAuth.

Excluded:

- Real Google token exchange or userinfo calls.
- Real Apple public-key verification and token exchange.
- Real iOS Google/Apple native authorization plugins.
- M2/M3 asset CRUD pages.
- M4 Home, Collection, Search, and M5 Card Detail UI.
- Subscription or Restore Purchase behavior.
- Database schema changes.

## Architecture Choice

Use path A: backend-first, then Flutter integration.

Reasoning:

- The remaining scope crosses backend auth, D1 writes, session behavior, guest migration, account deletion, and Flutter routing. Stabilizing API semantics first keeps failure localization clear.
- Flutter UI can depend on a known API contract instead of carrying fake state that later diverges from Workers behavior.
- Mock-first OAuth unblocks M1 while preserving a clean replacement point for M8 real credentials.

## Backend Design

### Module Layout

Add or adjust the following focused modules:

- `apps/workers-api/src/auth/oauth.ts`
  - Registers `/oauth/google/callback` and `/oauth/apple/callback`.
  - Parses provider-specific request bodies.
  - Maps provider failures to the documented authorization error response.

- `apps/workers-api/src/auth/oauth-provider.ts`
  - Defines a narrow provider interface that converts callback input into `{ provider, providerUid, email }`.
  - M1 implementation is deterministic and testable with mock Google and Apple providers.
  - M8 can replace internals with real provider calls without changing account-flow code.

- `apps/workers-api/src/auth/account-flow.ts`
  - Owns shared OAuth login and registration semantics.
  - Existing `auth_identity` logs in the linked live user and does not migrate guest assets.
  - Missing `auth_identity` creates an OAuth-only `user`, inserts `auth_identity`, initializes default user assets, optionally migrates a live guest account, and signs a user session.

- `apps/workers-api/src/auth/guest-migration.ts`
  - Extracts guest migration behavior currently embedded in Email registration.
  - Reused by Email registration, OAuth new-user registration, and `/auth/migrate-assets`.
  - Preserves the rule that registration of a new user may migrate guest assets, while login to an existing user never migrates guest assets.

- `apps/workers-api/src/auth/account.ts`
  - Registers `DELETE /auth/account` and `POST /auth/migrate-assets`.
  - Handles user and anonymous account deletion through one API endpoint.

### OAuth Flow

For Google and Apple callbacks:

1. Parse the callback body.
2. Ask the mock provider for provider identity.
3. Look up `auth_identity` by provider and provider UID.
4. If identity exists:
   - Load the linked live user.
   - Sign a new user session.
   - Return `is_new_user: false` and `migrated: false`.
5. If identity does not exist:
   - Create `user` with `password_hash = NULL`.
   - Insert `auth_identity`.
   - Initialize default user assets.
   - If a live `anonymous_id` was supplied, migrate guest assets and mark the anonymous account upgraded.
   - Sign a new user session.
   - Return `is_new_user: true` and the actual migrated flag.

### Standalone Migration

`POST /auth/migrate-assets`:

- Requires a user JWT.
- Accepts `anonymous_id`.
- Returns `NOT_FOUND` when the anonymous account does not exist or is no longer live.
- Returns `CONFLICT` when the anonymous account was already upgraded.
- Migrates portfolio folders, collection items, wishlist items, and user preferences.
- Returns migration counts for folders, items, and wishlist rows.

Migration failures must not mark the anonymous account upgraded and must not delete guest assets.

### Account Deletion

`DELETE /auth/account` accepts both user and anonymous JWT owners.

For user JWT:

- Set `user.deleted_at`.
- Revoke all sessions for that user.
- Keep account assets under the deleted user according to privacy retention policy for this M1 slice.

For anonymous JWT:

- Delete or invalidate the anonymous account and its guest-owned assets.
- Revoke all sessions for that anonymous account.
- The old anonymous identity must not be restored by the client.

This deliberately chooses the product-confirmed behavior in `docs/tcg-card/00-product/modules/profile.md`: guest users can delete the server-side `anonymous_account` and all guest assets. That supersedes the older `api-spec.md` wording that said anonymous calls to `DELETE /auth/account` return `AUTH_REQUIRED`.

## Flutter Design

### App Shell

Replace the generated counter app with a minimal Auth application shell:

- `lib/app/app.dart`
- `lib/app/router.dart`
- `lib/app/theme.dart`

Use:

- `MaterialApp.router`
- `go_router`
- Riverpod for Auth state
- Dio for Workers API calls

### Auth Feature

Add:

- `features/auth/auth_controller.dart`
- `features/auth/auth_repository.dart`
- `features/auth/auth_models.dart`
- `features/auth/auth_storage.dart`
- `features/auth/oauth_authorizer.dart`

Responsibilities:

- Persist `device_id`, `anonymous_id`, access token, refresh token, and current owner type.
- Restore current account with `/auth/me`.
- Refresh access token when possible.
- Create or restore anonymous session when user session is absent or invalid.
- Keep the previous anonymous binding available after logging into an existing user account.
- Store pending migration state when registration succeeds but migration requires retry.

### Profile and Auth UI

Add minimal M1 Auth UI:

- Guest Profile.
- User Profile.
- Account page.
- Sign in / Sign up method sheet.
- Email registration flow.
- Email login flow.
- Forgot password flow.
- Mock Google and Apple buttons.
- Logout action.
- Delete account confirmation.

M1 success is Auth correctness, not full app UI completion. Home, Collection, Search, and Card Detail can remain outside this slice.

## State Rules

Startup:

- If a user session exists, validate with `/auth/me`.
- If user validation fails, fall back to anonymous.
- If no anonymous session exists, create one with `/auth/anonymous`.

Existing account login:

- Store user tokens.
- Do not migrate current anonymous assets.
- Keep anonymous binding so logout can return to guest state.

New account registration:

- Send `anonymous_id` when available.
- On successful migration, switch to user owner assets.
- On migration failure, preserve guest assets and allow retry through `/auth/migrate-assets`.

Logout:

- Revoke current user session.
- Return to previous anonymous session when still valid.
- Otherwise create a new anonymous session.

Account deletion:

- User deletion clears user session and returns to guest state.
- Anonymous deletion clears old anonymous identity and creates a fresh anonymous session.

## Error Handling

OAuth failure:

- `422 / VALIDATION_ERROR / Authorization failed. Please try again.`

Guest migration failure:

- Flutter shows `Something went wrong. Please try again later.`
- Guest assets remain under `anonymous_account`.
- The client records that migration can be retried.

Delete account or logout failure:

- Flutter shows `Unable to complete this action. Please try again later.`
- Existing Auth state remains unchanged.

Anonymous access to user-only endpoints:

- `403 / AUTH_REQUIRED`, except `DELETE /auth/account`, which intentionally supports anonymous JWT.

## Implementation Order

1. Extract backend guest migration and shared account helpers.
2. Implement Google OAuth callback with mock provider.
3. Implement Apple OAuth callback with mock provider.
4. Implement `DELETE /auth/account` and `POST /auth/migrate-assets`.
5. Regress token refresh, logout, and current-account lookup.
6. Replace Flutter counter app with Auth shell.
7. Implement Flutter anonymous boot, Profile state, Account page, logout, and delete account.
8. Implement Flutter Email registration, Email login, and forgot password UI.
9. Implement Flutter mock Google and Apple Auth paths.
10. Run M1 full backend, Flutter, and repository verification.

## Testing Strategy

Backend tests:

- Existing Email registration, login, forgot password, refresh, logout, and `/me` tests must remain passing.
- Google OAuth tests cover new user, existing identity, invalid authorization, guest migration, and existing-user login without guest migration.
- Apple OAuth tests cover new user, existing identity, missing or invalid mock token, guest migration, and existing-user login without guest migration.
- Migration endpoint tests cover success counts, missing anonymous account, already-upgraded anonymous account, anonymous JWT rejection, and migration failure preservation.
- Account deletion tests cover user soft delete, user session revocation, anonymous deletion, anonymous session revocation, and old anonymous identity non-reuse.

Flutter tests:

- Auth controller startup chooses valid user, valid anonymous, or new anonymous session.
- Existing user login keeps the previous anonymous binding.
- New user registration records migrated state.
- Migration failure preserves guest state and exposes retry.
- Logout returns to guest state.
- User delete and anonymous delete both clear the correct local state.
- Form validation messages match Auth PRD copy.

## Verification Commands

Backend:

```powershell
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

Flutter:

```powershell
dart run melos run analyze
dart run melos run test
```

Repository:

```powershell
pnpm run lint
pnpm run type-check
pnpm run build -- --force
```

## Acceptance Criteria

- M1-6 and M1-7 complete through mock-first OAuth callbacks.
- M1-8 and M1-10 remain compatible with new OAuth, migration, and deletion behavior.
- M1-9 supports user deletion, anonymous deletion, and standalone guest migration.
- M1-11 provides usable Auth/Profile UI for M1 flows.
- M1-12 handles guest upgrade, existing-account login without migration, logout-to-guest, and migration retry state.
- No database schema change is required.
- Real Google and Apple credentials are not required for M1 completion.
- Each implementation slice has focused tests before the final M1 regression.
