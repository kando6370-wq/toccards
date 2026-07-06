# M1 Auth Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete M1-6 through M1-12 with mock-first Google/Apple OAuth, account deletion, standalone guest migration, and a minimal Flutter Auth/Profile client.

**Architecture:** Implement backend auth capabilities first, then wire Flutter against the stable API contract. OAuth uses replaceable mock providers in M1; real provider calls replace the provider internals in M8. Shared backend helpers own guest migration and user session creation so Email registration, OAuth registration, and explicit migration do not diverge.

**Tech Stack:** TypeScript, Hono, Cloudflare Workers D1, Vitest, `@kando/auth-core`, Flutter, Riverpod, go_router, Dio, Dart pub workspace.

---

## Execution Constraints

- Do not start implementation unless the worktree is clean or isolated by `superpowers:using-git-worktrees`.
- Keep commits small and task-scoped.
- Preserve existing API behavior for Email registration, Email login, forgot password, refresh, logout, and `/auth/me`.
- Do not add database migrations. The existing `user`, `auth_identity`, `session`, `anonymous_account`, and asset tables are sufficient.
- Use mock-first OAuth in M1. The mock callback input format is:
  - Google `code`: `mock-google:<provider_uid>:<email>`
  - Apple `id_token`: `mock-apple:<provider_uid>:<email>`
- If OAuth email already exists as a live `user` but no `auth_identity` exists, bind the identity to that existing user, sign in, return `is_new_user: false`, and do not migrate guest assets.

---

## File Structure

### Backend

- Create: `apps/workers-api/src/auth/http-auth.ts`
  - Shared bearer-token parsing and signing-secret checks.
- Create: `apps/workers-api/src/auth/user-session.ts`
  - Creates hashed refresh tokens, inserts user sessions, and signs access tokens.
- Create: `apps/workers-api/src/auth/guest-migration.ts`
  - Locates live anonymous accounts and migrates guest-owned rows to a user owner.
- Create: `apps/workers-api/src/auth/oauth-provider.ts`
  - Parses mock Google/Apple provider identities.
- Create: `apps/workers-api/src/auth/oauth.ts`
  - Registers Google and Apple OAuth callback routes.
- Create: `apps/workers-api/src/auth/account.ts`
  - Registers account deletion and standalone migration routes.
- Modify: `apps/workers-api/src/auth/anonymous.ts`
  - Registers OAuth and account routes.
- Modify: `apps/workers-api/src/auth/register.ts`
  - Reuses shared user-session and guest-migration helpers without changing response shape.
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`
  - Extends fake D1 and adds OAuth, migration, and deletion tests.

### Flutter

- Replace: `apps/flutter-app/lib/main.dart`
  - Boots `ProviderScope` and `KandoApp`.
- Create: `apps/flutter-app/lib/app/app.dart`
- Create: `apps/flutter-app/lib/app/router.dart`
- Create: `apps/flutter-app/lib/app/theme.dart`
- Create: `apps/flutter-app/lib/features/auth/auth_controller.dart`
- Create: `apps/flutter-app/lib/features/auth/auth_models.dart`
- Create: `apps/flutter-app/lib/features/auth/auth_repository.dart`
- Create: `apps/flutter-app/lib/features/auth/auth_storage.dart`
- Create: `apps/flutter-app/lib/features/auth/oauth_authorizer.dart`
- Create: `apps/flutter-app/lib/features/auth/ui/auth_sheet.dart`
- Create: `apps/flutter-app/lib/features/auth/ui/email_auth_pages.dart`
- Create: `apps/flutter-app/lib/features/profile/profile_page.dart`
- Create: `apps/flutter-app/lib/features/profile/account_page.dart`
- Create: `apps/flutter-app/test/auth_controller_test.dart`
- Create: `apps/flutter-app/test/widget/auth_profile_test.dart`

---

### Task 1: Extract Shared Backend Auth Helpers

**Files:**
- Create: `apps/workers-api/src/auth/http-auth.ts`
- Create: `apps/workers-api/src/auth/user-session.ts`
- Create: `apps/workers-api/src/auth/guest-migration.ts`
- Modify: `apps/workers-api/src/auth/register.ts`
- Test: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Run current registration regression tests before refactor**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "register"
```

Expected: current registration tests pass before any behavior-preserving extraction.

- [ ] **Step 2: Create `http-auth.ts`**

Use this public API:

```ts
export function getBearerToken(authorization: string | undefined): string | null {
  if (!authorization) return null;
  const [scheme, token, extra] = authorization.trim().split(/\s+/);
  return scheme === "Bearer" && token && !extra ? token : null;
}

export function hasSigningSecret(secret: unknown): secret is string {
  return typeof secret === "string" && secret.trim().length > 0;
}
```

- [ ] **Step 3: Create `user-session.ts`**

Use this public API:

```ts
import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
} from "@kando/auth-core";
import { ulid } from "ulid";

export type CreatedUserSession = {
  sessionId: string;
  accessToken: string;
  refreshToken: string;
  hashedRefreshToken: string;
  expiresAt: string;
  expiresIn: number;
};

export async function createUserSessionValues(
  userId: string,
  jwtSecret: string,
  now: Date,
): Promise<CreatedUserSession> {
  const sessionId = ulid();
  const refreshToken = createRefreshToken();
  const hashedRefreshToken = await hashRefreshToken(refreshToken);
  const accessToken = await signAccessToken(
    { owner_type: "user", owner_id: userId, session_id: sessionId },
    jwtSecret,
    now,
  );

  return {
    sessionId,
    accessToken,
    refreshToken,
    hashedRefreshToken,
    expiresAt: refreshTokenExpiresAt(now),
    expiresIn: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  };
}
```

- [ ] **Step 4: Create `guest-migration.ts` with focused helpers**

Expose these functions and types:

```ts
import { verifyAccessToken } from "@kando/auth-core";
import { getBearerToken } from "./http-auth";

export type AnonymousAccountRow = { id: string };
export type SessionLookupRow = {
  id: string;
  owner_type: string;
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};
export type MigrationCounts = {
  migrated_folders: number;
  migrated_items: number;
  migrated_wishlist: number;
};

export type GuestMigrationGuard = {
  verificationCodeId?: string;
  verificationUsedAt?: string;
};
```

Keep SQL in this module for:

- selecting a live anonymous account,
- selecting a session by id,
- updating anonymous portfolio folders,
- updating anonymous collection items,
- updating anonymous wishlist items,
- updating anonymous user preference,
- marking `anonymous_account.upgraded_user_id`.

The helper names must be:

```ts
export async function findVerifiedAnonymousAccount(
  db: D1Database,
  anonymousId: string | null,
  authorization: string | undefined,
  jwtSecret: string,
  now: Date,
): Promise<AnonymousAccountRow | null>;

export async function migrateGuestAssetsToUser(
  db: D1Database,
  anonymousId: string,
  userId: string,
  updatedAt: string,
  guard: GuestMigrationGuard,
): Promise<MigrationCounts>;
```

For Email registration, `guard` must enforce the verification-code gate. For OAuth and standalone migration, `guard` is empty and the anonymous live-account gate is enough.

- [ ] **Step 5: Refactor `register.ts` to use helpers**

Replace local `getBearerToken`, `hasSigningSecret`, session value creation, and anonymous account verification with imports. Keep the existing response payloads unchanged:

```ts
{
  success: true,
  data: {
    user_id: userId,
    email: input.email,
    access_token: session.accessToken,
    refresh_token: session.refreshToken,
    expires_in: session.expiresIn,
    migrated: anonymousAccount !== null,
  },
}
```

- [ ] **Step 6: Run regression verification**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "register"
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit**

```powershell
git add apps/workers-api/src/auth/http-auth.ts apps/workers-api/src/auth/user-session.ts apps/workers-api/src/auth/guest-migration.ts apps/workers-api/src/auth/register.ts apps/workers-api/src/auth/anonymous.test.ts
git commit -m "refactor(auth): share guest migration helpers"
```

---

### Task 2: Implement Mock Google OAuth Callback

**Files:**
- Create: `apps/workers-api/src/auth/oauth-provider.ts`
- Create: `apps/workers-api/src/auth/account-flow.ts`
- Create: `apps/workers-api/src/auth/oauth.ts`
- Modify: `apps/workers-api/src/auth/anonymous.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Add failing Google OAuth tests**

Add helper:

```ts
async function requestGoogleOAuthCallback(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/oauth/google/callback",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}
```

Add `AuthIdentityRow` to the fake DB model:

```ts
type AuthIdentityRow = {
  id: string;
  user_id: string;
  provider: "google" | "apple";
  provider_uid: string;
  created_at: string;
};
```

Add these test cases:

- `google oauth creates an OAuth-only user because a new provider identity starts durable auth`
  - Request body: `{ code: "mock-google:google-1:google.new@example.com", redirect_uri: "kando://auth/google" }`
  - Assert `200`, `is_new_user: true`, `migrated: false`, one user with `password_hash: null`, one `auth_identity`, one user session.
- `google oauth signs in an existing identity because provider_uid is the stable login key`
  - Seed user and `auth_identity`.
  - Assert `is_new_user: false`, no new user, no guest migration.
- `google oauth binds an existing live email because user.email is unique across auth methods`
  - Seed a live Email user with matching email and no identity.
  - Assert one new `auth_identity`, no new user, `is_new_user: false`, no guest migration.
- `google oauth migrates a live guest only for a new user because registration transfers guest assets`
  - Create anonymous account and guest assets.
  - Send anonymous bearer token and `anonymous_id`.
  - Assert guest asset owners become the new user.
- `google oauth rejects malformed mock authorization because failed provider proof must not create accounts`
  - Request body: `{ code: "bad-code", redirect_uri: "kando://auth/google" }`
  - Assert `422 / VALIDATION_ERROR / Authorization failed. Please try again.`

- [ ] **Step 2: Run tests to verify RED**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "google oauth"
```

Expected: Google OAuth tests fail with 404 or missing fake D1 SQL branches.

- [ ] **Step 3: Implement `oauth-provider.ts`**

Use this public API:

```ts
export type OAuthProviderName = "google" | "apple";

export type OAuthIdentity = {
  provider: OAuthProviderName;
  providerUid: string;
  email: string;
};

export type GoogleOAuthInput = {
  code: string | null;
  redirectUri: string | null;
};

export type AppleOAuthInput = {
  code: string | null;
  idToken: string | null;
};

const EMAIL_MAX_LENGTH = 254;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function resolveMockGoogleIdentity(
  input: GoogleOAuthInput,
): OAuthIdentity | null {
  if (!input.code || !input.redirectUri) return null;
  const parts = input.code.split(":");
  if (parts.length !== 3 || parts[0] !== "mock-google") return null;
  const providerUid = parts[1]?.trim();
  const email = normalizeEmail(parts[2]);
  if (!providerUid || !email) return null;
  return { provider: "google", providerUid, email };
}

export function resolveMockAppleIdentity(
  input: AppleOAuthInput,
): OAuthIdentity | null {
  if (!input.code || !input.idToken) return null;
  const parts = input.idToken.split(":");
  if (parts.length !== 3 || parts[0] !== "mock-apple") return null;
  const providerUid = parts[1]?.trim();
  const email = normalizeEmail(parts[2]);
  if (!providerUid || !email) return null;
  return { provider: "apple", providerUid, email };
}

function normalizeEmail(rawEmail: string | undefined): string | null {
  if (!rawEmail) return null;
  const email = rawEmail.trim().toLowerCase();
  return email.length <= EMAIL_MAX_LENGTH && EMAIL_PATTERN.test(email)
    ? email
    : null;
}
```

- [ ] **Step 4: Implement `oauth.ts` Google path**

Create `account-flow.ts` and implement the shared OAuth account flow used by the Google route and the later Apple route. It must:

- check existing `auth_identity` by provider and provider UID,
- sign in the linked live user when identity exists,
- bind a missing identity to an existing live `user.email`,
- create an OAuth-only user when neither identity nor live email exists,
- initialize default user assets for new OAuth-only users,
- migrate a verified anonymous account only for a newly created user,
- create a user session with `createUserSessionValues`.

Then register `POST /oauth/google/callback` in `oauth.ts`. The route must:

- parse `code`, `redirect_uri`, and optional `anonymous_id`,
- call `resolveMockGoogleIdentity`,
- return the authorization failure response on null,
- call the shared account-flow helper to return access and refresh tokens.

Response shape:

```ts
{
  success: true,
  data: {
    user_id: userId,
    email: identity.email,
    access_token: session.accessToken,
    refresh_token: session.refreshToken,
    expires_in: session.expiresIn,
    is_new_user: isNewUser,
    migrated,
  },
}
```

- [ ] **Step 5: Register OAuth routes**

In `apps/workers-api/src/auth/anonymous.ts`:

```ts
import { registerOAuthRoutes } from "./oauth";
```

Register after forgot-password routes:

```ts
registerOAuthRoutes(authRoutes);
```

- [ ] **Step 6: Extend FakeD1 for Google OAuth SQL**

Add fake DB arrays and SQL branches for:

- `authIdentities: AuthIdentityRow[] = []`
- select identity by provider and provider UID,
- select live user by id,
- select live user by email,
- insert OAuth-only user,
- insert `auth_identity`,
- insert user default folder,
- insert user preference,
- insert user session,
- migration SQL from Task 1.

All branches must return `okResult<T>(1)` for successful writes and `okResult<T>(0)` for guarded no-op writes.

- [ ] **Step 7: Run Google OAuth verification**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "google oauth"
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
```

Expected: all commands exit 0.

- [ ] **Step 8: Commit**

```powershell
git add apps/workers-api/src/auth/oauth-provider.ts apps/workers-api/src/auth/account-flow.ts apps/workers-api/src/auth/oauth.ts apps/workers-api/src/auth/anonymous.ts apps/workers-api/src/auth/anonymous.test.ts
git commit -m "feat(auth): add mock google oauth callback"
```

---

### Task 3: Implement Mock Apple OAuth Callback

**Files:**
- Modify: `apps/workers-api/src/auth/oauth.ts`
- Modify: `apps/workers-api/src/auth/oauth-provider.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Add failing Apple OAuth tests**

Add helper:

```ts
async function requestAppleOAuthCallback(
  env: TestEnv,
  body: unknown,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/oauth/apple/callback",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}
```

Add these test cases:

- `apple oauth creates an OAuth-only user because id_token proves a new provider identity`
- `apple oauth signs in an existing identity because provider_uid is stable across sessions`
- `apple oauth binds an existing live email because one email maps to one user`
- `apple oauth migrates a live guest only for a new user because existing-user login must not merge assets`
- `apple oauth rejects missing id_token because provider identity cannot be proven`

Use request bodies like:

```ts
{ code: "apple-auth-code", id_token: "mock-apple:apple-1:apple.new@example.com" }
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "apple oauth"
```

Expected: Apple OAuth tests fail until `/oauth/apple/callback` is implemented.

- [ ] **Step 3: Implement Apple route**

Reuse the same account-flow helper as Google. The Apple route must parse `code`, `id_token`, and optional `anonymous_id`, then call `resolveMockAppleIdentity`.

Authorization failure response:

```ts
const AUTHORIZATION_FAILED_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Authorization failed. Please try again.",
  },
} as const;
```

- [ ] **Step 4: Run Apple and full backend verification**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "apple oauth"
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```powershell
git add apps/workers-api/src/auth/oauth-provider.ts apps/workers-api/src/auth/oauth.ts apps/workers-api/src/auth/anonymous.test.ts
git commit -m "feat(auth): add mock apple oauth callback"
```

---

### Task 4: Implement Account Deletion and Standalone Guest Migration

**Files:**
- Create: `apps/workers-api/src/auth/account.ts`
- Modify: `apps/workers-api/src/auth/anonymous.ts`
- Modify: `apps/workers-api/src/auth/anonymous.test.ts`

- [ ] **Step 1: Add failing account endpoint tests**

Add helpers:

```ts
async function requestDeleteAccount(
  env: TestEnv,
  authorization?: string,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/account",
    { method: "DELETE", headers: authorization ? { Authorization: authorization } : {} },
    env,
  );
}

async function requestMigrateAssets(
  env: TestEnv,
  body: unknown,
  authorization?: string,
): Promise<Response> {
  return app.request(
    "/api/v1/auth/migrate-assets",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(authorization ? { Authorization: authorization } : {}),
      },
      body: JSON.stringify(body),
    },
    env,
  );
}
```

Add these tests:

- `delete account soft-deletes a user because removed credentials must not authenticate again`
- `delete account revokes all user sessions because deleted users must not refresh tokens`
- `delete account deletes anonymous guest assets because guest deletion must be irreversible`
- `delete account revokes anonymous sessions because old guest identity must not be reused`
- `delete account returns 401 without bearer token because destructive actions require owner proof`
- `migrate-assets transfers guest assets to the current user because registration migration can be retried`
- `migrate-assets returns 404 for a missing anonymous account because there is no source owner`
- `migrate-assets returns 409 for an already upgraded anonymous account because assets must not be stolen`
- `migrate-assets returns 403 for anonymous JWT because only durable users can claim guest assets`

- [ ] **Step 2: Run tests to verify RED**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "delete account|migrate-assets"
```

Expected: tests fail with 404.

- [ ] **Step 3: Implement `account.ts`**

Route behavior:

- `DELETE /account`
  - verifies bearer token,
  - for `owner_type = "user"` updates `user.deleted_at` and revokes sessions by owner,
  - for `owner_type = "anonymous"` deletes guest-owned portfolio folders, collection items, wishlist items, user preferences, marks anonymous account unavailable, and revokes sessions by owner,
  - returns `{ success: true, data: {} }`.
- `POST /migrate-assets`
  - verifies bearer token,
  - rejects anonymous owner with `403 / AUTH_REQUIRED`,
  - parses non-empty `anonymous_id`,
  - calls `migrateGuestAssetsToUser`,
  - returns counts.

Response constants:

```ts
const UNAUTHORIZED_RESPONSE = {
  success: false,
  error: { code: "UNAUTHORIZED", message: "Unauthorized." },
} as const;

const AUTH_REQUIRED_RESPONSE = {
  success: false,
  error: { code: "AUTH_REQUIRED", message: "Auth required." },
} as const;

const NOT_FOUND_RESPONSE = {
  success: false,
  error: { code: "NOT_FOUND", message: "Not found." },
} as const;

const CONFLICT_RESPONSE = {
  success: false,
  error: { code: "CONFLICT", message: "Guest account is no longer available." },
} as const;

const ACCOUNT_ACTION_FAILED_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Unable to complete this action. Please try again later.",
  },
} as const;
```

- [ ] **Step 4: Register account routes**

In `anonymous.ts`:

```ts
import { registerAccountRoutes } from "./account";
registerAccountRoutes(authRoutes);
```

- [ ] **Step 5: Extend FakeD1 for account SQL**

Add branches for:

- updating `user.deleted_at`,
- revoking sessions by owner,
- deleting or invalidating anonymous account,
- deleting guest-owned asset rows,
- migration endpoint queries and updates.

Ensure deleting anonymous account removes or invalidates all rows with `owner_type = "anonymous"` and matching owner id.

- [ ] **Step 6: Run endpoint and full backend verification**

Run:

```powershell
pnpm --filter @kando/workers-api run test -- src/auth/anonymous.test.ts -t "delete account|migrate-assets"
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit**

```powershell
git add apps/workers-api/src/auth/account.ts apps/workers-api/src/auth/anonymous.ts apps/workers-api/src/auth/anonymous.test.ts
git commit -m "feat(auth): add account deletion and guest migration"
```

---

### Task 5: Build Flutter Auth Shell and Anonymous Startup

**Files:**
- Replace: `apps/flutter-app/lib/main.dart`
- Create: `apps/flutter-app/lib/app/app.dart`
- Create: `apps/flutter-app/lib/app/router.dart`
- Create: `apps/flutter-app/lib/app/theme.dart`
- Create: `apps/flutter-app/lib/features/auth/auth_models.dart`
- Create: `apps/flutter-app/lib/features/auth/auth_storage.dart`
- Create: `apps/flutter-app/lib/features/auth/auth_repository.dart`
- Create: `apps/flutter-app/lib/features/auth/auth_controller.dart`
- Create: `apps/flutter-app/lib/features/profile/profile_page.dart`
- Test: `apps/flutter-app/test/auth_controller_test.dart`

- [ ] **Step 1: Add Auth model types**

Create immutable plain Dart models first, without code generation:

```dart
enum OwnerType { anonymous, user }

class AuthSession {
  const AuthSession({
    required this.ownerType,
    required this.accessToken,
    required this.refreshToken,
    this.anonymousId,
    this.userId,
    this.email,
  });

  final OwnerType ownerType;
  final String accessToken;
  final String refreshToken;
  final String? anonymousId;
  final String? userId;
  final String? email;
}

class AuthState {
  const AuthState.loading()
      : session = null,
        isLoading = true,
        pendingMigrationAnonymousId = null;

  const AuthState.ready({
    required this.session,
    this.pendingMigrationAnonymousId,
  }) : isLoading = false;

  final AuthSession? session;
  final bool isLoading;
  final String? pendingMigrationAnonymousId;
}
```

- [ ] **Step 2: Add repository interface and fake test implementation**

Define repository methods:

```dart
abstract class AuthRepository {
  Future<AuthSession?> currentSessionFromStorage();
  Future<AuthSession> createAnonymousSession(String deviceId);
  Future<AuthSession?> validateStoredSession(AuthSession session);
  Future<void> persistSession(AuthSession session);
  Future<void> clearUserSession();
  Future<void> clearAnonymousSession();
}
```

- [ ] **Step 3: Add controller behavior**

`AuthController` must:

- load stored session,
- validate it through repository,
- create anonymous session when validation fails,
- expose logout and delete-account entry points for subsequent tasks.

Use Riverpod `AsyncNotifier<AuthState>` or `Notifier<AuthState>` consistently with the installed Riverpod 3 API.

- [ ] **Step 4: Replace counter app**

`main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

void main() {
  runApp(const ProviderScope(child: KandoApp()));
}
```

`KandoApp` uses `MaterialApp.router` and the Profile page as the first route.

- [ ] **Step 5: Add startup tests**

In `auth_controller_test.dart`, cover:

- valid stored user session stays user,
- invalid stored user session creates anonymous,
- no stored session creates anonymous,
- anonymous session remains anonymous.

- [ ] **Step 6: Run Flutter verification**

Run:

```powershell
dart run melos run analyze
dart run melos run test
```

Expected: analyze and tests exit 0.

- [ ] **Step 7: Commit**

```powershell
git add apps/flutter-app/lib apps/flutter-app/test/auth_controller_test.dart
git commit -m "feat(flutter): add auth shell and anonymous startup"
```

---

### Task 6: Add Flutter Profile, Account, Logout, and Delete Account

**Files:**
- Create: `apps/flutter-app/lib/features/profile/account_page.dart`
- Modify: `apps/flutter-app/lib/features/profile/profile_page.dart`
- Modify: `apps/flutter-app/lib/features/auth/auth_controller.dart`
- Modify: `apps/flutter-app/lib/features/auth/auth_repository.dart`
- Test: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [ ] **Step 1: Add controller methods**

Add methods:

```dart
Future<void> logout();
Future<void> deleteAccount();
```

Rules:

- logout clears user session and returns to previous anonymous session or creates a new anonymous session,
- delete user clears user session and returns to anonymous,
- delete anonymous clears old anonymous identity and creates a fresh anonymous session.

- [ ] **Step 2: Build Profile page**

Profile must show:

- guest state with `Sign in / Sign up`, `Customer Support`, `Score`, `Share With Friends`, `Terms Of Use`, `Privacy Policy`, and `Delete account`,
- user state with account card, `Customer Support`, `Score`, `Share With Friends`, `Terms Of Use`, `Privacy Policy`.

Keep visual styling simple and aligned with M1 scope.

- [ ] **Step 3: Build Account page**

Account page must show:

- email,
- user id,
- login method text,
- `Log Out`,
- `Delete account`.

- [ ] **Step 4: Add delete confirmation dialog**

Dialog copy:

- title: `Delete Account?`
- body: `This action is permanent and can't be undone.`
- secondary button: `Cancel`
- primary button: `Delete`

- [ ] **Step 5: Add widget tests**

Cover:

- guest profile shows delete account and no logout,
- user profile navigates to account page,
- logout returns to guest state,
- guest delete creates a fresh anonymous state,
- user delete returns to guest state.

- [ ] **Step 6: Run Flutter verification**

Run:

```powershell
dart run melos run analyze
dart run melos run test
```

Expected: analyze and tests exit 0.

- [ ] **Step 7: Commit**

```powershell
git add apps/flutter-app/lib apps/flutter-app/test
git commit -m "feat(flutter): add profile auth actions"
```

---

### Task 7: Add Flutter Email and Forgot Password UI

**Files:**
- Create: `apps/flutter-app/lib/features/auth/ui/auth_sheet.dart`
- Create: `apps/flutter-app/lib/features/auth/ui/email_auth_pages.dart`
- Modify: `apps/flutter-app/lib/features/auth/auth_controller.dart`
- Modify: `apps/flutter-app/lib/features/auth/auth_repository.dart`
- Test: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [ ] **Step 1: Add repository methods**

Add methods:

```dart
Future<void> sendRegisterCode(String email);
Future<AuthSession> verifyRegister({
  required String email,
  required String code,
  required String password,
  String? anonymousId,
});
Future<AuthSession> login({
  required String email,
  required String password,
});
Future<void> sendForgotPasswordCode(String email);
Future<String> verifyForgotPasswordCode({
  required String email,
  required String code,
});
Future<void> resetPassword({
  required String email,
  required String resetToken,
  required String newPassword,
});
```

- [ ] **Step 2: Implement validation helpers**

Use these messages exactly:

- `Please enter your email.`
- `Please enter a valid email address.`
- `Password must be at least 8 characters.`
- `Passwords do not match.`
- `Incorrect verification code.`
- `Code expired. Please request a new code.`

- [ ] **Step 3: Add Auth method sheet**

Sheet entries:

- `Continue with Google`
- `Continue with Apple`
- `Continue with Email`

- [ ] **Step 4: Add Email pages**

Implement:

- email input,
- password login,
- register code input,
- set password,
- forgot password email,
- forgot password code,
- set new password.

Each submit button must be disabled or show loading while the request is in flight.

- [ ] **Step 5: Add widget tests**

Cover:

- invalid email shows email format error,
- short password blocks submit,
- mismatched password blocks submit,
- successful login switches to user state,
- forgot password reset success returns to login path.

- [ ] **Step 6: Run Flutter verification**

Run:

```powershell
dart run melos run analyze
dart run melos run test
```

Expected: analyze and tests exit 0.

- [ ] **Step 7: Commit**

```powershell
git add apps/flutter-app/lib apps/flutter-app/test
git commit -m "feat(flutter): add email auth flows"
```

---

### Task 8: Add Flutter Mock Google and Apple Auth Paths

**Files:**
- Create: `apps/flutter-app/lib/features/auth/oauth_authorizer.dart`
- Modify: `apps/flutter-app/lib/features/auth/auth_controller.dart`
- Modify: `apps/flutter-app/lib/features/auth/auth_repository.dart`
- Modify: `apps/flutter-app/lib/features/auth/ui/auth_sheet.dart`
- Test: `apps/flutter-app/test/auth_controller_test.dart`
- Test: `apps/flutter-app/test/widget/auth_profile_test.dart`

- [ ] **Step 1: Define OAuth authorizer**

```dart
enum OAuthProvider { google, apple }

class OAuthAuthorizationResult {
  const OAuthAuthorizationResult.google({required this.code})
      : provider = OAuthProvider.google,
        idToken = null;

  const OAuthAuthorizationResult.apple({
    required this.code,
    required this.idToken,
  }) : provider = OAuthProvider.apple;

  final OAuthProvider provider;
  final String code;
  final String? idToken;
}

abstract class OAuthAuthorizer {
  Future<OAuthAuthorizationResult?> authorize(OAuthProvider provider);
}
```

M1 mock implementation returns:

- Google: `mock-google:flutter-google-user:flutter.google@example.com`
- Apple: `code = "apple-auth-code"`, `idToken = "mock-apple:flutter-apple-user:flutter.apple@example.com"`

- [ ] **Step 2: Add repository methods**

```dart
Future<AuthSession> googleCallback({
  required String code,
  required String redirectUri,
  String? anonymousId,
});

Future<AuthSession> appleCallback({
  required String code,
  required String idToken,
  String? anonymousId,
});
```

- [ ] **Step 3: Add controller actions**

```dart
Future<void> continueWithGoogle();
Future<void> continueWithApple();
```

Rules:

- pass current `anonymousId` when present,
- persist returned user session,
- keep previous anonymous binding when response represents existing account login,
- record pending migration state only when backend reports migration failure.

- [ ] **Step 4: Wire sheet buttons**

`Continue with Google` calls `continueWithGoogle`; `Continue with Apple` calls `continueWithApple`.

- [ ] **Step 5: Add tests**

Cover:

- Google new user switches to user state,
- Apple new user switches to user state,
- cancelled authorization leaves state unchanged,
- authorization failure keeps guest state and exposes error copy `Authorization failed. Please try again.`,
- existing account login does not clear stored anonymous binding.

- [ ] **Step 6: Run Flutter verification**

Run:

```powershell
dart run melos run analyze
dart run melos run test
```

Expected: analyze and tests exit 0.

- [ ] **Step 7: Commit**

```powershell
git add apps/flutter-app/lib apps/flutter-app/test
git commit -m "feat(flutter): add mock oauth auth paths"
```

---

### Task 9: Final M1 Auth Verification and Code Review Prep

**Files:**
- Verify only unless a previous task left a defect.

- [ ] **Step 1: Backend verification**

Run:

```powershell
pnpm --filter @kando/auth-core run test
pnpm --filter @kando/auth-core run type-check
pnpm --filter @kando/auth-core run build
pnpm --filter @kando/workers-api run test
pnpm --filter @kando/workers-api run type-check
pnpm --filter @kando/workers-api run build
```

Expected: all commands exit 0.

- [ ] **Step 2: Flutter verification**

Run:

```powershell
dart run melos run analyze
dart run melos run test
```

Expected: all commands exit 0.

- [ ] **Step 3: Repository verification**

Run:

```powershell
pnpm run lint
pnpm run type-check
pnpm run build -- --force
```

Expected: all commands exit 0. If Wrangler dry-run build is blocked by sandbox log writes, rerun the same build command with escalation and record the clean result.

- [ ] **Step 4: Review checklist**

Check:

- Google and Apple OAuth are mock-first and do not require real credentials.
- Existing user email binding creates `auth_identity` and does not migrate guest assets.
- New OAuth users with `anonymous_id` can migrate guest assets.
- Existing identity login never migrates guest assets.
- User delete soft-deletes the user and revokes sessions.
- Anonymous delete makes the old anonymous identity unrecoverable.
- Logout returns to previous anonymous state when available.
- Flutter does not implement M2/M3/M4/M5 screens inside this M1 Auth slice.

- [ ] **Step 5: Commit verification fixes if needed**

If verification required fixes:

```powershell
git add <changed-files>
git commit -m "fix(auth): resolve m1 verification issues"
```

If no fixes were needed, do not create an empty commit.

- [ ] **Step 6: Final status**

Run:

```powershell
git status --short --branch
git log -5 --oneline
```

Expected: worktree clean; recent log includes the M1 auth completion commits.
