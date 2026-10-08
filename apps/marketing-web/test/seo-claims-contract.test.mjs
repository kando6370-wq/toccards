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
