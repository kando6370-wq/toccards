# Solution: Shared Premium Locked Panel

## Scope

- Add a reusable `KandoPremiumLockedPanel` under `apps/flutter-app/lib/shared/ui`.
- Expose title, message, button label, button callback, and stable widget keys as constructor inputs.
- Keep the Figma `1892:7057` lock treatment and three original SVG assets as the component defaults.
- Connect only Home Performance in this task; other future call sites remain out of scope.

## Component Boundary

- The shared component owns panel dimensions, backdrop blur, gradient surface and border, shadow, icon treatment, typography, spacing, and CTA layout.
- Home owns the `Portfolio Performance` copy and passes its existing `onUnlock` callback without wrapping or changing behavior.
- The component depends only on Flutter Material, `flutter_svg`, local assets, and existing `KandoColors`.

## Platform And Data

- One Flutter implementation is used by iOS and Android.
- Database/API impact: none. No entitlement state, requests, controller, router, purchase, restore, analytics, or native platform code changes.

## Verification

- Assert the shared component receives the Home callback and renders exact geometry and SVG asset references.
- Use the focused Figma Golden and the existing Free/Pro Home tests as visual and business-boundary regression coverage.
- Run format, focused and full Home widget tests, Flutter analyze, and diff checks.

## Documentation

- N/A: the reusable component implements the existing Figma/UI contract without changing product behavior or architecture.

## Risk And Rollback

- The component is presentation-only and private state-free. Rollback removes the shared file and restores the Home-local presentation.
