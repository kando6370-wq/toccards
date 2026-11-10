import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {legacyPages,resolvePage,allStaticPaths} from '../src/render.mjs';
import {mayIndex,publishHtml} from '../src/publication.mjs';

const accountPath='/Account/AccountSetup';

test('the public account deletion page explains the platform-scoped operation',()=>{
 const page=resolvePage(new URL(accountPath,'https://tcgcard.fun'));
 assert.equal(page.status,200);
 assert.ok(allStaticPaths.includes(accountPath));
 assert.match(page.html,/mailto:support@tcgcard\.fun/);
 assert.match(page.html,/platform you want deleted/i);
 assert.match(page.html,/other platform account and its business data remain/i);
 assert.match(page.html,/requires registering a new platform account/i);
 assert.match(page.html,/does not cancel an Apple subscription/i);
 assert.doesNotMatch(page.html,/within \d+ days|business days/i);
});

test('privacy and the retained home legal source share the platform deletion contract',async()=>{
 const sources=[
  legacyPages.find(page=>page.path==='/privacy')?.bodyHtml??'',
  await readFile(new URL('../content/legacy/home.html',import.meta.url),'utf8'),
 ];
 for(const source of sources){
  assert.match(source,/href="\/Account\/AccountSetup"/);
  assert.match(source,/does not delete the other platform account/i);
  assert.match(source,/Deleted\s+business data is not restored/i);
 }
});

test('the deletion support page remains public but outside search indexing',()=>{
 const url=new URL(accountPath,'https://tcgcard.fun');
 const page=resolvePage(url);
 assert.equal(mayIndex(url,page.status,page),false);
 assert.match(publishHtml(page.html,url,page.status,page),/content="noindex,follow"/);
});
