import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import sitemapLastmod from '../content/sitemap-lastmod.mjs';
import { sitemapEntries } from '../scripts/sitemap.mjs';

const publicUrl = new URL('../public/', import.meta.url);
const landingContentUrl = new URL('../content/landing/', import.meta.url);
const indexPath = fileURLToPath(new URL('index.html', publicUrl));
const notFoundPath = fileURLToPath(new URL('404.html', publicUrl));
const llmsPath = fileURLToPath(new URL('llms.txt', publicUrl));
const sitemapPath = fileURLToPath(new URL('sitemap.xml', publicUrl));
const minimalSitemapPath = fileURLToPath(new URL('sitemap-minimal.xml', publicUrl));
const robotsPath = fileURLToPath(new URL('robots.txt', publicUrl));
const cssPath = fileURLToPath(new URL('site.css', publicUrl));
const nonLandingRootPages = new Set([
  '404.html',
  'google406556797e3e830d.html',
  'index.html',
  'privacy.html',
  'terms.html',
]);

function jsonLdObjects(html) {
  return [...html.matchAll(/<script type="application\/ld\+json">\s*([\s\S]*?)\s*<\/script>/g)].map(
    ([, json]) => JSON.parse(json),
  );
}

async function landingPageNames() {
  return (await readdir(publicUrl, { withFileTypes: true }))
    .filter(
      (entry) =>
        entry.isFile() &&
        entry.name.endsWith('.html') &&
        !nonLandingRootPages.has(entry.name),
    )
    .map((entry) => entry.name)
    .sort();
}

function normalizedWords(value) {
  return value
    .toLowerCase()
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

function occurrences(value, needle) {
  return value.split(needle).length - 1;
}

test('homepage describes the verified free install without unsupported sports claims', async () => {
  const html = await readFile(indexPath, 'utf8');
  const seoSurface = html.slice(0, html.indexOf('</main>') + '</main>'.length);
  const softwareApplication = jsonLdObjects(html).find(
    (value) => value['@type'] === 'SoftwareApplication',
  );

  assert.deepEqual(softwareApplication?.offers, {
    '@type': 'Offer',
    price: 0,
  });
  assert.doesNotMatch(seoSurface, /\b(?:baseball|hockey)\b/i);
  assert.match(
    seoSurface,
    /<span class="store-badge store-badge-disabled" aria-disabled="true">[\s\S]*?<small>Store Link Pending<\/small>[\s\S]*?<strong>Google Play<\/strong>/,
  );
  assert.doesNotMatch(seoSurface, /<small>Get Started<\/small><strong>Google Play<\/strong>/);
});

test('custom 404 page cannot advertise itself as a canonical indexable page', async () => {
  const html = await readFile(notFoundPath, 'utf8');

  assert.match(html, /<meta name="robots" content="noindex,follow">/);
  assert.doesNotMatch(html, /<link rel="canonical"/);
  assert.doesNotMatch(html, /<meta property="og:url"/);
});

test('rendered SEO pages keep scan recognition and notification claims within product capability', async () => {
  const rootPages = (await readdir(publicUrl, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith('.html'))
    .map((entry) => entry.name);
  const blogUrl = new URL('blog/', publicUrl);
  const blogPages = (await readdir(blogUrl, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith('.html'))
    .map((entry) => `blog/${entry.name}`);
  const pages = await Promise.all(
    [...rootPages, ...blogPages].map(async (path) =>
      readFile(fileURLToPath(new URL(path, publicUrl)), 'utf8'),
    ),
  );
  const html = pages.join('\n');

  assert.doesNotMatch(
    html,
    /\b(?:finish|variant|edition) (?:is|are) part of (?:what )?the scan result\b/i,
  );
  assert.doesNotMatch(
    html,
    /\bCard AI (?:returns?|reads?|identifies) (?:the )?(?:finish|variant|edition|treatment|exact printing)\b/i,
  );
  assert.doesNotMatch(html, /set up push alerts/i);
  assert.doesNotMatch(html, /track set completion|checklist here is generated/i);
  assert.doesNotMatch(
    html,
    /Automatic Edition Recognition|Recognition History|Multi-Angle Recognition with High Accuracy|Popularity & Liquidity Analysis|Trusted by Collectors Worldwide|Real-Time Valuation Updates/i,
  );
  assert.match(html, /confirm (?:the )?(?:matching card|printing|finish|language)/i);
});

test('GEO summary keeps recognition and pricing claims within verified capability', async () => {
  const llms = await readFile(llmsPath, 'utf8');
  const pricePage = await readFile(
    fileURLToPath(new URL('card-price-checker.html', publicUrl)),
    'utf8',
  );

  assert.doesNotMatch(llms, /identify any card from a photo/i);
  assert.doesNotMatch(llms, /including set, card number, edition, variant, and finish/i);
  assert.match(llms, /suggests likely catalog matches/i);
  assert.doesNotMatch(pricePage, /Card AI works from the second and third/i);
  assert.match(pricePage, /does not import eBay sold transactions or calculate the published market price from that search/i);
});

test('comparison pages cite product sources and avoid placeholder or untested winner claims', async () => {
  const pages = await Promise.all(
    ['card-scanner-comparison-2026', 'card-ai-vs-ludex', 'card-ai-vs-collx'].map((slug) =>
      readFile(fileURLToPath(new URL(`${slug}.html`, publicUrl)), 'utf8'),
    ),
  );

  for (const html of pages) {
    assert.doesNotMatch(html, /Check the current (?:plan|catalog|app|scanner|category|grade|condition|price|portfolio)/i);
    assert.doesNotMatch(html, /Card AI (?:is|was) (?:the )?(?:best|fastest|most accurate)/i);
    assert.doesNotMatch(html, /Card AI (?:imports|syncs|shows) eBay sold transactions/i);
    assert.match(html, /reviewed October 19(?:-20)?, 2026/i);
  }

  assert.match(pages[0], /href="https:\/\/www\.ludex\.com\/scan-and-price\/"/);
  assert.match(pages[0], /href="https:\/\/www\.collx\.app\/faq"/);
  assert.match(pages[0], /not a hands-on accuracy or speed test/i);
  assert.match(pages[1], /does not claim a winner for recognition speed or accuracy/i);
  assert.match(pages[2], /not a synced feed of sold transactions/i);
});

test('approved keyword clusters stay with one truthful owner', async () => {
  const pages = Object.fromEntries(
    await Promise.all(
      [
        'card-identifier.html',
        'card-price-checker.html',
        'pokemon-card-scanner.html',
        'card-collection-tracker.html',
        'bulk-card-scanner.html',
        'graded-card-tracker.html',
        'card-scanner-comparison-2026.html',
        'card-ai-vs-ludex.html',
        'card-ai-vs-collx.html',
      ].map(async (name) => [name, await readFile(fileURLToPath(new URL(name, publicUrl)), 'utf8')]),
    ),
  );

  assert.match(pages['card-identifier.html'], /trading card scanner app/i);
  assert.match(pages['card-identifier.html'], /identify a trading card from a photo/i);
  assert.match(pages['card-identifier.html'], /TCG card scanner/i);
  assert.match(pages['card-identifier.html'], /does not guarantee an exact printing/i);

  assert.match(pages['card-price-checker.html'], /card price scanner app/i);
  assert.match(pages['card-price-checker.html'], /trading card value app/i);
  assert.match(pages['card-price-checker.html'], /same confirmed card record/i);
  assert.match(pages['card-price-checker.html'], /Pokemon card price checker and a Pokemon card value checker answer the same question/i);
  assert.match(pages['card-price-checker.html'], /keep a missing price as missing/i);

  assert.match(pages['pokemon-card-scanner.html'], /Pokemon card value scanner/i);
  assert.match(pages['pokemon-card-scanner.html'], /best Pokemon card scanner app/i);
  assert.match(pages['pokemon-card-scanner.html'], /free to install/i);
  assert.match(pages['pokemon-card-scanner.html'], /does not authenticate cards or predict grades/i);
  assert.match(pages['pokemon-card-scanner.html'], /server-managed limit of 10 successful scans/i);
  assert.match(pages['pokemon-card-scanner.html'], /10-image queue is a separate batch limit/i);

  assert.match(pages['card-collection-tracker.html'], /TCG collection tracker/i);
  assert.match(pages['card-collection-tracker.html'], /trading card portfolio tracker/i);
  assert.match(pages['card-collection-tracker.html'], /raw conditions and existing slab grades as distinct holdings/i);

  assert.match(pages['bulk-card-scanner.html'], /bulk card scanner app/i);
  assert.match(pages['bulk-card-scanner.html'], /up to 10 camera captures or gallery selections/i);
  assert.match(pages['bulk-card-scanner.html'], /does not continuously auto-capture cards or read an entire binder page/i);

  assert.match(pages['graded-card-tracker.html'], /graded card value tracker/i);
  assert.match(pages['graded-card-tracker.html'], /PSA card value tracker/i);
  assert.match(pages['graded-card-tracker.html'], /does not connect to PSA or predict the grade/i);

  assert.match(pages['card-scanner-comparison-2026.html'], /Trading Card Scanner Apps Compared in 2026/i);
  assert.match(pages['card-scanner-comparison-2026.html'], /eBay search link/i);
  assert.match(pages['card-scanner-comparison-2026.html'], /<table>/i);
  assert.match(pages['card-scanner-comparison-2026.html'], /href="https:\/\/www\.pricecharting\.com\/page\/collection-tracker"/);
  assert.match(pages['card-scanner-comparison-2026.html'], /href="https:\/\/www\.cardladder\.com\/pricing"/);
  assert.match(pages['card-scanner-comparison-2026.html'], /free access currently allows 10 successful scans per account/i);
  assert.match(pages['card-scanner-comparison-2026.html'], /Google Play store link on this website is still pending/i);
  assert.match(pages['card-scanner-comparison-2026.html'], /Try the card scanner in Card AI/);
  assert.match(pages['card-ai-vs-ludex.html'], /Card AI vs Ludex/i);
  assert.match(pages['card-ai-vs-ludex.html'], /Ludex scan and price guide/i);
  assert.match(pages['card-ai-vs-ludex.html'], /does not create an eBay listing/i);
  assert.match(pages['card-ai-vs-ludex.html'], /Try the card scanner in Card AI/);
  assert.match(pages['card-ai-vs-collx.html'], /Card AI vs CollX/i);
  assert.match(pages['card-ai-vs-collx.html'], /pricing FAQ/i);
  assert.match(pages['card-ai-vs-collx.html'], /not a synced feed of sold transactions/i);
  assert.match(pages['card-ai-vs-collx.html'], /Try the collection tracker in Card AI/);
});

test('homepage scanner-app guidance is visible and matches FAQ schema', async () => {
  const html = await readFile(indexPath, 'utf8');
  const faq = jsonLdObjects(html).find((value) => value['@type'] === 'FAQPage');
  const question = faq?.mainEntity?.find(
    (entry) => entry.name === 'What should I look for in a trading card scanner app?',
  );
  const expectedAnswer =
    'A useful trading card scanner app should show likely catalog matches for review, keep the set and card number visible, separate raw condition from existing slab grades, and connect confirmed cards to price history and a collection tracker. Card AI does not authenticate cards or predict grades from a photo.';

  assert.equal(question?.acceptedAnswer?.text, expectedAnswer);
  assert.match(
    html,
    /<summary>What should I look for in a trading card scanner app\?<\/summary>\s*<p>A useful trading card scanner app should show likely catalog matches for review,[\s\S]*?does not authenticate cards or predict grades from a photo\.<\/p>/,
  );
});

test('30th Celebration guide keeps dated facts, article metadata, links, and discovery surfaces aligned', async () => {
  const slug = 'pokemon-tcg-30th-celebration-card-prices';
  const canonical = `https://tcgcard.fun/blog/${slug}`;
  const articlePath = fileURLToPath(new URL(`blog/${slug}.html`, publicUrl));
  const [articleHtml, pokemonHtml, homepageHtml, blogIndexHtml, llms, sitemap] =
    await Promise.all([
      readFile(articlePath, 'utf8'),
      readFile(fileURLToPath(new URL('pokemon-card-scanner.html', publicUrl)), 'utf8'),
      readFile(indexPath, 'utf8'),
      readFile(fileURLToPath(new URL('blog/index.html', publicUrl)), 'utf8'),
      readFile(llmsPath, 'utf8'),
      readFile(sitemapPath, 'utf8'),
    ]);
  const article = jsonLdObjects(articleHtml).find((value) => value['@type'] === 'Article');

  assert.match(articleHtml, /<h1>Pokemon TCG 30th Celebration card prices and set guide<\/h1>/);
  assert.match(articleHtml, /30C main set with 202 card records/i);
  assert.match(articleHtml, /30C-CC Classic Collection with 30 card records/i);
  assert.match(articleHtml, /Price snapshot observed October 10, 2026 \(USD\)/);
  assert.match(
    articleHtml,
    /Illustrative Card AI screen composite\. Values shown in the image are examples, not the dated 30th Celebration snapshot below\./,
  );
  assert.match(articleHtml, /Lugia 149\/147[^<]*\$192\.93/);
  assert.match(articleHtml, /Charizard 4\/102[^<]*\$142\.32/);
  assert.match(articleHtml, /Mew ex 158\/128[^<]*\$62\.33/);
  assert.match(articleHtml, /Gengar \(Prime\) 94\/102[^<]*\$54\.29/);
  assert.match(articleHtml, /Mewtwo ex 157\/128[^<]*\$45\.75/);
  assert.match(
    articleHtml,
    /dated market snapshots, not offers, appraisals, or guaranteed sale prices/i,
  );
  assert.match(articleHtml, /does not authenticate a card or guarantee the exact printing/i);
  assert.match(articleHtml, /Card AI does not predict a grade/i);
  assert.match(articleHtml, /official 30th Celebration gallery and its full card checklist/i);
  assert.match(articleHtml, /not a complete card list or a ranking of the most valuable cards/i);
  assert.match(articleHtml, /Updated 2026-10-20/);
  assert.match(articleHtml, /30th Celebration Ultra-Premium Collection/);
  assert.match(articleHtml, /29 30th Celebration booster packs and one Classic Collection booster pack/);
  assert.match(articleHtml, /not a Card AI price for a sealed box/);
  assert.match(articleHtml, /href="\/pokemon-card-scanner"/);
  assert.match(articleHtml, /href="\/card-price-checker"/);
  assert.match(pokemonHtml, new RegExp(`href="/blog/${slug}"`));

  assert.equal(article?.headline, 'Pokemon TCG 30th Celebration card prices and set guide');
  assert.equal(article?.datePublished, '2026-10-10');
  assert.equal(article?.dateModified, '2026-10-20');
  assert.equal(article?.mainEntityOfPage, canonical);
  assert.equal(article?.image, 'https://tcgcard.fun/assets/showcase-analysis.png');
  assert.match(articleHtml, new RegExp(`<link rel="canonical" href="${canonical}">`));
  assert.match(articleHtml, /<meta property="og:type" content="article">/);
  assert.match(
    articleHtml,
    /<meta property="og:image" content="https:\/\/tcgcard\.fun\/assets\/showcase-analysis\.png">/,
  );

  assert.equal(occurrences(sitemap, `<loc>${canonical}</loc>`), 1);
  assert.equal(occurrences(llms, `](${canonical})`), 1);
  assert.equal(occurrences(homepageHtml, `href="/blog/${slug}"`), 1);
  assert.equal(occurrences(blogIndexHtml, `href="/blog/${slug}"`), 1);
  assert.equal(occurrences(sitemap, '<url>'), 31);
});

test('Minior guide distinguishes Pokemon GO encounters from physical card printings', async () => {
  const slug = 'minior-pokemon-card-guide';
  const canonical = `https://tcgcard.fun/blog/${slug}`;
  const [article, pokemon, blogIndex, llms, sitemap] = await Promise.all([
    readFile(fileURLToPath(new URL(`blog/${slug}.html`, publicUrl)), 'utf8'),
    readFile(fileURLToPath(new URL('pokemon-card-scanner.html', publicUrl)), 'utf8'),
    readFile(fileURLToPath(new URL('blog/index.html', publicUrl)), 'utf8'),
    readFile(llmsPath, 'utf8'),
    readFile(sitemapPath, 'utf8'),
  ]);

  assert.match(article, /Searching for &quot;Minior Pokemon GO&quot; usually means the Pokemon GO encounter event/);
  assert.match(article, /Paradox Rift 099\/182/);
  assert.match(article, /Paradox Rift 201\/182/);
  assert.match(article, /Guardians Rising 77\/145/);
  assert.match(article, /does not quote a live price or guarantee a sale amount/);
  assert.match(article, /href="https:\/\/pokemongo\.com\/news\/minior-meteor-showers-2026"/);
  assert.match(pokemon, new RegExp(`href="/blog/${slug}"`));
  assert.match(blogIndex, new RegExp(`href="/blog/${slug}"`));
  assert.equal(occurrences(llms, `](${canonical})`), 1);
  assert.equal(occurrences(sitemap, `<loc>${canonical}</loc>`), 1);
});

test('grading guide describes existing slab tracking without offering grading services', async () => {
  const article = await readFile(
    fileURLToPath(new URL('blog/raw-vs-graded-card-values.html', publicUrl)),
    'utf8',
  );
  const metadata = jsonLdObjects(article).find((value) => value['@type'] === 'Article');

  assert.match(article, /Which card grading companies can Card AI record/);
  assert.match(article, /record PSA, BGS, CGC or SGC and the grade shown on its slab/);
  assert.match(article, /does not submit cards to a grading company, authenticate a slab, or estimate what grade a raw card would receive/);
  assert.equal(metadata?.dateModified, '2026-10-20');
});

test('new collector guides keep card releases and retailer names distinct', async () => {
  const slugs = ['dungeon-crawler-carl-trading-cards', 'scanning-cards-from-watsontcg'];
  const [dungeon, watson, blogIndex, llms, sitemap] = await Promise.all([
    readFile(fileURLToPath(new URL(`blog/${slugs[0]}.html`, publicUrl)), 'utf8'),
    readFile(fileURLToPath(new URL(`blog/${slugs[1]}.html`, publicUrl)), 'utf8'),
    readFile(fileURLToPath(new URL('blog/index.html', publicUrl)), 'utf8'),
    readFile(llmsPath, 'utf8'),
    readFile(sitemapPath, 'utf8'),
  ]);

  assert.match(dungeon, /World Earth trading cards/);
  assert.match(dungeon, /Character collector cards/);
  assert.match(dungeon, /Unstoppable game cards/);
  assert.match(dungeon, /supports scanning cataloged Dungeon Crawler Carl collectible cards/);
  assert.match(dungeon, /Availability of a matching record, image and market price depends on the specific card/);
  assert.match(watson, /WatsonTCG.*store, not a separate TCG/s);
  assert.match(watson, /does not claim Card AI can identify every game, sealed product or item/);
  assert.match(watson, /does not imply a partnership with WatsonTCG/);

  for (const slug of slugs) {
    const canonical = `https://tcgcard.fun/blog/${slug}`;
    assert.match(blogIndex, new RegExp(`href="/blog/${slug}"`));
    assert.equal(occurrences(llms, `](${canonical})`), 1);
    assert.equal(occurrences(sitemap, `<loc>${canonical}</loc>`), 1);
  }
});

test('llms inventory includes every generated blog article exactly once', async () => {
  const blogUrl = new URL('blog/', publicUrl);
  const llms = await readFile(llmsPath, 'utf8');
  const articleNames = (await readdir(blogUrl, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith('.html') && entry.name !== 'index.html')
    .map((entry) => entry.name.replace(/\.html$/, ''));

  for (const slug of articleNames) {
    assert.equal(occurrences(llms, `](https://tcgcard.fun/blog/${slug})`), 1, slug);
  }
});

test('marketing composites are disclosed as illustrative examples', async () => {
  for (const name of await landingPageNames()) {
    const html = await readFile(fileURLToPath(new URL(name, publicUrl)), 'utf8');

    assert.match(html, /Illustrative Card AI screen composite/);
    assert.match(html, /Values shown are examples/);
    assert.doesNotMatch(html, /Actual Card AI product view/);
  }
});

test('sitemap matches the production XML structure and uses explicit lastmod values', async () => {
  const sitemap = await readFile(sitemapPath, 'utf8');
  const lines = sitemap.trimEnd().split('\n');
  const entryLines = lines.slice(2, -1);
  const entries = entryLines.map((line) => {
    const match = line.match(/^<url><loc>(https:\/\/tcgcard\.fun(?:\/[^<]*)?)<\/loc><lastmod>(\d{4}-\d{2}-\d{2})<\/lastmod><\/url>$/);
    assert.ok(match, line);
    return { canonical: match[1], lastmod: match[2] };
  });

  assert.deepEqual(
    lines.slice(0, 2),
    [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">',
    ],
  );
  assert.equal(lines.at(-1), '</urlset>');
  assert.doesNotMatch(sitemap, /Generated by|<priority>/);
  assert.equal(entries.length, 31);
  assert.equal(Object.keys(sitemapLastmod).length, entries.length);
  assert.deepEqual(
    [...new Set(entries.map(({ canonical }) => new URL(canonical).pathname))].sort(),
    Object.keys(sitemapLastmod).sort(),
  );

  for (const { canonical, lastmod } of entries) {
    const path = new URL(canonical).pathname;
    assert.equal(lastmod, sitemapLastmod[path], canonical);
    assert.equal(new Date(`${lastmod}T00:00:00Z`).toISOString().slice(0, 10), lastmod, canonical);
  }
});

test('sitemap inventory rejects incomplete, stale, duplicate, and invalid dates', () => {
  assert.throws(() => sitemapEntries(['/'], {}), /missing=\//);
  assert.throws(() => sitemapEntries(['/'], { '/': '2026-10-20', '/stale': '2026-10-20' }), /stale=\/stale/);
  assert.throws(() => sitemapEntries(['/', '/'], { '/': '2026-10-20' }), /duplicate=\//);
  assert.throws(() => sitemapEntries(['/'], { '/': '2026-13-40' }), /invalid=\//);
  assert.throws(() => sitemapEntries(['/'], { '/': '2026-02-31' }), /invalid=\//);
});

test('minimal diagnostic sitemap isolates Google processing without changing discovery signals', async () => {
  const [minimalSitemap, sitemap, robots] = await Promise.all([
    readFile(minimalSitemapPath, 'utf8'),
    readFile(sitemapPath, 'utf8'),
    readFile(robotsPath, 'utf8'),
  ]);
  const expected = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://tcgcard.fun/</loc>
  </url>
  <url>
    <loc>https://tcgcard.fun/pokemon-card-scanner</loc>
  </url>
  <url>
    <loc>https://tcgcard.fun/card-price-checker</loc>
  </url>
</urlset>
`;

  assert.equal(minimalSitemap, expected);
  assert.equal(occurrences(minimalSitemap, '<url>'), 3);
  assert.doesNotMatch(minimalSitemap, /<!--|<priority>|<lastmod>|<changefreq>|xhtml:/);
  assert.doesNotMatch(sitemap, /sitemap-minimal\.xml/);
  assert.doesNotMatch(robots, /sitemap-minimal\.xml/);
  assert.match(robots, /Sitemap: https:\/\/tcgcard\.fun\/sitemap\.xml/);
});

test('FAQ switches to one column at tablet widths', async () => {
  const css = await readFile(cssPath, 'utf8');

  assert.match(
    css,
    /@media \(max-width: 960px\) \{[\s\S]*?\.faq-layout \{ grid-template-columns: 1fr;/,
  );
});

test('every landing page shows product proof, contextual links, and an honest store state', async () => {
  const names = await landingPageNames();
  assert.equal(names.length, 21);

  for (const name of names) {
    const html = await readFile(fileURLToPath(new URL(name, publicUrl)), 'utf8');
    const title = (html.match(/<title>([\s\S]*?)<\/title>/)?.[1] ?? '').replace(/&amp;/g, '&');
    const webPage = jsonLdObjects(html).find((value) => value['@type'] === 'WebPage');
    const proof = html.match(/<figure class="[^"]*\bproduct-proof\b[^"]*">([\s\S]*?)<\/figure>/)?.[1] ?? '';

    assert.ok(title.length <= 60, `${name}: title is ${title.length} characters`);
    assert.doesNotMatch(title, /\b(?:PSA|BGS|CGC|SGC)\b/);
    assert.match(proof, /<img[^>]+src="\/assets\/(?:showcase|feature)-[^"]+"[^>]+alt="[^"]+"/);
    assert.match(proof, /<figcaption>/);
    assert.match(proof, /<div class="product-proof-copy">[\s\S]*?<a href="\/[^"]+">/);
    assert.match(webPage?.image ?? '', /^https:\/\/tcgcard\.fun\/assets\//);
    assert.match(html, /<h2>Try [^<]+ in Card AI\.<\/h2>/);
    assert.doesNotMatch(html, /<h2>Start tracking your collection\.<\/h2>/);
    assert.match(
      html,
      /<span class="store-badge store-badge-disabled" aria-disabled="true">[\s\S]*?<small>Store Link Pending<\/small>[\s\S]*?<strong>Google Play<\/strong>/,
    );
    assert.doesNotMatch(
      html,
      /<h2>(?:Prices|Organise|Basketball cards|Soccer cards|Graded cards) questions\.<\/h2>/i,
    );
  }
});

test('landing pages do not reuse long exact content blocks', async () => {
  const files = (await readdir(landingContentUrl, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith('.mjs'))
    .map((entry) => entry.name)
    .sort();
  const ownersByBlock = new Map();

  for (const file of files) {
    const page = (await import(new URL(file, landingContentUrl))).default;
    const blocks = [
      page.description,
      page.lede,
      page.proof.title,
      page.proof.body,
      ...page.sections.flatMap((section) => [section.h2, section.body]),
      ...page.faq.flatMap((item) => [item.q, item.a]),
      page.cta,
    ];
    for (const block of blocks) {
      const words = normalizedWords(block);
      if (words.length < 20) continue;
      const normalized = words.join(' ');
      const owners = ownersByBlock.get(normalized) ?? [];
      owners.push(page.slug);
      ownersByBlock.set(normalized, owners);
    }
  }

  const duplicates = [...ownersByBlock.entries()]
    .filter(([, owners]) => new Set(owners).size > 1)
    .map(([block, owners]) => ({ block, owners: [...new Set(owners)] }));
  assert.deepEqual(duplicates, []);
});

test('blog pages provide article images and use consistent US English', async () => {
  const blogUrl = new URL('blog/', publicUrl);
  const index = await readFile(fileURLToPath(new URL('index.html', blogUrl)), 'utf8');
  const articleNames = (await readdir(blogUrl, { withFileTypes: true }))
    .filter((entry) => entry.isFile() && entry.name.endsWith('.html') && entry.name !== 'index.html')
    .map((entry) => entry.name);

  assert.match(index, /class="blog-card-image"/);
  for (const name of articleNames) {
    const html = await readFile(fileURLToPath(new URL(name, blogUrl)), 'utf8');
    const article = jsonLdObjects(html).find((value) => value['@type'] === 'Article');
    const title = (html.match(/<title>([\s\S]*?)<\/title>/)?.[1] ?? '').replace(/&amp;/g, '&');

    assert.ok(title.length <= 60, `${name}: title is ${title.length} characters`);
    assert.match(article?.image ?? '', /^https:\/\/tcgcard\.fun\/assets\//);
    assert.match(html, /<figure class="content-figure">[\s\S]*?<img[^>]+alt="[^"]+"/);
  }

  const allSeoCopy = `${index}\n${await Promise.all(
    articleNames.map((name) => readFile(fileURLToPath(new URL(name, blogUrl)), 'utf8')),
  )}`;
  assert.doesNotMatch(
    allSeoCopy,
    /\b(?:organise|organised|organising|catalogue|cataloguing|coloured|centring|sceptical)\b/i,
  );
});
