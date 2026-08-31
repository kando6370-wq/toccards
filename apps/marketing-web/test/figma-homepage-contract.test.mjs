import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const publicUrl = new URL('../public/', import.meta.url);
const indexPath = fileURLToPath(new URL('index.html', publicUrl));

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
