# M5 CardDetail Collection Item CRUD Design

## Goal

Build M5-4 for the Flutter CardDetail page: users can add, edit, and delete Collection Item records from the CardDetail view, with a grader-driven form that switches between Raw condition and graded grade fields.

## Source And Scope

- Plan source: `docs/tcg-card/05-plan/dev-plan.md` M5-4.
- Product source: `docs/tcg-card/00-product/modules/card-detail.md` sections 9 and 10.
- Current implementation source: `apps/flutter-app/lib/features/card_detail/*`.

This slice stays mock-first and local to CardDetail. It does not add backend clients, mutate Workers schema or migrations, modify Admin code, or wire the Home refresh behavior called out in the broader M5 acceptance notes.

## Recommended Approach

Use an inline edit mode inside the existing CardDetail page instead of introducing a new route. This keeps navigation stable for Search and Collection tests, reuses the existing `CardDetailController`, and avoids new route/state boundaries before real API persistence exists.

The Collection Item tab will show:

- An `Add item` action above the owned item list.
- One card per Collection Item with `Edit item` and `Remove from Portfolio` actions.
- An inline `Ownership Summary` form when adding or editing.

## State Model

Extend CardDetail state with a small edit draft:

- `collectionItemDraft`
- `editingCollectionItemId`
- `collectionItemFormError`

The draft stores string inputs for text fields and selected values for controlled fields:

- quantity text
- portfolio name
- grader
- condition
- grade
- purchase price text
- notes

The existing `CardCollectionItem` remains the persisted mock record shape. Add `copyWith` and replacement helpers only where needed.

## Form Rules

The form supports the fields already represented by the mock model:

- Quantity: positive whole number.
- Portfolio: mock options `Main`, `Sealed`, `Empty`, defaulting to the current item portfolio or `Main`.
- Grader: `Raw`, `PSA`, `BGS`, `SGC`, `TAG`, `CGC`, `AGS`.
- Raw grader shows Condition options.
- Non-Raw grader shows Grade options.
- Purchase price: optional decimal value.
- Notes: optional, max 500 characters.

Validation messages follow the product copy:

- `Please enter a quantity.`
- `Quantity must be at least 1.`
- `Quantity must be a whole number.`
- `Please enter a valid price.`
- `Notes must be 500 characters or less.`

For graded items, missing grade uses the same row fallback already used by the display layer. This keeps the mock flow permissive, matching the product rule that missing market price still allows save.

## Controller Behavior

Add controller methods:

- `startAddingCollectionItem()`
- `startEditingCollectionItem(String itemId)`
- `updateCollectionItemDraft(...)`
- `cancelCollectionItemEdit()`
- `saveCollectionItemDraft()`
- `removeCollectionItem(String itemId)`

Saving a new item appends a mock `CardCollectionItem` and marks the card collected. Editing replaces the matched item. Removing deletes the matched item and recomputes `quantity` as the sum of remaining item quantities. If no items remain, the detail returns to the uncollected state.

Wishlist remains false after adding a Portfolio item, preserving the Portfolio/Wishlist mutual exclusion rule already used by quick Collect.

## UI Behavior

When the draft is active, the Collection Item tab renders the form before the list. `Cancel` discards the draft. `Save changes` calls the controller and keeps the form visible with an error message if validation fails.

`Remove from Portfolio` opens a simple confirmation dialog. Confirming removes the item. If that was the only item, the page falls back to the uncollected detail body, where Price overview remains visible.

## Testing Strategy

Use TDD in two layers:

1. Controller tests cover add, edit, raw-to-graded switching, validation failures, cancel, and delete behavior.
2. Widget tests cover the inline form, grader/condition/grade switching, saved rows, and remove confirmation.

Focused verification for implementation:

- `flutter test test/card_detail_controller_test.dart`
- `flutter test test/widget/card_detail_page_test.dart`
- `flutter test test/widget/search_page_test.dart`

Final verification for the milestone:

- `flutter pub get`
- `dart run melos run test`
- `flutter analyze`
- `dart format --set-exit-if-changed lib test`

## Out Of Scope

- Real API calls for Collection Item CRUD.
- Home, Collection, Search global data reload after save/delete.
- New routing for a dedicated edit page.
- M5-5 price-data empty/degraded states.
- Admin/M7 code.
