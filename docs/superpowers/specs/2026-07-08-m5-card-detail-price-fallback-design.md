# M5-5 CardDetail Price Fallback States Design

## Scope

Build the M5-5 price fallback slice for CardDetail. This covers the Price Tab
states called out by `docs/tcg-card/05-plan/dev-plan.md`: missing market prices
render as `--`, missing change values render as `-/-`, and a missing price
series renders `No price data available.`.

This slice stays local to Flutter CardDetail. It does not add backend calls,
new mock repositories, chart dependencies, admin code, database schema changes,
or global Home/Collection valuation refresh logic.

## Assumptions

- `mystery-promo` remains the mock card for missing public price data.
- Existing header fallback behavior (`--` and `-/-`) is correct and must remain.
- A missing price series is represented by an empty
  `priceSeriesByRange[selectedPriceRange]` list.
- Sold listings with no rows should use a local empty-state message rather than
  the full-page `No content available` failure block.
- Public-card unavailable three-line messaging is outside this slice and remains
  owned by future backend public-card status work; M5-5 only implements the
  empty-data fallback described in the dev-plan.

## Recommended Approach

Extend the existing controller-derived state and Price Tab UI:

- Add controller getters that describe whether the selected price series is
  empty and whether sold listings are empty.
- Keep market rows derived from `CardMarketPrice`; the existing currency
  formatter already emits `--` for missing prices, and `MarketChange` already
  emits `-/-` for missing changes.
- Render `No price data available.` in the `Price series` section when the
  selected range has no rows.
- Render `No sold listings available.` in the `Sold listings` section when the
  sold listing list is empty.
- Keep all non-empty Price Tab behavior unchanged.

## Alternatives Considered

1. Add a new mock repository scenario with separate partial failures. This would
   broaden test setup without changing user-visible behavior for M5-5.
2. Add route-level or section-level loading/error state objects. That is useful
   once real API calls exist, but is premature for the current mock-first slice.
3. Reuse the global failure block for empty sections. This conflicts with the
   product distinction between no data and a failed page load.

The selected approach is the smallest local change and avoids conflicts with
M7/Admin or future backend work.

## Behavior

For `mystery-promo`:

- Header market price remains `--`.
- Header 30D change remains `-/-`.
- Price Tab Market Prices row renders `Raw`, `--`, and `7D -/-`.
- Price series renders `No price data available.` for the selected range.
- Sold listings renders `No sold listings available.`.

For existing cards with data:

- Price series rows continue to render normally.
- Market Prices continue to render formatted prices and 7D changes.
- Sold listings continue to render listing rows.
- Range switching continues to update only the visible series rows.

## Testing

Use TDD:

- Controller tests prove missing Price Tab market rows keep `--` and `-/-`, the
  selected price series is empty, and sold listings are empty.
- Widget tests prove `mystery-promo` renders the price-series empty copy, market
  fallback values, and sold-listings empty copy.
- Existing CardDetail and Search tests continue to protect non-empty paths and
  navigation.

Completion verification remains:

- `flutter test test/card_detail_controller_test.dart`
- `flutter test test/widget/card_detail_page_test.dart`
- `flutter test test/widget/search_page_test.dart`
- `flutter pub get`
- `dart run melos run test`
- `flutter analyze`
- `dart format --set-exit-if-changed lib test`
