# M5-1 CardDetail Uncollected State Design

## Scope

Build the first CardDetail slice for cards that are not yet in the user's Portfolio.
This covers the M5-1 requirement from `docs/tcg-card/05-plan/dev-plan.md`: a Search
result can open CardDetail, the page shows basic card information and price overview,
and the user can quick Collect or Wishlist the card.

This slice does not implement the owned Collection Item tab, edit/delete flows,
price chart time ranges, sold listing details, real API calls, camera scanning, or
any M7/Admin surface.

## Recommended Approach

Use a new Flutter feature folder:

- `apps/flutter-app/lib/features/card_detail/card_detail_models.dart`
- `apps/flutter-app/lib/features/card_detail/card_detail_repository.dart`
- `apps/flutter-app/lib/features/card_detail/card_detail_controller.dart`
- `apps/flutter-app/lib/features/card_detail/card_detail_page.dart`

Register `/cards/:cardId` in `app/router.dart`, and make Search card tiles navigate
to that route when the card body is tapped. The feature stays mock-first and mirrors
the existing Home/Search/Collection pattern: model file, repository interface with
mock data, Riverpod controller, widget page, controller tests, widget tests.

## Alternatives Considered

1. Reuse `SearchCard` directly as the detail model. This is smaller at first, but it
   couples a richer detail page to list-specific fields and makes M5-2/M5-3 harder.
2. Put the detail state inside `SearchController`. This would avoid a new provider,
   but it makes Search responsible for a separate page and blocks Collection/Home
   detail entry points later.
3. Create a new CardDetail feature. This adds a few small files, but keeps boundaries
   clear and lets later M5 tasks grow without reshaping Search.

The selected option is 3.

## Behavior

For `squirtle`, the uncollected detail page renders:

- title `Squirtle`
- game `Pokemon`
- set `Mega Evolution Promos`
- identity line `Promo #039`
- finish `Holofoil`
- language `English`
- market price formatted in the selected app currency
- 30D change percentage
- a Price overview section with market rows
- `Collect` and Wishlist quick actions

Quick Collect sets local detail state to quantity 1 and clears Wishlist, matching the
Search quick action rule that Portfolio and Wishlist cannot both hold the same card.
Wishlist toggles only while the card is uncollected. A missing market price displays
`--` and missing change displays `-/-`.

## Data Flow

`CardDetailPage(cardId)` watches `cardDetailControllerProvider(cardId)`.
The controller reads `cardDetailRepositoryProvider` and `selectedCurrencyProvider`.
It loads a mock `CardDetail` by id and exposes derived text for UI formatting.

Unknown ids and repository failures use the existing shared failure copy:
`No content available` and `Refresh`. Refresh reloads from the repository for the
same card id.

## Search Integration

`SearchPage` keeps the existing Collect and Wishlist buttons. Only the card body is
made tappable, with route `context.go('/cards/${card.id}')`. This avoids changing
the current quick-action behavior and keeps the Search scanner icon as the existing
coming-soon Toast.

## Testing

Use TDD:

- controller tests prove the detail model loads, currency formatting changes market
  text, missing prices degrade to PRD fallback text, Collect clears Wishlist, and
  repository failure can recover on refresh.
- widget tests prove the uncollected page renders the intended fields, does not show
  Collection Item or Remove from Portfolio UI, and quick actions update visible state.
- Search widget route test proves tapping a card opens `/cards/:cardId`.

Full completion gate remains the Flutter chain used in M4:

- `flutter pub get`
- `dart run melos run test`
- `flutter analyze`
- `dart format --set-exit-if-changed lib test`
