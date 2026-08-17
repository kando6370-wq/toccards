# Solution: iOS Subscription Sheet Right Edge

## Root Cause

Figma node `1651:9915` clips background child `1651:11958` inside its 390px parent. The child starts at `left: 0.47px` with a 390px width, so its right export edge is outside the parent. The standalone PNG preserves that edge, while Flutter previously scaled the full PNG to the exact viewport width and made the last pixel column visible.

## Fix

- Keep the existing exported background asset and all content layout unchanged.
- In the iOS updated-sheet background branch only, paint the image one logical pixel wider from the top-left anchor and clip it to the existing viewport.
- The one-sided overscan removes only the exported right edge. It does not shift the left edge or alter Android and full-page branches.

## Scope

- UI only: `subscription_page.dart` background painting and the existing iOS sheet Golden.
- No purchase, Restore, entitlement, routing, product, API, database, configuration, or platform-bridge changes.
- Database impact: none.

## Verification

- Regenerate and rerun the iOS bottom-sheet Golden at 390x844.
- Inspect the rendered right-edge crop and full Golden against Figma `1651:9915`.
- Rerun the iOS/Android visual-branch test, subscription Restore UI tests, Flutter analyze, format check, and `git diff --check`.

## Documentation

- Update the existing v1.1 delivery note to state that the exported background edge is clipped to the Figma parent boundary.

