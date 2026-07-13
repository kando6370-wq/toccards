# M5-2 CardDetail Owned State Design

## Scope

Build the second CardDetail slice for cards already in the user's Portfolio.
This covers M5-2 from `docs/tcg-card/05-plan/dev-plan.md`: an owned card detail
shows the user's Collection Item records and keeps the existing price overview.

This slice stays mock-first. It does not implement Collection Item edit/delete,
the Price Tab chart and time ranges, sold listing details, real API calls,
Home refresh behavior, database changes, or any M7/Admin surface.

## Assumptions

- `charizard-ex` is the canonical owned sample because Search already shows it
  with `Qty: 1`.
- A quick Collect action should now create a local default Collection Item so
  the page can immediately switch from uncollected to owned state.
- Purchase price is user-entered cost data and remains separate from market
  price; missing purchase price displays `--`.

## Recommended Approach

Extend the existing `features/card_detail` files instead of creating a second
owned-detail feature. Add a small `CardCollectionItem` model and expose formatted
Collection Item rows from `CardDetailState`.

Owned details render a `Collection Item` section by default and retain access to
the existing `Price overview`. The uncollected page keeps its current basic info,
price overview, Collect, and Wishlist behavior until Collect is tapped.

## Alternatives Considered

1. Reuse `CollectionItem` from the Collection feature. This would save a type,
   but it couples CardDetail to list-specific sorting/filtering fields and makes
   CardDetail harder to evolve for M5-4 edit forms.
2. Add a backend-backed CardDetail repository now. This is premature for the
   current mock-first Flutter slice and would touch broader API concerns.
3. Extend the existing CardDetail model. This is the selected option because it
   keeps the change local and matches the M5-1 structure.

## Behavior

For `charizard-ex`, CardDetail renders owned state:

- title `Charizard ex`
- basic information matching Search/Collection mock data
- total quantity `1`
- `Collection Item` content with portfolio `Main`
- grader/grade `PSA 10`
- purchase price formatted in the selected currency
- notes
- no Wishlist heart
- price overview still available

For uncollected cards, quick Collect sets quantity to `1`, clears Wishlist, and
adds a default Collection Item:

- portfolio `Main`
- grader `Raw`
- condition `Near Mint`
- missing purchase price `--`

Unknown card ids still use the shared failure block and refresh behavior from M5-1.

## Data Flow

`CardDetailPage(cardId)` continues to watch
`cardDetailControllerProvider(cardId)`. The controller loads mock card detail
data and derives:

- `detail.isCollected`
- `collectionItemRows`
- market price and 30D change text
- purchase price text in the selected app currency

No global Collection state is mutated in this slice. That keeps the mock UI local
and avoids inventing cross-page cache invalidation before the real API layer is
connected.

## Testing

Use TDD:

- controller tests prove owned detail exposes Collection Item rows, purchase
  price formatting follows selected currency, and quick Collect creates a
  default owned item while clearing Wishlist.
- widget tests prove owned CardDetail defaults to Collection Item content, hides
  Wishlist UI, can show the existing price overview, and uncollected quick Collect
  switches to owned content.
- Search widget test proves tapping owned `charizard-ex` opens owned CardDetail.

Completion verification remains:

- `flutter pub get`
- `dart run melos run test`
- `flutter analyze`
- `dart format --set-exit-if-changed lib test`
