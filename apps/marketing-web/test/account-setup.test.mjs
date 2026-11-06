import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const publicUrl = new URL('../public/', import.meta.url);

test('Account Setup exposes a platform-scoped manual deletion request', async () => {
  const [accountSetup, privacy] = await Promise.all([
    readFile(new URL('Account/AccountSetup.html', publicUrl), 'utf8'),
    readFile(new URL('privacy.html', publicUrl), 'utf8'),
  ]);

  assert.match(accountSetup, /mailto:support@tcgcard\.fun/);
  assert.match(accountSetup, /platform you want deleted/i);
  assert.match(accountSetup, /other platform account and its business data remain/i);
  assert.match(accountSetup, /requires registering a new platform account/i);
  assert.doesNotMatch(accountSetup, /within \d+ days|business days/i);
  assert.match(privacy, /href="\/Account\/AccountSetup"/);
  assert.match(privacy, /does not delete the other platform account/i);
});
