const LASTMOD_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function isValidLastmod(value) {
  if (typeof value !== 'string' || !LASTMOD_PATTERN.test(value)) return false;

  const timestamp = Date.parse(`${value}T00:00:00Z`);
  return Number.isFinite(timestamp) && new Date(timestamp).toISOString().slice(0, 10) === value;
}

export function sitemapEntries(paths, lastmodByPath) {
  const pathSet = new Set(paths);
  const duplicate = [...new Set(paths.filter((path, index) => paths.indexOf(path) !== index))];
  const missing = paths.filter((path) => !lastmodByPath[path]);
  const stale = Object.keys(lastmodByPath).filter((path) => !pathSet.has(path));
  const invalid = Object.entries(lastmodByPath)
    .filter(([, lastmod]) => !isValidLastmod(lastmod))
    .map(([path]) => path);

  if (duplicate.length || missing.length || stale.length || invalid.length) {
    throw new Error(
      `Invalid sitemap lastmod inventory: duplicate=${duplicate.join(',') || 'none'}; missing=${missing.join(',') || 'none'}; stale=${stale.join(',') || 'none'}; invalid=${invalid.join(',') || 'none'}`,
    );
  }

  return paths.map((loc) => ({ loc, lastmod: lastmodByPath[loc] }));
}

export function renderSitemap(origin, urls) {
  const entries = urls
    .map(({ loc, lastmod }) => `<url><loc>${origin}${loc}</loc><lastmod>${lastmod}</lastmod></url>`)
    .join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">\n${entries}\n</urlset>\n`;
}
