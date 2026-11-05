# Public checklist snapshots

These JSON files are source content for the three English checklist pages. Generation is local and deterministic; it does not query production services. The browser filters the rendered table locally and does not send searches to an API.

Each file records the official gallery and checklist URLs, set code/ID, catalog query, and snapshot retrieval date. `cards` retains every numbered English entry from the issuer's checklist. `records` holds separately matched Card AI catalog printings, finishes, available USD prices and each price's actual observation date. An absent record uses an empty array; an absent price uses `null`. Never replace either with another printing's value.

To refresh a snapshot:

1. Re-read the linked issuer checklist. Confirm names, all printed numbers and the English set identity. Expected numbered entries for the currently checked PDFs are CRI 122, ASC 295 and PFL 130.
2. Fetch all pages of the recorded public `catalogSource` query. Its `total` is the current page length, not a whole-catalog count. Continue until the page has fewer than 100 records. Fail on HTTP, API, JSON or pagination errors; retain the previous snapshot on failure.
3. Match the exact set, English language, full printed collector number and card name. Record name variants such as patterns or trainer labels explicitly. Exclude code cards, sealed products and unnumbered extras. Check ambiguous names manually before assigning a price.
4. Preserve missing official numbers and separate finishes. Change `observedAt` to the retrieval date while retaining each source `priceAsOf`. The current sample does not specify condition or grade, so public copy must not label its amounts as Near Mint or PSA prices.
5. Generate content, run the affected marketing checks and exercise search, missing-price filtering and reset in the browser. Update page dates only for actual content changes.

The initial 2026-11-05 snapshots contain 122 CRI records, 549 ASC records and 130 PFL records matched to official numbered entries. ASC 217/217 remains without a catalog record. PFL's two code cards and an unnumbered Charcadet promo are excluded. These counts are snapshot coverage, not claims of complete variant or price coverage.
