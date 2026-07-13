# M5-3 CardDetail Price Tab Design

## Scope

Build the mock-first Price Tab slice for CardDetail. This covers M5-3 from
`docs/tcg-card/05-plan/dev-plan.md`: market prices by condition or grade, a
price-series area with range switching, and sold listing rows.

This slice does not add a real chart library, backend API calls, edit/delete
Collection Item flows, Home refresh behavior, database changes, or M7/Admin code.
The chart area is represented by range controls plus formatted series points so
the data contract and UI behavior are testable before visual chart polish.

## Assumptions

- Use the dev-plan range contract `7 / 30 / 90 / 180 / 365` days.
- Keep existing `Price overview` text so M5-1/M5-2 tests and user flow remain
  understandable.
- Existing market price rows continue to power the page header. Price Tab adds
  richer rows for `Market Prices` and `Sold listings`.
- Missing-data specialty states stay for M5-5. This slice includes normal rows
  and basic empty-list rendering only.

## Recommended Approach

Extend the existing `features/card_detail` model and controller:

- Add `CardPriceRange`, `CardPricePoint`, and `CardSoldListing`.
- Add series data and sold listings to `CardDetail`.
- Add derived controller rows for selected range, market prices, and sold
  listings.
- Add `selectPriceRange()` to the controller.

Update `CardDetailPage` so both uncollected and owned Price views use the same
full Price Tab widget:

- range selector
- price-series data area
- market prices
- sold listings

## Alternatives Considered

1. Add a real chart dependency now. This would make M5-3 look richer but expands
   dependency and visual QA risk before the data model is stable.
2. Build Price Tab as a separate route. This conflicts with the PRD tab model and
   would split CardDetail state across pages.
3. Extend the existing CardDetail feature. This is selected because it keeps the
   change local, preserves M5-1/M5-2 behavior, and avoids M7/Admin conflicts.

## Behavior

For `charizard-ex`, Price Tab shows:

- default selected range `30D`
- price-series rows ending at `$780.00`
- range buttons for `7D`, `30D`, `90D`, `180D`, `365D`
- `Market Prices` rows such as `PSA 10` and `Raw Near Mint`
- `7D` change text for market rows
- sold listings with date, title, platform, and formatted price

Changing the selected range updates only the series rows. Market rows and sold
listings remain stable because they are separate data sections.

For `mystery-promo`, existing market price fallback remains `--` and `-/-`.
M5-5 will add the dedicated no-data chart and public-data-unavailable states.

## Testing

Use TDD:

- controller tests prove default range, range switching, currency formatting,
  market rows, and sold listing rows.
- widget tests prove uncollected CardDetail renders the full Price Tab, owned
  CardDetail can switch to Price, range buttons update visible data, and sold
  listings are visible.

Completion verification remains:

- `flutter pub get`
- `dart run melos run test`
- `flutter analyze`
- `dart format --set-exit-if-changed lib test`
