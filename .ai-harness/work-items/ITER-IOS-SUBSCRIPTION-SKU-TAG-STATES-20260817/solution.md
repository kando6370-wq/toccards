# iOS Subscription SKU Tag States

## Scope

- Match active Tag node `2228:18625` and inactive Tag node `2228:18638` in the updated iOS Subscription Sheet.
- Preserve each plan's existing Tag copy while switching visual state with the plan's selected state.
- Keep subscription selection, availability, purchase, Restore, routing, Android, and full-page behavior unchanged.

## Implementation

- Extract the existing inline plan Tag into a private widget in `subscription_page.dart`.
- Drive the updated iOS Tag background and border from `isSelected`, not from the plan ID.
- Apply the Figma 30px height, 9px horizontal padding, pill radius, 10px bold text with 15px line height, and 6px clipped backdrop blur.
- Preserve the existing non-updated Tag appearance.
- Add stable widget keys and extend the iOS selection regression to assert both Tag states before and after switching plans.
- Update the existing 390x844 Golden and v1.1 delivery documentation.

## Database Impact

None. This is a Flutter presentation-only change.

## Verification

- Run the focused selection-state test and full subscription widget test file.
- Update and rerun the iOS Sheet Golden.
- Run Flutter analyze, Dart format check, task-path diff checks, and Harness CI check.
