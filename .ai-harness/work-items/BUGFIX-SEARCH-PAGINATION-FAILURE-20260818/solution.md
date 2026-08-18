# Search pagination failure fix

## Root cause

`SearchController.loadNextCardPage()` catches a page request failure and only
clears `isLoadingMoreCards`. The requested page is not advanced, but no state
distinguishes the failed append from an idle list, so `SearchPage` cannot show
the failure or provide an explicit retry.

## Design

- Add a `hasCardPageFailure` flag to `SearchState` for append failures only.
- Keep the existing catalog, page number, search query, game and asset state
  unchanged when an append request fails.
- Stop scroll-triggered automatic loading while the flag is set.
- Add `retryNextCardPage()` to clear the flag and request the same next page.
- Reuse the existing Set Detail bottom refresh icon pattern in Search.
- Clear the flag after a successful page request or a new first-page search.

## Verification

- Controller test: page 2 fails once, page 1 content and pagination cursor are
  retained, and explicit retry requests page 2 again before appending it.
- Widget test: retained cards stay visible, a local retry control appears, and
  tapping it appends the page and removes the failure control.
- Run focused Flutter tests, Flutter analysis, formatting verification and
  `git diff --check`.

## Boundaries

This changes shared Flutter code and therefore applies equally to iOS and
Android. It does not change HTTP APIs, PostgreSQL schema or queries, remote
configuration, or any D1 path.
