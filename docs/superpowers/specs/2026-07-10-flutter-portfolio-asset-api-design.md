# Flutter Portfolio Asset API Design

## Background

Flutter Auth is already connected to the real `/auth/*` API. The next useful business milestone is to connect authenticated portfolio asset state to Flutter so Collection and Card Detail stop using isolated mock ownership data.

Assumptions:

- The existing Workers portfolio routes are the source of truth for folders, collection items, wishlist items, and quick collect.
- The current Flutter UI should remain structurally unchanged in this iteration.
- Search and Home stay out of scope except for any test updates required by provider defaults.
- Existing dirty backend and documentation changes are unrelated and must not be touched.

## Goal

Build one Flutter portfolio asset integration shared by Collection and Card Detail:

- Collection loads real folders, portfolio items, and wishlist items.
- Card Detail quick collect, manual item add/edit/delete, and wishlist toggle write to the real API.
- Both surfaces use the current authenticated session token.

## Scope

In scope:

- Add an HTTP implementation for the existing Collection repository boundary.
- Extend the Card Detail repository boundary with asset mutations.
- Reuse existing Card Detail local card presentation data while overlaying real owner asset state.
- Map backend portfolio and wishlist responses into existing Flutter view models.
- Add focused repository/controller tests for API mapping and mutation intent.

Out of scope:

- Search API integration.
- Home aggregation changes.
- Folder create, rename, reorder, delete UI.
- Backend route changes unless implementation proves an existing route is unusable.
- Offline cache or optimistic retry infrastructure.

## Architecture

Create a small shared Portfolio API client inside the Flutter app. It owns:

- Base URL from `KANDO_API_BASE_URL`, matching Auth.
- `Authorization: Bearer <access_token>` from the current Auth session.
- Envelope parsing for `{ success, data }` API responses.
- Minimal typed methods for folders, portfolio items, wishlist items, and quick collect.

`CollectionRepository` should default to an HTTP repository and keep `MockCollectionRepository` for tests and explicit overrides.

`CardDetailRepository` should keep loading card display data from the existing mock detail source for now, then merge real asset state from Portfolio API by `cardId`/`card_ref`. Mutations return the saved backend item or updated asset state so the existing controller can update its state without inventing local IDs.

## Data Flow

Collection load:

1. Read current Auth session.
2. Fetch `/portfolio/folders`, `/portfolio/items?page_size=100`, and `/wishlist?page_size=100`.
3. Convert folders to `CollectionFolder`.
4. Convert collection items and wishlist items to `CollectionItem`.
5. Preserve existing filtering, sorting, totals, and empty states.

Card Detail load:

1. Load existing card detail presentation data.
2. Fetch portfolio items and wishlist items.
3. Keep only rows matching the current `cardId`.
4. Replace `quantity`, `collectionItems`, and `isWishlisted` with backend state.

Card Detail mutations:

- Quick collect calls `POST /cards/:card_ref/collect`.
- Add item calls `POST /portfolio/items`.
- Edit item calls `PATCH /portfolio/items/:item_id`.
- Delete item calls `DELETE /portfolio/items/:item_id`.
- Add wishlist calls `POST /wishlist`.
- Remove wishlist calls `DELETE /wishlist/:item_id`.

## Error Handling

- If initial Collection loading fails, keep the existing unavailable state.
- If Card Detail presentation data fails, keep the existing unavailable state.
- If asset overlay fails but presentation data loads, show the detail without asset rows and keep actions available only when a session exists.
- Mutation failures should not fabricate local success. The controller keeps the previous state and exposes the existing form error path where applicable.

## Testing

Repository tests:

- Auth token is attached to portfolio requests.
- Collection dashboard maps folders, collection items, and wishlist items.
- Quick collect sends the expected payload and removes wishlist state by using the backend response.
- Wishlist add/remove calls the expected endpoints.

Controller tests:

- Quick collect updates Card Detail from the repository result, not a local generated ID.
- Manual add/edit/delete collection item uses repository mutations and preserves validation errors.
- Wishlist toggle persists through repository calls.

Regression checks:

- `flutter test apps/flutter-app/test`
- `flutter analyze apps/flutter-app`

## Acceptance Criteria

- After login, Collection shows real folders, portfolio items, and wishlist items.
- Quick collect on Card Detail creates a backend collection item and clears wishlist intent.
- Manual Card Detail item add/edit/delete persists to backend.
- Wishlist toggle persists to backend and refreshes Card Detail state.
- Existing Flutter tests pass, with new tests covering the integration boundary.
