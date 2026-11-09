import { readFile, writeFile, realpath } from 'node:fs/promises';
import { resolve, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Marked } from 'marked';
import { parseFragment, serialize } from 'parse5';

const categories = new Set(['identity', 'values', 'collecting', 'comparisons', 'opinion']);
const tags = new Set(['p', 'h2', 'h3', 'h4', 'ul', 'ol', 'li', 'blockquote', 'pre', 'code', 'em', 'strong', 'del', 'a', 'img', 'hr', 'br', 'table', 'thead', 'tbody', 'tr', 'th', 'td']);
const attributes = { a: new Set(['href', 'title']), img: new Set(['src', 'alt', 'title']), th: new Set(['align']), td: new Set(['align']), ol: new Set(['start']) };
const parser = new Marked({ gfm: true, async: false });
export function safeUrl(value, image = false) {
  if (/[\u0000-\u0020\u007f\\]/.test(value) || value.startsWith('//')) return false;
  if (value.startsWith('/')) return !value.startsWith('/../');
  if (!image && value.startsWith('#')) return true;
  try { return new URL(value).protocol === 'https:'; } catch { return false; }
}
export function renderMarkdown(markdown) {
  if (markdown.length > 250_000) throw new Error('Article body exceeds the file limit.');
  const fragment = parseFragment(parser.parse(markdown));
  function clean(parent) {
    for (const node of parent.childNodes ?? []) {
      if (node.nodeName === '#text') continue;
      if (!tags.has(node.tagName)) throw new Error(`Unsupported article HTML: ${node.tagName ?? node.nodeName}`);
      for (const attr of node.attrs ?? []) {
        if (!attributes[node.tagName]?.has(attr.name)) throw new Error(`Unsupported article attribute: ${attr.name}`);
        if (['href', 'src'].includes(attr.name) && !safeUrl(attr.value, attr.name === 'src')) throw new Error('Unsafe article URL.');
      }
      if (node.tagName === 'img') {
        if (!node.attrs.some(a => a.name === 'alt' && a.value.trim())) throw new Error('Article images need alternative text.');
        node.attrs.push({ name: 'loading', value: 'lazy' });
      }
      clean(node);
    }
  }
  clean(fragment);
  return serialize(fragment);
}
const isDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value ?? '') && new Date(value + 'T00:00:00Z').toISOString().slice(0, 10) === value;
export async function compileArticles(registry, { root, protectedPaths = [] }) {
  if (!Array.isArray(registry)) throw new Error('Article registry must be an array.');
  const seen = new Set(protectedPaths), articles = [];
  const contentRoot = resolve(root);
  for (const page of registry) {
    if (!page || !/^\/blog\/[a-z0-9]+(?:-[a-z0-9]+)*$/.test(page.path ?? '') || seen.has(page.path)) throw new Error('Duplicate, protected or invalid article path.');
    seen.add(page.path);
    for (const key of ['title', 'description', 'h1', 'author', 'file']) if (typeof page[key] !== 'string' || !page[key].trim()) throw new Error(`Article ${page.path} needs ${key}.`);
    if (typeof page.published !== 'boolean' || !categories.has(page.category) || !isDate(page.publishedAt) || (page.updatedAt && (!isDate(page.updatedAt) || page.updatedAt < page.publishedAt))) throw new Error(`Invalid article metadata: ${page.path}`);
    if (!Array.isArray(page.sources) || page.sources.length === 0 || page.sources.some(s => !s.label?.trim() || !safeUrl(s.url) || !s.url.startsWith('https:'))) throw new Error('Articles need labeled primary sources.');
    if (page.language !== undefined && !['en', 'de'].includes(page.language)) throw new Error('Unsupported article language.');
    const path = resolve(contentRoot, page.file);
    if (!path.startsWith(contentRoot + sep) || !path.endsWith('.md')) throw new Error('Article file must stay inside content/articles.');
    const resolvedFile=await realpath(path),resolvedRoot=await realpath(contentRoot);
    if(!resolvedFile.startsWith(resolvedRoot+sep))throw new Error('Article symlink leaves its content directory.');
    const bodyHtml = renderMarkdown(await readFile(resolvedFile, 'utf8'));
    if (!page.published) continue;
    articles.push({ id: page.path, path: page.path, type: 'article', title: page.title, description: page.description, h1: page.h1, author: page.author, category: page.category, ...(page.language ? {language:page.language} : {}), publishedAt: page.publishedAt, updatedAt: page.updatedAt ?? null, sources: page.sources.map(s => ({ label: s.label, url: s.url })), bodyHtml, protected: false });
  }
  return articles;
}
export async function compileFromProject() {
  const registry = JSON.parse(await readFile(new URL('../content/articles.json', import.meta.url), 'utf8'));
  const legacy = JSON.parse(await readFile(new URL('../../../packages/website-content/data/legacy-pages.json', import.meta.url), 'utf8'));
  const articles = await compileArticles(registry, { root: fileURLToPath(new URL('../content/articles/', import.meta.url)), protectedPaths: legacy.map(p => p.path) });
  await writeFile(new URL('../../../packages/website-content/data/articles.json', import.meta.url), JSON.stringify(articles, null, 2) + '\n');
  return articles;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) console.log(`Compiled ${(await compileFromProject()).length} published Markdown articles.`);
