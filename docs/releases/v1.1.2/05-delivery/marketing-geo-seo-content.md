# Marketing GEO and SEO content

Before choosing a keyword or writing a public capability claim, read [Card AI product positioning](../00-product/card-ai-product-positioning.md). Match the reader's task to the scan/search, collection, and market-data workflow. A marketplace can be a price source or an external research destination; its name does not by itself define a supported card category or a live sold-price feed.

## Scope

The marketing site assigns a primary page to each approved intent cluster. The generated pages are sourced from `apps/marketing-web/content/landing/` and included in the generated homepage links, `llms.txt`, and sitemap.

## Page owners

| Intent | Owner |
| --- | --- |
| Best trading card scanner apps in 2026 | `/card-scanner-comparison-2026` |
| Card AI vs Ludex | `/card-ai-vs-ludex` |
| Card AI vs CollX | `/card-ai-vs-collx` |
| Raw versus graded pricing guide | `/blog/raw-vs-graded-card-values` |
| Graded holdings product workflow | `/graded-card-tracker` |
| Card price and separate eBay search | `/card-price-checker` |
| Minior physical card printings | `/blog/minior-pokemon-card-guide` |
| Dungeon Crawler Carl collectible-card releases | `/blog/dungeon-crawler-carl-trading-cards` |
| Scanning supported singles bought at WatsonTCG | `/blog/scanning-cards-from-watsontcg` |
| Pokemon card price/value checker | `/card-price-checker` for valuation; `/pokemon-card-scanner` for the camera app workflow |
| Free sports card scanner app | `/card-scanner-comparison-2026` for free quota and workflow limits |
| Card Ladder feature comparison | `/card-scanner-comparison-2026`, based on its dated official pricing page |
| Existing grading companies | `/blog/raw-vs-graded-card-values` for already graded cards |
| 30th Celebration Ultra-Premium Collection | `/blog/pokemon-tcg-30th-celebration-card-prices` for official contents and single-card identification |

## Product facts used

- Card AI supports basketball, football, and soccer card workflows.
- A scan can queue up to 10 camera or gallery items for review.
- Raw condition and existing PSA, BGS, CGC, and SGC grades remain separate records.
- Supported sports cards provide an eBay search link. The API does not import eBay sold transactions or use that link to calculate the published market price.
- Competitor claims are limited to linked first-party product pages reviewed on October 19, 2026. No controlled scan-speed or recognition-accuracy comparison was performed.
- The comparison pages must be refreshed when competitor features or plans change. A dated source review does not substitute for a hands-on comparison.
- `llms.txt` remains a public content inventory for other consumers. Google Search says it does not use this file for ranking, including its generative search features.
- The Minior guide uses the `minior pokemon go` query only to clarify game encounters versus physical TCG cards. Its card facts link to official Pokemon TCG checklists; it does not publish live prices or game advice.
- The Dungeon Crawler Carl guide separates Playmates trading cards, ShelfCare collector cards and Renegade's Unstoppable game. The product owner confirms Card AI scan support for cataloged collector cards. Public `/games` and title search did not independently expose those records on October 20, 2026; page copy therefore does not promise coverage or prices for every release.
- WatsonTCG is a retailer. Its guide maps only supported singles to their actual games, excludes blanket coverage of Riftbound and sealed inventory, and states there is no partnership.
- October 20, 2026: approved existing owners now distinguish free install, the server's 10 successful free scans, and the separate 10-image queue. The Card Ladder row uses its official free/Pro feature table and dated price. The 30th Celebration guide uses Pokemon's official Day & Night product description without claiming sealed-product valuation.

## Generation

Run `pnpm --filter @kando/marketing-web generate:content` after editing content sources. The generator writes public HTML, homepage discovery links, `llms.txt`, and `sitemap.xml`.

The formal sitemap follows the same namespace and `loc`/`lastmod` line shape as `meshcrate.vip`: the standard sitemap and Google image namespaces are declared, each URL is one line, and each record contains `loc` plus `lastmod` without `priority`. Card AI does not add `image:image` records until it has a page-specific image inventory. `apps/marketing-web/content/sitemap-lastmod.mjs` is the explicit date source. Update a route there only after a meaningful change to that public page. Before writing any generated file, the generator rejects missing, stale, duplicate, malformed, or impossible date entries instead of using the build date.

## Homepage card preview

The scan showcase uses the existing sample card image for an interactive tilt and flip preview. Its reverse side is Card AI branding, not a representation of the physical card back. The preview uses no new image or 3D library. It remains visible without JavaScript; reduced-motion settings disable tilt and flip transitions. The hero screenshots and store links remain the primary first-screen content.
