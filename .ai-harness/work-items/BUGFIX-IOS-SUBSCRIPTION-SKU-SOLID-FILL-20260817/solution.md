# iOS Subscription SKU Solid Fill

## Root Cause

- The selected iOS SKU uses a translucent accent fill, so the paywall artwork remains visible through the tile and creates a perceived gradient.
- Lifetime adds an iOS-only 8px top padding on top of the shared 12px bottom spacing.
- The selected tile is 77px while the other two tiles are 74px.

## Implementation

- Use the screenshot-sampled solid selected surface `#38372D` for the iOS sheet only.
- Keep the Figma `2228:18613` border, glow, radio, text, badge, and 17px horizontal padding unchanged.
- Set every iOS sheet SKU tile to 74px and use one 12px gap between adjacent tiles.
- Keep `selected` independent from `enabled`, so purchase-in-flight still disables interaction without clearing the selected visual.

## Scope

- UI only: `subscription_page.dart`, its focused widget test, the existing sheet Golden, and the v1.1 delivery note.
- No purchase, Restore, entitlement, routing, product, Android, or full-page changes.
