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

## Product facts used

- Card AI supports basketball, football, and soccer card workflows.
- A scan can queue up to 10 camera or gallery items for review.
- Raw condition and existing PSA, BGS, CGC, and SGC grades remain separate records.
- Supported sports cards provide an eBay search link. The API does not import eBay sold transactions or use that link to calculate the published market price.
- Competitor claims are limited to linked first-party product pages reviewed on October 19, 2026. No controlled scan-speed or recognition-accuracy comparison was performed.
- The comparison pages must be refreshed when competitor features or plans change. A dated source review does not substitute for a hands-on comparison.
- `llms.txt` remains a public content inventory for other consumers. Google Search says it does not use this file for ranking, including its generative search features.

## Generation

Run `pnpm --filter @kando/marketing-web generate:content` after editing content sources. The generator writes public HTML, homepage discovery links, `llms.txt`, and `sitemap.xml`.
