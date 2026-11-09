import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { renderCardList } from '../scripts/card-lists.mjs';

const read = (path) => readFile(new URL(path, import.meta.url), 'utf8');

test('English checklists retain every issuer number and separate printing prices', async () => {
  for (const [key, count, denominator] of [
    ['chaos-rising', 122, '086'],
    ['ascended-heroes', 295, '217'],
    ['phantasmal-flames', 130, '094'],
  ]) {
    const snapshot = JSON.parse(await read(`../content/card-lists/${key}.json`));
    const html = await read(`../public/blog/${key}-card-list.html`);
    assert.equal(snapshot.cards.length, count);
    assert.deepEqual(snapshot.cards.map((card) => card.number),
      Array.from({ length: count }, (_, i) => `${String(i + 1).padStart(3, '0')}/${denominator}`));
    assert.equal((html.match(/data-card-row /g) ?? []).length, count);
    assert.match(html, /These samples do not specify a raw condition or slab grade/);
    assert.match(html, /<form class="card-list-controls" role="search" hidden>/);
    assert.match(html, /<script src="\/card-list.js" defer><\/script>/);
    assert.match(html, /href="#card-list">Browse the card list and price samples/);
    assert.match(html, /official English checklist/);
    assert.doesNotMatch(html, /<td>Code Card|<td>Booster Box/);
    for (const card of snapshot.cards) {
      for (const record of card.records) {
        assert.ok(record.priceUsd === null || (Number.isFinite(record.priceUsd) && record.priceUsd >= 0));
        assert.ok(record.priceAsOf === null || record.priceAsOf <= snapshot.observedAt);
        assert.ok(record.printing);
      }
    }
  }

  const asc = JSON.parse(await read('../content/card-lists/ascended-heroes.json'));
  assert.deepEqual(asc.cards.find((card) => card.number === '217/217').records, []);
  assert.ok(asc.cards.find((card) => card.number === '178/217').records.length > 1);
  const html = await read('../public/blog/ascended-heroes-card-list.html');
  assert.match(html, /id="card-217"[^>]*data-priced="false"/);
  assert.match(html, /Energy Symbol Pattern/);
});

test('reference rendering preserves zero, exposes missing prices and escapes card data', () => {
  const html = renderCardList({
    setName: 'Example', setCode: 'EX', observedAt: '2026-11-05',
    checklistUrl: 'https://example.com/checklist.pdf', galleryUrl: 'https://example.com/gallery',
    cards: [
      { number: '001/002', name: '<img src=x onerror=alert(1)>', records: [
        { printing: 'Normal', priceUsd: 0, priceAsOf: '2026-11-04' },
        { printing: 'Foil', priceUsd: null, priceAsOf: null },
      ] },
      { number: '002/002', name: 'Missing record', records: [] },
    ],
  });
  assert.match(html, /&lt;img src=x onerror=alert\(1\)&gt;/);
  assert.doesNotMatch(html, /<img src=x/);
  assert.match(html, /Normal<\/span> · <strong>\$0\.00<\/strong>/);
  assert.match(html, /Foil<\/span> · <strong>Price unavailable<\/strong>/);
  assert.match(html, /No matching catalog record in this snapshot/);
  assert.match(html, /id="card-002"[^>]*data-priced="false"/);
});

test('new reference guides are discoverable and preserve product scope', async () => {
  const [home, index, sitemap, llms, price, pokemon, football, basketball] = await Promise.all([
    '../public/index.html', '../public/blog/index.html', '../public/sitemap.xml', '../public/llms.txt',
    '../public/card-price-checker.html', '../public/pokemon-card-scanner.html',
    '../public/football-card-scanner.html', '../public/basketball-card-scanner.html',
  ].map(read));
  for (const slug of ['chaos-rising-card-list', 'ascended-heroes-card-list', 'phantasmal-flames-card-list',
    'moonbreon-card-value', 'charizard-151-card-value', 'mega-charizard-x-ex-card-value', 'pikachu-card-values']) {
    const html = await read(`../public/blog/${slug}.html`);
    const canonical = `https://tcgcard.fun/blog/${slug}`;
    assert.match(home, new RegExp(`href="/blog/${slug}"`));
    assert.match(index, new RegExp(`href="/blog/${slug}"`));
    assert.ok(sitemap.includes(`<loc>${canonical}</loc>`));
    assert.ok(llms.includes(`](${canonical})`));
    assert.ok(html.includes(`<link rel="canonical" href="${canonical}">`));
    assert.match(html, /"@type": "Article"/);
    assert.doesNotMatch(html, /"@type": "Product"|"aggregateRating"/);
  }
  assert.match(price, /href="\/blog\/moonbreon-card-value"/);
  assert.match(pokemon, /href="\/blog\/chaos-rising-card-list"/);
  assert.match(football, /Complete 2025 Phoenix Football coverage has not been confirmed/);
  assert.match(basketball, /does not promise a complete 2025-26 Bowman catalog/);
});
