# Solution

## Scope

Only the iOS subscription Bottom Sheet SKU visual transition changes. Product
selection, availability, purchase, restore, pricing, routes, and Android UI stay
unchanged.

## Root cause

The current `AnimatedContainer` transitions between a selected solid `color`
and an unselected `gradient` while also interpolating its border. Those
decoration channels do not read as one transition, so the old accent border
appears to leave before the selected surface.

## Fix

Keep the unselected gradient surface as the stable base. Fade a selected overlay
that owns the solid `#38372D` fill, accent border, and glow together. Selection
uses two 140ms phases: the old SKU fully exits first, then the new SKU enters.
Because each overlay owns its fill and border, those visuals share one opacity
progress. Use the same phase duration and curve for the SKU radio and badge.
Extend the existing iOS widget test to verify the enforced gap between the old
exit and new entry, plus the final selected state.

## Database and docs

No database, API, persistence, entitlement, or configuration impact. Update the
existing v1.1 delivery note because it already records this iOS SKU UI contract.
