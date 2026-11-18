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

test('Aura Seeker provides a source-linked Japanese preview, not an English checklist', () => {
  const {url, page} = render(auraPath);
  assert.match(page.html, /November 27, 2026.*scheduled release date in Japan/);
  assert.match(page.html, /preview covers selected official reveals, not the full Japanese checklist/);
  const revealedNumbers = [...page.html.matchAll(/<td>(\d{3})\/078<\/td>\s*<td>[^<]+<\/td>\s*<td><a href="https:\/\/www\.pokemon-card\.com\/ex\/m7\/assets\/images\/card\/m7-\1-[a-z0-9]+\.webp">/g)].map(match => match[1]);
  assert.deepEqual(revealedNumbers, ['013', '018', '020', '030', '057', '067']);
  assert.match(page.html, /No English entries are confirmed by the sources used for this preview/);
  assert.ok(page.html.includes(`<link rel="canonical" href="${url.href}">`));
  assert.ok(mayIndex(url, page.status, page));
  assert.match(publishHtml(page.html, url, page.status, page), /content="index,follow"/);
  assert.ok(publicSitemap(origin).includes(`<loc>${url.href}</loc>`));
  for (const listing of ['/blog/', '/blog/category/identity']) {
    assert.ok(render(listing).page.html.includes(`href="${auraPath}"`));
  }
  assert.equal(renderer.resolvePage(new URL('/blog/flowing-fists-card-list', origin)).status, 404);
});

test('Charizard answers supplement intact legacy pages without replacing the SEO metadata', () => {
  const checks = [
    ['/blog/charizard-151-card-value', /English 199\/165 and .*Japanese Charizard ex 201\/165/],
    ['/blog/mega-charizard-x-ex-card-value', /125\/094<\/strong> is the Special Illustration Rare.*130\/094<\/strong> is the gold Mega Hyper Rare/],
  ];
  for (const [path, answer] of checks) {
    const {url, page} = render(path);
    const source = legacyPages.find(entry => entry.path === path);
    const published = publishHtml(page.html, url, page.status, page);
    const root = parse(published).childNodes.find(node => node.tagName === 'html');
    const head = root.childNodes.find(node => node.tagName === 'head');
    const title = head.childNodes.find(node => node.tagName === 'title');
    const description = head.childNodes.find(node => node.tagName === 'meta' && node.attrs.some(attr => attr.name === 'name' && attr.value === 'description'));
    assert.ok(published.includes(source.bodyHtml), path);
    assert.equal(title.childNodes[0].value, seoPages[path].title, path);
    assert.equal(description.attrs.find(attr => attr.name === 'content').value, seoPages[path].description, path);
    assert.ok(published.includes(`<h1>${source.h1}</h1>`), path);
    assert.ok(published.includes(`<link rel="canonical" href="${source.canonical}">`), path);
    assert.match(published, /content="index,follow"/);
    assert.match(published, answer);
  }
  const englishGuide = render(checks[0][0]).page.html;
  for (const [id, number] of [['502558', '006/165'], ['517017', '183/165'], ['517045', '199/165']]) {
    assert.ok(englishGuide.includes(`href="/cards/${id}">Charizard ex ${number}</a>`));
  }
});
