import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {parse} from 'parse5';
import registry from '../content/articles.json' with {type: 'json'};
import articles from '@kando/website-content/articles' with {type: 'json'};
import {compileArticles} from '../scripts/compile-articles.mjs';
import {createRenderer, allStaticPaths} from '../src/render.mjs';
import {mayIndex, publicSitemap, publishHtml} from '../src/publication.mjs';

const origin = 'https://tcgcard.fun';
const mainPath = '/blog/delta-reign-pokemon';
const etbPath = '/blog/delta-reign-etb';
const renderer = createRenderer({liveSite: true});
const attr = (node, name) => node.attrs?.find(item => item.name === name)?.value;
const text = node => node.nodeName === '#text' ? node.value : (node.childNodes ?? []).map(text).join('');
const normalized = node => text(node).replace(/\s+/g, ' ').trim();
const nodes = (root, predicate) => {
  const found = [];
  const visit = node => {
    if (predicate(node)) found.push(node);
    for (const child of node.childNodes ?? []) visit(child);
  };
  visit(root);
  return found;
};
const matching = (root, tag, name, value) => nodes(root, node => node.tagName === tag && attr(node, name) === value);
const render = path => {
  const result = renderer.resolvePage(new URL(path, origin));
  assert.equal(result.status, 200, path);
  return {html: result.html, tree: parse(result.html)};
};
const articleBody = tree => {
  const bodies = nodes(tree, node => node.tagName === 'article' && (attr(node, 'class') ?? '').split(/\s+/).includes('file-article'));
  assert.equal(bodies.length, 1);
  return bodies[0];
};
const rows = table => nodes(table, node => node.tagName === 'tr')
  .map(row => row.childNodes.filter(node => node.tagName === 'td'))
  .filter(cells => cells.length);
const schemas = tree => matching(tree, 'script', 'type', 'application/ld+json').map(node => JSON.parse(text(node)));

test('Delta Reign directly supplies the 103 main and 38 secret numbered cards without counting price examples twice', () => {
  const {tree} = render(mainPath);
  const body = articleBody(tree);
  const checklists = nodes(body, node => node.tagName === 'table').filter(table => {
    const headers = nodes(table, node => node.tagName === 'th').map(normalized);
    return headers.length === 2 && headers[0] === 'Card number' && headers[1] === 'Card name';
  });
  assert.equal(checklists.length, 2);
  const main = rows(checklists[0]).map(cells => normalized(cells[0]));
  const secret = rows(checklists[1]).map(cells => normalized(cells[0]));
  assert.deepEqual(main, Array.from({length: 103}, (_, index) => String(index + 1).padStart(3, '0') + '/103'));
  assert.deepEqual(secret, Array.from({length: 38}, (_, index) => String(index + 104).padStart(3, '0') + '/103'));
  assert.equal(new Set([...main, ...secret]).size, 141);
  assert.match(normalized(body), /Checklist source:.*PokéCottage.*checked November 16, 2026/);
});

test('the eight card-price examples retain their printing, price type and observation date', () => {
  const {tree} = render(mainPath);
  const body = articleBody(tree);
  const prices = nodes(body, node => node.tagName === 'table').flatMap(rows).filter(cells =>
    cells.length === 5 && /^\d{3}\/103$/.test(normalized(cells[0])) && /^\$/.test(normalized(cells[2])));
  assert.equal(prices.length, 8);
  for (const cells of prices) {
    assert.equal(normalized(cells[3]), 'Ungraded reference');
    assert.equal(normalized(cells[4]), '2026-11-16');
  }
  const byNumber = new Map(prices.map(cells => [normalized(cells[0]), normalized(cells[2])]));
  assert.equal(byNumber.get('138/103'), '$304.99');
  assert.equal(byNumber.get('141/103'), '$247.06');
  assert.ok(nodes(body, node => node.tagName === 'a' && attr(node, 'href')?.startsWith('https://www.pricecharting.com/')).length);
});

test('both page owners keep one H1 and propagate their own metadata and cover into Article and social output', () => {
  const expectations = new Map([
    [mainPath, {phrase: /Delta Reign Card List/, h1: 'Delta Reign card list: all 141 English cards'}],
    [etbPath, {phrase: /Delta Reign Elite Trainer Box/, h1: 'Delta Reign ETB: Standard vs Pokémon Center'}],
  ]);
  for (const [path, expected] of expectations) {
    const source = registry.find(page => page.path === path);
    const compiled = articles.find(page => page.path === path);
    assert.ok(source && compiled, path);
    assert.equal(compiled.image, source.image);
    assert.equal(compiled.imageAlt, source.imageAlt);
    assert.match(source.image, /^\/assets\/guides\/.+\.png$/);
    const {tree} = render(path);
    const headings = nodes(tree, node => node.tagName === 'h1');
    assert.equal(nodes(articleBody(tree), node => node.tagName === 'p' && attr(node, 'class') === 'content-lede').length, 0, 'start with the answer instead of repeating the meta description');
    assert.equal(headings.length, 1, path);
    assert.equal(normalized(headings[0]), expected.h1);
    assert.match(normalized(nodes(tree, node => node.tagName === 'title')[0]), expected.phrase);
    assert.equal(attr(matching(tree, 'meta', 'name', 'description')[0], 'content'), source.description);
    assert.equal(attr(matching(tree, 'link', 'rel', 'canonical')[0], 'href'), origin + path);
    assert.equal(attr(matching(tree, 'meta', 'property', 'og:image')[0], 'content'), origin + source.image);
    assert.equal(attr(matching(tree, 'meta', 'property', 'og:image:alt')[0], 'content'), source.imageAlt);
    const schema = schemas(tree).find(item => item['@type'] === 'Article');
    assert.ok(schema, path);
    assert.equal(schema.headline, expected.h1);
    assert.equal(schema.author.name, 'Card AI');
    assert.equal(schema.publisher.name, 'Card AI');
    assert.equal(schema.mainEntityOfPage, origin + path);
    assert.equal(schema.datePublished, path === mainPath ? '2026-11-08' : '2026-11-16');
    assert.equal(schema.dateModified, '2026-11-19');
    const image = Array.isArray(schema.image) ? schema.image[0] : schema.image;
    assert.equal(typeof image === 'string' ? image : image?.url, origin + source.image);
    const bodyImage = matching(articleBody(tree), 'img', 'src', source.image)[0];
    assert.ok(bodyImage, path + ' body diagram');
    assert.ok(attr(bodyImage, 'alt')?.trim());
  }
});

test('home, Pokémon and set discovery point to the sole Delta Reign checklist owner', () => {
  const deltaSet = {id:'db-24831', name:'ME06: Delta Reign', code:'DLR', gameSlug:'pokemon', catalogedCount:141};
  const catalog = createRenderer({
    sets: [deltaSet],
    getSet: id => id === deltaSet.id ? deltaSet : null,
    queryCards: () => ({items:[], page:1, pageSize:24, total:0, hasMore:false}),
  });
  for (const path of ['/', '/games/pokemon', '/sets', '/sets/db-24831']) {
    const page = catalog.resolvePage(new URL(path, origin));
    assert.equal(page.status, 200, path);
    const links = matching(parse(page.html), 'a', 'href', mainPath);
    assert.ok(links.some(link => /Delta Reign.*card list/i.test(normalized(link))), path);
  }
  assert.doesNotMatch(publicSitemap(), /<loc>https:\/\/tcgcard\.fun\/sets\/db-24831<\/loc>/);
});

test('the two guides hand off through contextual links and appear with their own covers in their topic lists', () => {
  for (const [from, to] of [[mainPath, etbPath], [etbPath, mainPath]]) {
    const body = articleBody(render(from).tree);
    assert.ok(matching(body, 'a', 'href', to).length, `${from} → ${to}`);
    const source = registry.find(page => page.path === from);
    const list = render('/blog/category/' + source.category).tree;
    assert.ok(matching(list, 'a', 'href', from).length, from + ' topic link');
    const cover = matching(list, 'img', 'src', source.image)[0];
    assert.ok(cover, from + ' topic cover');
    assert.equal(attr(cover, 'alt'), source.imageAlt);
  }
});

test('the ETB article gives a same-page calculator with labels, external assets and a readable no-script route', () => {
  const {tree} = render(etbPath);
  const body = articleBody(tree);
  const component = nodes(body, node => attr(node, 'id') === 'etb-cost-calculator')[0];
  assert.ok(component);
  assert.equal(matching(body, 'a', 'href', '#etb-cost-calculator').length, 1);
  const form = nodes(component, node => node.tagName === 'form')[0];
  assert.ok(form);
  const controls = nodes(form, node => ['input', 'select'].includes(node.tagName));
  assert.ok(controls.some(node => attr(node, 'type') === 'number'));
  assert.ok(nodes(form, node => node.tagName === 'label').length >= 4);
  assert.ok(nodes(component, node => attr(node, 'aria-live') === 'polite' || attr(node, 'role') === 'status').length);
  assert.ok(matching(tree, 'script', 'src', '/assets/etb-calculator.js').some(node => attr(node, 'type') === 'module'));
  assert.ok(matching(tree, 'link', 'href', '/assets/etb-calculator.css').some(node => attr(node, 'rel') === 'stylesheet'));
  assert.ok(nodes(component, node => node.tagName === 'noscript').length);
  assert.doesNotMatch(attr(form, 'action') ?? '', /\/api(?:\/|$)/);
  for (const script of nodes(tree, node => node.tagName === 'script' && !attr(node, 'src'))) {
    assert.ok(['application/json', 'application/ld+json'].includes(attr(script, 'type')), 'no inline executable calculator script');
  }
  assert.match(normalized(body), /2026-11-16|November 16, 2026/);
  assert.match(normalized(body), /minimum|at least three/i);
  assert.match(normalized(body), /shipping.*not observed|shipping.*not established|shipping.*unknown/i);
});

test('the new ETB URL joins only approved production discovery while preview and query variants remain noindex', () => {
  const sitemap = publicSitemap();
  for (const path of [mainPath, etbPath]) {
    const url = new URL(path, origin);
    const {html, tree} = render(path);
    assert.ok(allStaticPaths.includes(path));
    assert.equal(attr(matching(tree, 'meta', 'name', 'robots')[0], 'content'), 'noindex,nofollow');
    assert.equal(mayIndex(url), true);
    assert.equal(attr(matching(parse(publishHtml(html, url)), 'meta', 'name', 'robots')[0], 'content'), 'index,follow');
    assert.ok(sitemap.includes(`<loc>${origin + path}</loc>`));
    assert.equal(mayIndex(new URL(path + '?q=delta', origin)), false);
    assert.equal(mayIndex(url, 503), false);
  }
  const paused = '/blog/pokemillion-guide';
  assert.ok(!registry.some(page => page.path === paused));
  assert.ok(!articles.some(page => page.path === paused));
  assert.ok(!allStaticPaths.includes(paused));
  assert.equal(renderer.resolvePage(new URL(paused, origin)).status, 404);
  assert.equal(mayIndex(new URL(paused, origin)), false);
  assert.ok(!sitemap.includes(origin + paused));
});

test('optional article covers stay local, carry alt text and preserve the legacy fallback when omitted', async () => {
  const root = await mkdtemp(join(tmpdir(), 'cardscanfox-guide-cover-'));
  try {
    await writeFile(join(root, 'sample.md'), '## Compare a card\n\nMatch the collector number first.\n');
    const meta = {
      path: '/blog/sample-cover', title: 'Sample cover | Card AI', description: 'A source-backed cover fixture.',
      h1: 'Sample cover', author: 'Card AI', file: 'sample.md', published: true, category: 'identity',
      publishedAt: '2026-11-16', sources: [{label: 'Manufacturer', url: 'https://tcg.pokemon.com/'}],
      image: '/assets/guides/sample-cover.png', imageAlt: 'A printing comparison diagram',
    };
    const withCover = await compileArticles([meta], {root});
    assert.equal(withCover[0].image, meta.image);
    assert.equal(withCover[0].imageAlt, meta.imageAlt);
    for (const image of ['javascript:alert(1)', '//example.com/cover.png', 'https://example.com/cover.png', '/assets/../outside.png']) {
      await assert.rejects(() => compileArticles([{...meta, image}], {root}), /image|cover|asset/i);
    }
    await assert.rejects(() => compileArticles([{...meta, imageAlt: ''}], {root}), /image|cover|alt/i);
    const {image, imageAlt, ...withoutCover} = meta;
    const plain = await compileArticles([withoutCover], {root});
    const fallback = createRenderer({articles: plain}).resolvePage(new URL(meta.path, origin));
    assert.equal(fallback.status, 200);
    assert.equal(attr(matching(parse(fallback.html), 'meta', 'property', 'og:image')[0], 'content'), origin + '/assets/legacy/hero-phones.png');
  } finally {
    await rm(root, {recursive: true, force: true});
  }
});
