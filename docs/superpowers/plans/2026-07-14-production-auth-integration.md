# Production Authentication Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace mock Google login with verified Google ID tokens and send registration/password-reset codes through Zoho ZeptoMail.

**Architecture:** Cloudflare Workers owns Google token verification and transactional email delivery behind focused provider modules; existing account and verification-code flows remain authoritative. Flutter uses `google_sign_in` only to obtain an ID token, while Apple behavior remains unchanged.

**Tech Stack:** TypeScript, Hono, Cloudflare Workers, Vitest, `jose` 6.2.3, Flutter, `google_sign_in` 7.2.0, Zoho ZeptoMail HTTPS API

---

## File Structure

- Create `apps/workers-api/src/auth/mail.ts`: ZeptoMail request construction and delivery.
- Create `apps/workers-api/src/auth/mail.test.ts`: provider contract and redaction-focused tests.
- Modify `apps/workers-api/src/auth/register.ts`: send registration codes and invalidate failed deliveries.
- Modify `apps/workers-api/src/auth/forgot-password.ts`: send reset codes and invalidate failed deliveries.
- Modify `apps/workers-api/src/auth/anonymous.test.ts`: route-level mail and Google callback coverage.
- Modify `apps/workers-api/src/auth/oauth-provider.ts`: verified Google ID-token identity resolution.
- Create `apps/workers-api/src/auth/oauth-provider.test.ts`: token claim validation tests.
- Modify `apps/workers-api/src/auth/oauth.ts`: accept `id_token` for Google.
- Modify `apps/workers-api/src/env.ts`: production auth bindings.
- Modify `apps/workers-api/package.json` and `pnpm-lock.yaml`: add `jose`.
- Modify `apps/flutter-app/lib/features/auth/oauth_authorizer.dart`: native Google authorizer and unchanged Apple mock.
- Modify `apps/flutter-app/lib/features/auth/auth_controller.dart`: pass Google ID token.
- Modify `apps/flutter-app/lib/features/auth/auth_repository.dart`: send Google `id_token`.
- Modify `apps/flutter-app/test/auth_controller_test.dart` and `apps/flutter-app/test/widget/auth_profile_test.dart`: updated contract tests.
- Modify `apps/flutter-app/pubspec.yaml`, `pubspec.lock`, and `apps/flutter-app/ios/Runner/Info.plist`: Google SDK and iOS URL scheme.
- Modify `apps/workers-api/wrangler.toml`: non-secret production variables only.
- Modify relevant `docs/tcg-card` dependency and technology documents: replace the unresolved Resend/SES provider choice with ZeptoMail.

### Task 1: ZeptoMail Provider

**Files:** Create `apps/workers-api/src/auth/mail.ts`; create `apps/workers-api/src/auth/mail.test.ts`; modify `apps/workers-api/src/env.ts`.

- [ ] **Step 1: Write failing provider tests** for registration/reset subjects, `Zoho-enczapikey` authorization, HTML escaping, non-2xx rejection, and timeout rejection. Use a fake `fetch` and assert the token/code never appears in thrown errors.
- [ ] **Step 2: Verify RED:** `pnpm --filter @kando/workers-api exec vitest run src/auth/mail.test.ts` must fail because `mail.ts` does not exist.
- [ ] **Step 3: Implement the minimal API:**

```ts
export type VerificationPurpose = "register" | "reset_password";
export type MailEnv = Pick<Env, "ZEPTOMAIL_TOKEN" | "ZEPTOMAIL_API_URL" | "MAIL_FROM_ADDRESS" | "MAIL_FROM_NAME">;
export async function sendVerificationEmail(env: MailEnv, input: {
  recipient: string; code: string; purpose: VerificationPurpose;
}, fetcher: typeof fetch = fetch): Promise<void>;
```

POST the ZeptoMail JSON payload with plain-text and escaped HTML content. Throw `MailDeliveryError` containing only status and provider request ID; use an 8-second `AbortSignal.timeout`.
- [ ] **Step 4: Verify GREEN:** run the Task 1 test command and `pnpm --filter @kando/workers-api run type-check`; both exit 0.
- [ ] **Step 5: Commit:** `git add apps/workers-api/src/auth/mail.ts apps/workers-api/src/auth/mail.test.ts apps/workers-api/src/env.ts && git commit -m "feat(auth): add zeptomail verification sender"`.

### Task 2: Registration and Reset Delivery

**Files:** Modify `register.ts`, `forgot-password.ts`, and `anonymous.test.ts` under `apps/workers-api/src/auth/`.

- [ ] **Step 1: Add failing route tests** named `sends registration code because an issued code must reach its owner`, `invalidates registration code when delivery fails`, `sends reset code with reset purpose`, and `invalidates reset code when delivery fails`. Assert failure returns `503 / INTERNAL_ERROR` and the inserted row has non-null `used_at`.
- [ ] **Step 2: Verify RED:** `pnpm --filter @kando/workers-api exec vitest run src/auth/anonymous.test.ts -t "delivery|sends registration|sends reset"` fails because no mail request occurs.
- [ ] **Step 3: Generate `verificationCode` and `verificationCodeId` before each insert**, call `sendVerificationEmail` after a successful insert, and on delivery failure run:

```sql
UPDATE verification_code SET used_at = ? WHERE id = ? AND used_at IS NULL
```

Return the existing success body only after delivery succeeds. Log only `"Failed to send verification email."` plus the sanitized error.
- [ ] **Step 4: Verify GREEN:** run the focused test, full Worker tests, and Worker type-check; all exit 0.
- [ ] **Step 5: Commit:** `git add apps/workers-api/src/auth/register.ts apps/workers-api/src/auth/forgot-password.ts apps/workers-api/src/auth/anonymous.test.ts && git commit -m "feat(auth): deliver verification emails"`.

### Task 3: Google ID-Token Verification

**Files:** Modify `oauth-provider.ts`, create `oauth-provider.test.ts`, modify `env.ts`, `package.json`, and `pnpm-lock.yaml`.

- [ ] **Step 1: Add `jose`:** `pnpm --filter @kando/workers-api add jose@6.2.3`.
- [ ] **Step 2: Write failing tests** proving valid claims map `sub`/email, while wrong audience, wrong issuer, expiry, absent `sub`, absent email, and `email_verified !== true` return null. Inject a local JOSE key resolver so tests never call Google.
- [ ] **Step 3: Verify RED:** `pnpm --filter @kando/workers-api exec vitest run src/auth/oauth-provider.test.ts` fails on missing verifier.
- [ ] **Step 4: Implement:** use `jwtVerify` with issuer `accounts.google.com` or `https://accounts.google.com`, required audience `GOOGLE_CLIENT_ID`, and production `createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"))`. Export:

```ts
export async function resolveGoogleIdentity(
  idToken: string | null,
  clientId: string,
  keyResolver?: JWTVerifyGetKey,
): Promise<OAuthIdentity | null>;
```

- [ ] **Step 5: Verify GREEN:** run the focused test and Worker type-check; both exit 0.
- [ ] **Step 6: Commit:** `git add apps/workers-api/src/auth/oauth-provider.ts apps/workers-api/src/auth/oauth-provider.test.ts apps/workers-api/src/env.ts apps/workers-api/package.json pnpm-lock.yaml && git commit -m "feat(auth): verify google id tokens"`.

### Task 4: Google Callback Contract

**Files:** Modify `apps/workers-api/src/auth/oauth.ts` and `apps/workers-api/src/auth/anonymous.test.ts`.

- [ ] **Step 1: Replace mock-code tests** with ID-token tests covering new user, existing identity, guest migration, invalid token, and missing `GOOGLE_CLIENT_ID`.
- [ ] **Step 2: Verify RED:** focused Google OAuth tests fail because the route still parses `code`/`redirect_uri`.
- [ ] **Step 3: Change `GoogleOAuthCallbackInput` to `{ idToken, anonymousId }`, parse `id_token`, await `resolveGoogleIdentity(input.idToken, c.env.GOOGLE_CLIENT_ID)`, and return the existing 422 authorization response for any invalid configuration/token.
- [ ] **Step 4: Verify GREEN:** `pnpm --filter @kando/workers-api run test`, `type-check`, and `build` all exit 0.
- [ ] **Step 5: Commit:** `git add apps/workers-api/src/auth/oauth.ts apps/workers-api/src/auth/anonymous.test.ts && git commit -m "feat(auth): accept google id token callback"`.

### Task 5: Native Flutter Google Sign-In

**Files:** Modify Flutter authorizer/controller/repository/tests, `apps/flutter-app/pubspec.yaml`, root `pubspec.lock`, and `apps/flutter-app/ios/Runner/Info.plist`.

- [ ] **Step 1: Add dependency:** from `apps/flutter-app`, run `dart pub add google_sign_in:7.2.0`.
- [ ] **Step 2: Update failing controller tests** so Google authorization returns `idToken: "signed-google-id-token"`; assert the repository receives that token, cancellation is a no-op, missing token fails, and Apple input remains unchanged.
- [ ] **Step 3: Verify RED:** `flutter test test/auth_controller_test.dart` fails on the old code-based contract.
- [ ] **Step 4: Replace the Google result with `OAuthAuthorizationResult.google({required String idToken})`; implement `GoogleOAuthAuthorizer` using `GoogleSignIn.instance.initialize()` once and `authenticate()`, mapping cancellation to null and missing ID token to `OAuthAuthorizationException`. Keep the existing Apple mock branch.
- [ ] **Step 5: Change repository API to `googleCallback({required String idToken, String? anonymousId})` and send `{ "id_token": idToken, "anonymous_id": ... }`.
- [ ] **Step 6: Add `GIDClientID` and `CFBundleURLTypes` to `Info.plist` using the supplied client and reversed client IDs.
- [ ] **Step 7: Verify GREEN:** run `dart run melos run analyze`, `flutter test test/auth_controller_test.dart`, and `flutter test test/widget/auth_profile_test.dart`; all exit 0.
- [ ] **Step 8: Commit:** stage only the listed Flutter files and commit `feat(flutter): add native google sign in`.

### Task 6: Cloudflare Configuration and Documentation

**Files:** Modify `apps/workers-api/wrangler.toml` and the Resend/SES references in `docs/tcg-card/02-architecture/tech-stack.md`, `03-data-api/api-spec.md`, `03-data-api/data-model.md`, `05-plan/dev-plan.md`, `05-plan/external-deps-checklist.md`, and `README.md`.

- [ ] **Step 1: Add non-secret vars** `GOOGLE_CLIENT_ID`, `ZEPTOMAIL_API_URL`, `MAIL_FROM_ADDRESS`, and `MAIL_FROM_NAME` under `[vars]`; never commit `ZEPTOMAIL_TOKEN` or `JWT_SECRET`.
- [ ] **Step 2: Update scoped docs** to record ZeptoMail as the selected provider and remove only the resolved email-service decision markers.
- [ ] **Step 3: Verify local configuration:** `pnpm --filter @kando/workers-api run build` exits 0 and `git diff --check` reports no errors.
- [ ] **Step 4: On the correct Cloudflare account**, run `pnpm --dir apps/workers-api exec wrangler secret put ZEPTOMAIL_TOKEN`, deploy, then run `wrangler secret list`; verify the binding name appears without printing its value.
- [ ] **Step 5: Smoke-test** one registration and one password-reset delivery to an approved inbox; do not print codes. If the correct Worker remains unavailable, report this step as blocked rather than passed.
- [ ] **Step 6: Commit local config/docs:** stage only the files listed in this task and commit `docs: configure production auth providers`.

### Task 7: Final Verification

- [ ] Run `pnpm --filter @kando/workers-api run test`, `type-check`, and `build`; all exit 0.
- [ ] Run `dart run melos run analyze` and `dart run melos run test`; all exit 0.
- [ ] Run `git diff --check` and `git status --short`; report unrelated user changes separately.
- [ ] Confirm no tracked file contains `ZEPTOMAIL_TOKEN`, a Zoho token value, a verification code, or a changed `JWT_SECRET`.
