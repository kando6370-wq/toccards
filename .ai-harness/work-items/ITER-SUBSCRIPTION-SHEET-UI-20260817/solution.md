# Solution: Subscription Bottom Sheet UI

## Scope

- Authoritative visual source: Figma file `DjacfTioobtRy59SnqH7SY`, node `1651:9915`.
- Change only the iOS Flutter presentation used when `SubscriptionPage.sheet == true`; Android keeps the existing sheet UI.
- Preserve the full-page subscription presentation and every purchase, restore, entitlement, routing, analytics, and source-resume callback.

## UI Mapping

- Use the exported background-only child node `1651:11958` as a local Flutter asset so the Charizard card composition, glow, gradient, border, and top corners match Figma without rebuilding decorative layers in code.
- Keep the existing 390px baseline and 20px horizontal content margins.
- Sheet benefit rows use the Figma 50px height, 8px radius, translucent `#1A1C14` surface, `#2A2D20` border, 24px accent check overlay, 14px label, and 4px row gap.
- Sheet plan rows keep the existing dynamic product data and callbacks, while applying the Figma 76px height, 12px radius, dark gradient, selected accent surface/border/glow, 20px custom radio, and plan-specific badge treatment.
- Move only the sheet handle to the Figma top offset. Full-page layout remains unchanged.

## Platform Scope

- The new Figma presentation is enabled only when `defaultTargetPlatform == TargetPlatform.iOS`; Android continues to render the existing background, benefit rows, plan rows, badges, radio controls, spacing, and handle position.
- No new package, platform API, permission, entitlement, configuration, or native bridge is introduced.
- Narrow screens continue to scroll through the existing `CustomScrollView`; the background scales from the 390px design baseline.

## Data And API

- Database impact: none.
- API, query, write, schema, migration, and transaction impact: none.
- Subscription product IDs, prices, availability, selection state, and purchase/restore invocation remain sourced from the existing controller.

## Verification

- Format and analyze the touched Dart source.
- Run the focused subscription restore/presentation widget tests.
- Pin the bottom-sheet Golden case to iOS, regenerate and run it at 390x844, then visually inspect the render against Figma `1651:9915`.
- Assert directly that Android keeps the old composed-card background while iOS selects the new exported background.
- Review the final diff to confirm no controller, router, API, or business callback changed.

## Documentation

- Update `docs/releases/v1.1.0/05-delivery/development-plan.md` with the new Figma node and verified visual scope.

## Risk And Rollback

- Main risk: bitmap scaling or text fallback can produce visual drift on non-390 widths. Widget layout remains responsive and the 390px Golden is the exact baseline.
- Rollback is limited to the subscription page presentation file, the new/updated visual asset and Golden, and the v1.1 delivery note.
