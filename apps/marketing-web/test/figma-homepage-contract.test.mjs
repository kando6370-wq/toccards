import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const publicUrl = new URL('../public/', import.meta.url);
const indexPath = fileURLToPath(new URL('index.html', publicUrl));
const cssPath = fileURLToPath(new URL('site.css', publicUrl));

test('homepage keeps the Figma icon assets and supported-game layout', async () => {
  const html = await readFile(indexPath, 'utf8');
  const iconFiles = [
    'feature-icon-recognition.svg',
    'feature-icon-valuations.svg',
    'feature-icon-portfolio.svg',
    'feature-icon-market-data.svg',
    'feature-icon-wishlist.svg',
    'feature-icon-multi-game.svg',
  ];

  for (const iconFile of iconFiles) {
    assert.ok(html.includes(`/assets/${iconFile}`));
    await access(fileURLToPath(new URL(`assets/${iconFile}`, publicUrl)));
  }

  const gameLabels = [...html.matchAll(/<span class="game-tag">([^<]+)<\/span>/g)].map(
    ([, label]) => label,
  );
  assert.deepEqual(gameLabels, [
    'Pokemon Trading',
    'Yu-Gi-Oh!',
    'Magic: The Gathering',
    'One Piece Card Game',
    'Naruto Card Game',
    'Dragon Ball Super',
    'Digimon Card Game',
    'One Piece Card Game',
    'Basketball Cards',
    'Football Cards',
    'More Categories',
  ]);
});

test('homepage follows the latest Figma spacing and scan motion layers', async () => {
  const [html, css] = await Promise.all([
    readFile(indexPath, 'utf8'),
    readFile(cssPath, 'utf8'),
  ]);

  assert.match(css, /\.trust-row \{[^}]*padding-top: 32\.9px;/);
  assert.match(css, /\.tool-card \{[^}]*padding: 25px;/);
  assert.match(css, /\.steps-wrap \{[^}]*padding: 0 24px;/);
  assert.match(css, /\.detail-copy \{[^}]*display: flex;[^}]*gap: 24px;/);
  assert.match(css, /\.detail-copy ul \{[^}]*gap: 16px;[^}]*padding: 8px 0 0;/);
  assert.match(css, /\.detail-copy li \{[^}]*margin: 0;/);
  assert.match(css, /\.game-tag \{[^}]*padding: 8px 17px;/);
  assert.ok(html.includes('class="cta-brand-block"'));
  assert.match(css, /\.cta-brand-block \{[^}]*top: 156px;[^}]*height: 113px;/);
  assert.match(css, /\.new-footer-inner \{[^}]*width: min\(1680px,100%\);/);

  assert.ok(html.includes('class="scan-composite"'));
  assert.ok(html.includes('class="scan-card-motion"'));
  assert.ok(html.includes('/assets/showcase-scan-card.png'));
  await access(fileURLToPath(new URL('assets/showcase-scan-card.png', publicUrl)));
  assert.match(css, /\.scan-card-motion \{[^}]*animation: scan-card-float 2\.5s linear infinite;/);
  assert.doesNotMatch(css, /\.scan-visual img \{[^}]*animation:/);
  assert.match(
    css,
    /@media \(prefers-reduced-motion: reduce\) \{\s*\.scan-card-layer \{ display: none; \}\s*\}/,
  );
});
