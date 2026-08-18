# Pro Scan Quota Contract Bugfix

## Root Cause

- `GET /scan/quota` returns `access` and `unlimited`, while successful and exhausted `POST /scan/recognize` quota payloads omit them.
- Flutter treats a missing `unlimited` value as `false`, then replaces the authoritative quota state with that downgraded value.
- Scan presentation and preflight checks primarily use local `SubscriptionState.isPro`; a locally stale `free` state is allowed to proceed without one final entitlement refresh.

## Fix

1. Build all quota responses through one Workers helper containing `access`, `unlimited`, `limit`, `reserved`, `consumed`, and `remaining`.
2. Parse `access` and `unlimited` as required Flutter protocol fields. Missing or invalid fields fail explicitly instead of becoming Free.
3. Treat local Premium or server `unlimited` as effective Premium for Scan UI, quota blocking, and the protective request header.
4. Before the first Free-classified scan on a page lifecycle, refresh StoreKit entitlement once. Reset this confirmation when the app resumes. Unknown remains blocked; confirmed Free may scan normally.
5. Change `_viewfinderTop` from `193` to `213`; the shared constant continues to drive both visual placement and recognition crop.

## Compatibility

- The API change only adds fields to existing quota objects. Deploy Workers before or with the Flutter client because the corrected client intentionally rejects legacy quota objects that omit the required entitlement fields.
- No endpoint, status code, request body, database table, index, migration, quota formula, OCR behavior, or idempotency behavior changes.
- The shared Flutter implementation applies to iOS and Android. StoreKit refresh remains iOS-specific through the existing subscription adapter; unsupported platforms preserve their existing explicit Free/Unknown behavior.

## Verification

- Workers route tests: Free and Premium recognize responses expose the complete quota contract; Premium records remain excluded from Free usage.
- Flutter API tests: complete payload parses; missing `access` or `unlimited` fails.
- Flutter widget tests: server Unlimited hides Free quota even when local state is Free; stale local Free refreshes before scanning; confirmed Free still respects exhaustion.
- Existing scan tests, targeted Workers tests, Flutter analyze, and diff checks.

## Documentation

- Update the v1.1 Scan API contract with the unified quota payload.
- Update the v1.1 delivery status from viewfinder top `193` to `213` and record the entitlement merge behavior.
