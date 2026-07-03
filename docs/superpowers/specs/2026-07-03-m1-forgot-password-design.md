# M1 Forgot Password Flow Design

## Background

M1 already has anonymous accounts, current-account lookup, token refresh, logout, Email registration, and Email login. The next auth slice is the Email forgot-password flow defined by `docs/tcg-card/03-data-api/api-spec.md` sections 2.5 to 2.7.

This slice implements the Workers backend flow only. Flutter UI and real email-provider integration remain out of scope for this spec.

## Scope

Included:

- `POST /api/v1/auth/forgot-password/send-code`
- `POST /api/v1/auth/forgot-password/verify-code`
- `POST /api/v1/auth/forgot-password/reset`
- Reuse `verification_code` with `purpose = 'reset_password'`
- Generate and validate a short-lived signed `reset_token`
- Update `user.password_hash` with the existing PBKDF2 password hashing helper
- Workers integration tests for success, validation, expiry, replay, and failure cases

Excluded:

- Flutter Auth UI
- Real Resend / SES email sending
- OAuth password recovery
- Database schema or migration changes
- Session revocation after password reset

## Route Organization

Add `apps/workers-api/src/auth/forgot-password.ts` and register it from the existing auth route group.

The module owns only the forgot-password flow. Registration, login, refresh, logout, and current-account lookup remain in their existing modules.

## Data Model

Reuse the existing `verification_code` table:

- `email`: normalized Email address
- `code`: 6-digit code
- `purpose`: `reset_password`
- `expires_at`: `now + 10 minutes`
- `used_at`: null until reset succeeds
- `created_at`: creation timestamp

No new D1 table and no KV dependency are introduced.

## Reset Token

`verify-code` returns a short-lived signed token instead of storing a reset token.

Payload:

- `email`
- `verification_code_id`
- `exp`

Signing:

- Use `JWT_SECRET` as the signing secret.
- Token expiry is 10 minutes.
- Token is single-use by construction: `reset` only succeeds while the referenced verification code is still unused and unexpired, then marks that code used.

The token is not an access token and must not be accepted by auth middleware.

## Endpoint Behavior

### POST /auth/forgot-password/send-code

Request:

```json
{
  "email": "user@example.com"
}
```

Behavior:

1. Parse JSON body.
2. Normalize Email with trim and lowercase.
3. Validate Email with the existing Email rule.
4. Look up a live Email-password user: `email = ?`, `deleted_at IS NULL`, and `password_hash IS NOT NULL`.
5. If no such user exists, return the unregistered Email validation response.
6. Enforce resend throttling from the latest unused `reset_password` code created within 60 seconds.
7. Insert a new `verification_code` row with `purpose = 'reset_password'`.
8. Return `expires_in = 600` and `resend_after = 60`.

### POST /auth/forgot-password/verify-code

Request:

```json
{
  "email": "user@example.com",
  "code": "123456"
}
```

Behavior:

1. Parse and normalize Email.
2. Validate Email and 6-digit code format.
3. Select the latest `reset_password` verification code for the Email.
4. Return incorrect-code response when the code is missing or does not match.
5. Return expired-code response when the code is used or expired.
6. Sign a reset token containing the Email and verification code id.
7. Return the reset token.

### POST /auth/forgot-password/reset

Request:

```json
{
  "email": "user@example.com",
  "reset_token": "signed-token",
  "new_password": "new-password"
}
```

Behavior:

1. Parse and normalize Email.
2. Validate Email.
3. Validate `new_password` length is at least 8.
4. Verify reset token signature, expiry, and Email match.
5. Select the referenced reset verification code.
6. Return expired-code response if the code is missing, used, expired, or not tied to the Email and purpose.
7. Hash the new password.
8. Atomically update the live Email-password user and mark the verification code used.
9. Return `{ success: true, data: {} }`.

Password reset does not revoke existing sessions in this slice because the current API spec does not define that behavior.

## Error Responses

- Missing Email: `422 / VALIDATION_ERROR / Please enter your email.`
- Invalid Email: `422 / VALIDATION_ERROR / Please enter a valid email address.`
- Email not registered, soft-deleted, or OAuth-only: `422 / VALIDATION_ERROR / Email not registered. Please check your email or create a new account.`
- Invalid code format or wrong code: `422 / VALIDATION_ERROR / Incorrect verification code.`
- Used or expired code: `422 / VALIDATION_ERROR / Code expired. Please request a new code.`
- Invalid, mismatched, or expired reset token: `422 / VALIDATION_ERROR / Code expired. Please request a new code.`
- Password shorter than 8 characters: `422 / VALIDATION_ERROR / Password must be at least 8 characters.`
- Blank `JWT_SECRET`, D1 failure, hash failure, or signing failure: `500 / INTERNAL_ERROR / Something went wrong. Please try again.`

## Security Notes

- Reset tokens are short-lived and signed.
- Reset tokens are bound to both Email and verification code id.
- Reset tokens are single-use because the verification code is marked used during reset.
- OAuth-only users cannot use password reset because they have no `password_hash`.
- Soft-deleted users cannot use password reset.
- The flow intentionally tells users when an Email is not registered, matching the product and API spec.

## Tests

Workers integration tests should cover:

- Send code succeeds for a live Email-password user and writes `purpose = 'reset_password'`.
- Send code normalizes Email.
- Send code rejects unknown, soft-deleted, and OAuth-only users with the unregistered Email response.
- Send code rejects blank and invalid Email.
- Send code enforces 60-second resend throttling.
- Verify code returns a reset token for the latest matching unused code.
- Verify code rejects wrong, malformed, expired, and used codes.
- Reset succeeds, updates `password_hash`, and marks the verification code used.
- Reset token cannot be replayed after a successful reset.
- Reset rejects mismatched Email, malformed token, expired token, short password, and D1 failures.

## Acceptance Criteria

- `POST /api/v1/auth/forgot-password/send-code` matches API spec section 2.5.
- `POST /api/v1/auth/forgot-password/verify-code` matches API spec section 2.6.
- `POST /api/v1/auth/forgot-password/reset` matches API spec section 2.7.
- No schema or migration changes are required.
- Existing Email registration and login behavior remains unchanged.
- Local verification passes:
  - `pnpm --filter @kando/auth-core run test`
  - `pnpm --filter @kando/auth-core run type-check`
  - `pnpm --filter @kando/auth-core run build`
  - `pnpm --filter @kando/workers-api run test`
  - `pnpm --filter @kando/workers-api run type-check`
  - `pnpm --filter @kando/workers-api run build`
