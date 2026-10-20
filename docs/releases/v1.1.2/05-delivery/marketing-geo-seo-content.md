# Marketing GEO and SEO content

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

## Generation

Run `pnpm --filter @kando/marketing-web generate:content` after editing content sources. The generator writes public HTML, homepage discovery links, `llms.txt`, and `sitemap.xml`.

The formal sitemap follows the same namespace and `loc`/`lastmod` line shape as `meshcrate.vip`: the standard sitemap and Google image namespaces are declared, each URL is one line, and each record contains `loc` plus `lastmod` without `priority`. Card AI does not add `image:image` records until it has a page-specific image inventory. `apps/marketing-web/content/sitemap-lastmod.mjs` is the explicit date source. Update a route there only after a meaningful change to that public page. Before writing any generated file, the generator rejects missing, stale, duplicate, malformed, or impossible date entries instead of using the build date.
