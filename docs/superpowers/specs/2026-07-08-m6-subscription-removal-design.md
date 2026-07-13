# M6-6 Subscription Removal Design

## Scope

Complete the M6-6 subscription removal/hiding requirement before M7/Admin work
begins. The Flutter app must not expose subscription entry points, buttons,
badges, entitlement copy, restore-purchase UI, or a Customer Support
`Subscription` function option.

This slice is Flutter-only verification and regression coverage. It does not
modify Workers, D1 schema or migrations, admin web, or `docs/tcg-card/**`.

## Existing State

A source scan of `apps/flutter-app/lib` finds no subscription UI strings such as
`Upgrade to Pro`, `Subscribe`, `Subscription`, `PRO`, `Unlock All`,
`Go unlock`, or `Restore`. The Customer Support widget test already checks that
`Subscription` is absent from the Function chips. There is no production UI to
remove in the current Flutter surface.
The scan may match internal auth restore helper names; those are not visible
subscription or purchase-restore UI.

## Recommended Approach

Add a focused regression test that exercises the app surfaces most likely to
accidentally reintroduce subscription content:

- guest Profile
- signed-in Profile
- Account details
- Customer Support

The test asserts that subscription-related visible text is absent. Production
code stays unchanged because the requirement is already satisfied by current UI.

## Alternatives Considered

1. Change production code despite no matching UI. This would create churn with
   no user-visible improvement.
2. Rely only on manual `rg` scans. This proves the current state but does not
   guard future regressions.
3. Add a broad source-reading test over every Dart file. That would be brittle
   and would flag legitimate test names or unrelated words such as `restored`.

The selected approach gives M6-6 durable coverage with minimal code.

## Behavior

The Flutter app must not show:

- `Upgrade to Pro`
- `Subscribe`
- `Subscription`
- `PRO`
- `Unlock All`
- `Go unlock`
- `Restore`

Customer Support keeps the Function options from M6-3 and excludes
`Subscription`.

## Testing

Use a focused widget regression test plus deterministic source scan evidence:

- Add a widget test that navigates through guest Profile, signed-in Profile,
  Account, and Customer Support and verifies subscription copy is absent.
- Run the test. If it passes immediately, treat this as verification of already
  implemented behavior rather than a production-code change.
- Run full Flutter verification before marking `[M6-6]` complete.
