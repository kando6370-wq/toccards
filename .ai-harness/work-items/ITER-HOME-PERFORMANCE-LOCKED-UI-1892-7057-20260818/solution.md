# Solution: Home Performance Locked UI

## Scope

- Authoritative visual source: Figma file `DjacfTioobtRy59SnqH7SY`, node `1892:7057`.
- Replace the private `_PerformanceLockedPanel` presentation with the shared
  `KandoPremiumLockedPanel` component and keep Home responsible only for its
  Performance copy, keys, and existing `onUnlock` callback.
- Preserve the existing Free/Pro branch, Performance API loading boundary, Paywall callback, purchase/restore behavior, routing, analytics, and Pro data states.

## Figma Mapping

- Keep the panel at `350x427` on the 390px baseline with a 12px radius.
- Clip and blur the existing page background with `BackdropFilter(sigmaX: 12, sigmaY: 12)`, then apply the top-to-bottom translucent olive gradient, 10% gradient border, and `0 25 50 rgba(0,0,0,0.25)` shadow.
- Position the `284x222` content group at `x=33`, `y=63` instead of vertically centering it.
- Use the Figma source SVGs for the 26px lock, 16px button-leading icon, and 16px arrow; do not substitute Material icons.
- Match the 56px lock overlay, 6px icon/text and title/body gaps, 20px content/button gap, 24/32 title, 15/22 body, and 13/16 button label.
- Keep the full-width 284x36 accent pill button and route its press to the existing `onUnlock` callback.

## Platform And Behavior

- iOS and Android use the same Flutter widget and local SVG assets.
- No platform API, permission, dependency, native code, controller, repository, API, schema, migration, or data fixture changes.
- Free users continue to receive no Performance API request and no underlying demo data. Pro rendering remains unchanged.

## Verification

- Add focused widget assertions for dimensions, positions, exact SVG asset references, and unchanged Free/Pro visibility behavior.
- Add a 350x427 focused Golden and visually compare it with Figma node `1892:7057`.
- Run focused Home widget tests, Flutter analyze for the app, formatting check, and `git diff --check` through the Harness runtime.
- Inspect the final diff to confirm that only presentation code, local SVG assets, tests, and the Golden changed.

## Documentation

- N/A: this is a visual correction to an already-authoritative Figma node and existing UI design-system contract; no behavior, API, configuration, architecture, deployment, or operations documentation changes.

## Risk And Rollback

- Main risk: platform SVG or font rasterization may create small pixel differences. Geometry and source vector paths are fixed by tests and the 390px baseline Golden.
- Rollback is limited to the shared panel, the Home call site, its three local
  SVG assets, the focused test, and its Golden.
