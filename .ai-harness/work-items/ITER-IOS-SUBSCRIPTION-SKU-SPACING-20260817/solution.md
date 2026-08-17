# iOS Subscription Sheet SKU Spacing

## Scope

- Increase the two adjacent SKU gaps from 12px to 22px in the updated iOS Subscription Sheet only.
- Keep all three SKU surfaces at 74px high.
- Preserve the selected surface, badge, radio, purchase state, Restore flow, routing, Android UI, and full Subscription Page.

## Implementation

- Use the existing `useUpdatedSheetUi` boundary when selecting the SKU wrapper bottom padding: 22px for the updated iOS Sheet, 12px elsewhere.
- Update the existing widget regression assertions to require both adjacent gaps to be 22px while retaining the 74px and purchase-in-flight assertions.
- Regenerate and visually inspect the existing 390x844 iOS Sheet Golden.
- Update the v1.1 delivery baseline from 12px to 22px.

## Database Impact

None. This iteration changes Flutter layout values only.

## Verification

- Run the focused subscription widget regression suite.
- Update and rerun the iOS Sheet Golden.
- Run Flutter analyze, Dart format check, task-path diff check, and Harness CI check.
