# Solution

## Scope

- Only update the iOS `presentation=sheet` subscription UI.
- Preserve Android, the full Subscription Page, purchase/restore behavior, entitlement state, routes, and product selection data.

## Root causes

1. The sheet wrapper applies `Padding(top: 32)` around the complete `content` stack, so the iOS background starts 32 px below the rounded sheet top while the handle is positioned separately at 21 px.
2. The exported background contains a bright antialiased edge at its rightmost pixels. The current 1 px transform overscan does not fully remove that sampled edge.
3. `_PlanTile` derives its selected visual from `selected && enabled`. Starting purchase disables the tile, so the selected border, fill, glow, radio, and price emphasis disappear even though `selectedPlanId` has not changed.
4. The iOS tile uses the legacy 76 px geometry and incomplete text metrics instead of Figma pricing node `1651:9993`.

## UI-only fix

- Render the updated iOS background as the bottom layer of the outer rounded sheet stack, outside the 32 px content padding. Keep the existing padding for scroll content and actions so their positions do not change.
- Omit the duplicated inner background only for the updated iOS sheet. Android and full-page branches retain the existing structure.
- Replace the 1 px transform with an explicit 2 px top-left-aligned overscan inside a clipped viewport, excluding the PNG's right antialias edge.
- For the updated iOS SKU tiles, use Figma geometry and typography: 74 px inactive height, 77 px active height, 17 px horizontal padding, 18/22 title, 16/24 inactive price, 18/27 active price, and 12/16 `#999578` period text.
- Drive the updated iOS selected visuals from `selected` alone. Continue using `enabled` only for tap availability and unavailable-state affordances. Keep the legacy Android behavior unchanged.

## Verification

- Update and inspect the 390x844 subscription Sheet Golden, including top-right and right-edge crops.
- Add a widget regression proving that an iOS selected SKU keeps its selected surface after Subscribe enters an in-flight state.
- Run the iOS Golden test, platform isolation test, subscription restore/purchase UI tests, Flutter analyze, Dart format check, and `git diff --check`.
