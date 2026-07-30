# Production Authentication Integration Design

## Goal

Replace the current mock Google sign-in path with production iOS Google sign-in and connect registration/password-reset verification emails to Zoho ZeptoMail, while preserving the existing account-linking, guest-migration, and JWT session behavior.

## Credentials and Configuration

- Worker binding `GOOGLE_CLIENT_ID` contains `134647928937-abbkvdc4ntfsui9utm828bc1vhgabdmo.apps.googleusercontent.com`.
- iOS `CFBundleURLSchemes` contains `com.googleusercontent.apps.134647928937-abbkvdc4ntfsui9utm828bc1vhgabdmo`.
- `JWT_SECRET` remains an independent random signing secret and is never derived from either Google identifier.
- The reversed client ID is an iOS URL scheme, not a Worker secret.
- Worker secret `ZEPTOMAIL_TOKEN` contains the ZeptoMail Send Mail token.
- Worker variables `ZEPTOMAIL_API_URL`, `MAIL_FROM_ADDRESS`, and `MAIL_FROM_NAME` select the Zoho data-center endpoint and verified sender identity without embedding deployment values in code.

## Chosen Approach

The Flutter app uses the native Google Sign-In SDK to obtain an ID token. The Worker verifies the token signature through Google's published JWKS, checks issuer, expiry, and `aud` against `GOOGLE_CLIENT_ID`, then maps `sub` and verified email into the existing OAuth account flow.

This supersedes the older authorization-code exchange contract for Google. That path would require a Google Client Secret that is not available. Apple OAuth remains unchanged.

Zoho ZeptoMail's HTTPS API is used for transactional mail. Direct SMTP is excluded because it adds socket/TLS complexity in Cloudflare Workers, while Zoho Mail OAuth is excluded because it requires refresh-token lifecycle management that ZeptoMail avoids.

## Components and Data Flow

1. Add the established Flutter Google Sign-In package and configure the iOS client ID and reversed URL scheme.
2. Replace only the Google branch of `OAuthAuthorizer`; cancellation returns no result and does not alter auth state.
3. Send `id_token` and optional `anonymous_id` to `POST /api/v1/auth/oauth/google/callback`.
4. The Worker validates the ID token with a maintained JWT/JWKS library compatible with Cloudflare Workers.
5. A valid token produces the existing `{ provider, providerUid, email }` identity and reuses `completeOAuthAccountFlow` unchanged.
6. Invalid, expired, wrong-audience, or unverified-email tokens return the existing authorization failure response without exposing provider details.

## Verification Email Components and Data Flow

1. Add a narrow mail-sender interface and a ZeptoMail implementation that calls the configured HTTPS endpoint with `Authorization: Zoho-enczapikey <token>`.
2. Registration and password-reset send-code routes generate the existing six-digit code and persist its existing verification/expiry record.
3. Send a purpose-specific plain-text and HTML message from the verified Zoho sender. Dynamic values are escaped, and codes or tokens are never logged.
4. If ZeptoMail rejects or times out, invalidate the newly created verification record and return a retryable service error. A failed delivery must never leave a usable unseen code.
5. Existing code expiry, resend invalidation, verification, password reset, and account creation rules remain unchanged.

The provider response ID may be logged for delivery diagnosis, but the API token, recipient verification code, and complete response body must not be logged.

## Cloudflare Deployment

Configure `GOOGLE_CLIENT_ID` for the deployed Worker using Wrangler secret/config bindings, consistent with the treatment of runtime authentication configuration. Verify by listing binding names; secret values must never be printed.

Configure `ZEPTOMAIL_TOKEN` as a Worker secret. Configure the ZeptoMail API URL and verified sender identity as non-secret Worker variables. The exact URL must match the ZeptoMail account's data center; production sending is blocked until a Send Mail token and verified sender address are supplied.

Current blocker: the locally authenticated Cloudflare account (`product@kando.com.cn`) does not contain the configured Worker `toccards`. Cloud configuration and deployment verification require the correct account or Worker name.

## Testing and Acceptance Criteria

- Backend tests explain why forged, expired, wrong-audience, and unverified-email tokens must be rejected.
- Backend tests prove a verified Google identity still uses existing login, registration, and guest-migration rules.
- Flutter tests cover successful sign-in, user cancellation, provider failure, and ID-token absence.
- Worker type-check, test, and dry-run build pass.
- Flutter analyze and focused auth tests pass.
- iOS contains the supplied URL scheme, `JWT_SECRET` remains unchanged, and no credential value is committed as a private secret.
- Mail tests prove registration and password-reset messages use the correct purpose and expiry copy without exposing the code in logs or API responses.
- Failure tests prove a ZeptoMail error invalidates the generated code and returns a retryable error instead of reporting success.
- Focused route tests use an injected fake sender; no test calls Zoho over the network.
- A production smoke test sends one registration code and one password-reset code to an approved inbox and verifies receipt without printing either code.

## Scope Exclusions

- No Apple OAuth changes.
- No unrelated auth, UI, schema, or migration refactors.
- No Cloudflare deployment until the target account and Worker are resolvable.
- No bulk, marketing, feedback-notification, or admin email flows.
