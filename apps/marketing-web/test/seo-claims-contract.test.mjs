import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const publicUrl = new URL('../public/', import.meta.url);
const landingContentUrl = new URL('../content/landing/', import.meta.url);
const indexPath = fileURLToPath(new URL('index.html', publicUrl));
const notFoundPath = fileURLToPath(new URL('404.html', publicUrl));
const llmsPath = fileURLToPath(new URL('llms.txt', publicUrl));
const sitemapPath = fileURLToPath(new URL('sitemap.xml', publicUrl));
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
  assert.match(pricePage, /does not calculate its market price from visible sold-listing comps/i);
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

  assert.match(pages['pokemon-card-scanner.html'], /Pokemon card value scanner/i);
  assert.match(pages['pokemon-card-scanner.html'], /best Pokemon card scanner app/i);
  assert.match(pages['pokemon-card-scanner.html'], /free to install/i);
  assert.match(pages['pokemon-card-scanner.html'], /does not authenticate cards or predict grades/i);

  assert.match(pages['card-collection-tracker.html'], /TCG collection tracker/i);
  assert.match(pages['card-collection-tracker.html'], /trading card portfolio tracker/i);
  assert.match(pages['card-collection-tracker.html'], /raw conditions and existing slab grades as distinct holdings/i);

  assert.match(pages['bulk-card-scanner.html'], /bulk card scanner app/i);
  assert.match(pages['bulk-card-scanner.html'], /up to 10 camera captures or gallery selections/i);
  assert.match(pages['bulk-card-scanner.html'], /does not continuously auto-capture cards or read an entire binder page/i);

  assert.match(pages['graded-card-tracker.html'], /graded card value tracker/i);
  assert.match(pages['graded-card-tracker.html'], /PSA card value tracker/i);
  assert.match(pages['graded-card-tracker.html'], /does not connect to PSA or predict the grade/i);
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
  assert.match(articleHtml, /href="\/pokemon-card-scanner"/);
  assert.match(articleHtml, /href="\/card-price-checker"/);
  assert.match(pokemonHtml, new RegExp(`href="/blog/${slug}"`));

  assert.equal(article?.headline, 'Pokemon TCG 30th Celebration card prices and set guide');
  assert.equal(article?.datePublished, '2026-10-10');
  assert.equal(article?.dateModified, '2026-10-10');
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
  assert.equal(occurrences(sitemap, '<url>'), 25);
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

test('sitemap avoids synthetic build-date lastmod values', async () => {
  const sitemap = await readFile(sitemapPath, 'utf8');

  assert.doesNotMatch(sitemap, /<lastmod>/);
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
  assert.equal(names.length, 18);

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
