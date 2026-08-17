# Home Performance Header Solution

## Scope

- Adapt Figma `1911:8120` to the existing Flutter `_PerformanceSection`.
- Adapt Figma `2209:15661` as an anchored overlay above the subtitle info icon.
- Keep the existing folder picker, Performance API, entitlement, chart, and amount state contracts.

## UI design

- Header height remains 56px: 32px title row, 4px gap, and 20px subtitle row.
- `PERFORMANCE` uses the existing Fraunces/Baskerville mapping at 24/32, followed by the existing 24px amount visibility control with an 8px gap.
- The subtitle keeps the current truthful copy because the API does not expose the count of items with purchase prices. A 13px Figma info control follows at a 4px gap.
- The info overlay is 242x53.5px, centered above the icon with a 3px anchor gap. It contains a 242x46px black modal surface, 8px horizontal/9px vertical padding, 10/14 white copy, and the exported 19x7.5px notch.
- The overlay is inserted into the root Overlay so it remains above Home content. Tapping outside, selecting the chart, changing range/folder/tab, or disposing the section removes it.

## Behavior and data

- The title eye reuses `HomeController.toggleAmountHidden`; no new state or persistence path is introduced.
- The info overlay only explains the existing purchase-price calculation rule and does not change Performance calculations.
- No API, schema, query, transaction, migration, dependency, or platform channel changes.

## Verification

- Widget tests cover icon assets, exact visible sizes/gaps, amount hiding, overlay size/position/copy, toggle/dismissal, and existing chart mutual exclusion.
- Header and overlay Golden baselines protect the two Figma nodes.
- Run Flutter analysis, iOS test-flavor simulator build/install, simulator screenshot inspection, and `git diff --check`.
- Android build is outside this task per the user's latest platform scope.
