import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const indexPath = fileURLToPath(new URL('../public/index.html', import.meta.url));
const APP_STORE_URL =
  'https://apps.apple.com/us/app/card-ai-tcg-card-scanner/id6793017224';

test('both App Store downloads work without runtime config or database access', async () => {
  const html = await readFile(indexPath, 'utf8');
  const escapedUrl = APP_STORE_URL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  assert.equal(html.match(new RegExp(`href="${escapedUrl}"`, 'g'))?.length, 2);
  assert.doesNotMatch(html, /download-links\.mjs/);
  assert.doesNotMatch(html, /data-app-store-link/);
});
