import assert from 'node:assert/strict';
import test from 'node:test';
import {parse} from 'parse5';
import seoPages from '../content/seo-pages.json' with {type:'json'};
import {createRenderer, legacyPages} from '../src/render.mjs';
import {mayIndex, publicSitemap, publishHtml} from '../src/publication.mjs';

const origin = 'https://tcgcard.fun';
const auraPath = '/blog/aura-seeker-card-list';
const renderer = createRenderer({liveSite: true});

function render(path) {
  const url = new URL(path, origin);
  const page = renderer.resolvePage(url);
  assert.equal(page.status, 200, path);
  return {url, page};
}

test('Aura Seeker indexes the Japanese gallery and links to the English guide on site', () => {
  const {url, page} = render(auraPath);
  assert.match(page.html, /gallery showed <strong>79 records<\/strong>/);
  assert.match(page.html, /scheduled for <strong>November 27, 2026<\/strong>/);
  assert.doesNotMatch(page.html, /official image|m7-001-htfmi/);
  const mainNumbers = [...page.html.matchAll(/<td>(\d{3})\/078<\/td>/g)].map(match => match[1]);
  assert.equal(new Set(mainNumbers).size, 79);
  assert.deepEqual(mainNumbers.slice(0, 78), Array.from({length: 78}, (_, index) => String(index + 1).padStart(3, '0')));
  assert.match(page.html, /113\/078/);
  assert.match(page.html, /マキシの熱血/);
  assert.match(page.html, /href="\/blog\/flowing-fists-card-list">Flowing Fists guide/);
  assert.ok(page.html.includes(`<link rel="canonical" href="${url.href}">`));
  assert.ok(mayIndex(url, page.status, page));
  assert.match(publishHtml(page.html, url, page.status, page), /content="index,follow"/);
  assert.ok(publicSitemap(origin).includes(`<loc>${url.href}</loc>`));
  for (const listing of ['/blog/', '/blog/category/identity']) {
    assert.ok(render(listing).page.html.includes(`href="${auraPath}"`));
  }
  const flowing = render('/blog/flowing-fists-card-list').page;
  assert.match(flowing.html, /Flowing Fists card list/);
  assert.match(flowing.html, /No complete English Flowing Fists checklist is confirmed/);
  assert.match(flowing.html, /November 19, 2026<\/strong> announcement/);
  assert.match(flowing.html, /Aura Seeker card list<\/a> indexes the 78 Japanese M7 main-set numbers/);
  assert.ok(publicSitemap(origin).includes(`${origin}/blog/flowing-fists-card-list`));
});

test('November keyword guides retain price and rules context', () => {
  const checks = [
    ['/blog/mickey-mantle-rookie-card-value', /1951 Bowman #253/, /1952 Topps #311/, /AI card pregrading tool/],
    ['/blog/one-piece-tcg-ban-list', /OP14-020<\/td>\s*<td>Dracule Mihawk/, /November 27, 2026/, /North America, Europe, Oceania, Latin America and the Middle East/],
  ];
  for (const [path, first, second, third] of checks) {
    const {url, page} = render(path);
    assert.match(page.html, first);
    assert.match(page.html, second);
    assert.match(page.html, third);
    assert.ok(mayIndex(url, page.status, page));
    assert.ok(publicSitemap(origin).includes(`${origin}${path}`));
  }
});

test('Pokémon keyword updates keep one indexable owner per guide', () => {
  const checks = [
    ['/blog/pokemon-mcdonalds-2026', /November 10 through December 14/, /href="\/ai-card-grading"/],
    ['/blog/takumi-akabane-pokemon-cards', /021\/DPt-P/, /href="\/pokemon-card-scanner"/],
    ['/blog/flowing-fists-card-list', /February 6, 2027/, /No complete English Flowing Fists checklist/],
  ];
  const sitemap = publicSitemap(origin);
  for (const [path, answer, evidence] of checks) {
    const {url, page} = render(path);
    assert.match(page.html, answer);
    assert.match(page.html, evidence);
    assert.ok(page.html.includes(`<link rel="canonical" href="${url.href}">`));
    assert.ok(mayIndex(url, page.status, page));
    assert.ok(sitemap.includes(`<loc>${url.href}</loc>`));
  }
  assert.ok(render('/blog/category/identity').page.html.includes('href="/blog/takumi-akabane-pokemon-cards"'));
  assert.ok(!sitemap.includes('/blog/mcdonalds-pokemon-happy-meal-cards-2026'));
});

test('Charizard guides lead with their own set and valuation task without changing indexing or dated examples', () => {
  const checks = [
    ['/blog/charizard-151-card-value', 'Pokémon 151 Charizard ex', 'showcase-scan', 343, '$295.98', /English 199\/165 and .*Japanese Charizard ex 201\/165/],
    ['/blog/mega-charizard-x-ex-card-value', 'Mega Charizard X ex card value', 'showcase-analysis', 392, '$569.97', /125\/094<\/strong> is the Special Illustration Rare.*130\/094<\/strong> is the gold Mega Hyper Rare/],
  ];
  for (const [path, phrase, cover, height, historicalPrice, answer] of checks) {
    const {url, page} = render(path);
    const source = legacyPages.find(entry => entry.path === path);
    const published = publishHtml(page.html, url, page.status, page);
    const root = parse(published).childNodes.find(node => node.tagName === 'html');
    const head = root.childNodes.find(node => node.tagName === 'head');
    const title = head.childNodes.find(node => node.tagName === 'title');
    const description = head.childNodes.find(node => node.tagName === 'meta' && node.attrs.some(attr => attr.name === 'name' && attr.value === 'description'));
    const imagePath = `/assets/legacy/${cover}.png`;
    assert.ok(published.includes(source.bodyHtml), path);
    assert.equal(title.childNodes[0].value, seoPages[path].title, path);
    assert.equal(description.attrs.find(attr => attr.name === 'content').value, seoPages[path].description, path);
    assert.ok(published.includes(`<h1>${source.h1}</h1>`), path);
    assert.ok(title.childNodes[0].value.toLowerCase().includes(phrase.toLowerCase()), path);
    assert.ok(source.h1.toLowerCase().includes(phrase.toLowerCase()), path);
    const lead = source.bodyHtml.match(/<div class="content-prose">\s*<p>([^]*?)<\/p>\s*<figure/)[1];
    assert.match(lead, new RegExp(path.includes('mega-') ? 'Phantasmal Flames.*125/094.*130/094' : 'Pokémon 151.*006/165.*183/165.*199/165'));
    assert.ok(published.includes(`width="760" height="${height}"`), path);
    assert.ok(published.includes(`<meta name="twitter:card" content="summary_large_image">`), path);
    assert.ok(published.includes(`<meta name="twitter:image" content="${origin}${imagePath}">`), path);
    assert.ok(published.includes(`<meta property="og:image" content="${origin}${imagePath}">`), path);
    assert.ok(published.includes(historicalPrice), path);
    assert.ok(published.includes(`<link rel="canonical" href="${source.canonical}">`), path);
    assert.match(published, /content="index,follow"/);
    assert.match(published, answer);
  }
  const englishGuide = render(checks[0][0]).page.html;
  assert.doesNotMatch(render(checks[1][0]).page.html, /<title>[^<]*Pokémon 151/i);
  for (const [id, number] of [['502558', '006/165'], ['517017', '183/165'], ['517045', '199/165']]) {
    assert.ok(englishGuide.includes(`href="/cards/${id}">Charizard ex ${number}</a>`));
  }
});
