import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {parse} from 'parse5';
import {legacyPages,resolvePage,allStaticPaths} from '../src/render.mjs';
import {mayIndex,publishHtml} from '../src/publication.mjs';

const accountPath='/Account/AccountSetup';
const attribute=(node,name)=>node.attrs?.find(item=>item.name===name)?.value;
function nodes(html,predicate){const found=[];const visit=node=>{if(predicate(node))found.push(node);for(const child of node.childNodes??[])visit(child);};visit(parse(html));return found;}

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

test('the request builder is local, starts without a platform, and preserves an email-only fallback without JavaScript',()=>{
 const {html}=resolvePage(new URL(accountPath,'https://tcgcard.fun'));
 assert.match(html,/Delete your Card AI account and data/);
 assert.match(html,/Card AI: TCG Card Scanner/);
 assert.match(html,/Already uninstalled the app/);
 assert.equal(nodes(html,node=>node.tagName==='form').length,0,'account email must never become a website form submission');
 const choices=nodes(html,node=>node.tagName==='input'&&attribute(node,'data-deletion-platform')!==undefined);
 assert.deepEqual(choices.map(node=>attribute(node,'value')),['android','ios']);
 assert.ok(choices.every(node=>attribute(node,'checked')===undefined),'the user must explicitly confirm which platform is in scope');
 assert.equal(nodes(html,node=>node.tagName==='fieldset').length,1);
 assert.equal(nodes(html,node=>node.tagName==='legend').length,1);
 const email=nodes(html,node=>node.tagName==='input'&&attribute(node,'data-deletion-email')!==undefined)[0];
 assert.equal(attribute(email,'type'),'email');assert.equal(attribute(email,'name'),undefined);
 assert.equal(attribute(email,'value'),undefined);assert.equal(attribute(email,'maxlength'),'254');
 assert.match(attribute(email,'aria-describedby'),/deletion-email-error/);
 const buttons=nodes(html,node=>node.tagName==='button'&&['data-open-deletion-email','data-copy-deletion-request'].some(name=>attribute(node,name)!==undefined));
 assert.equal(buttons.length,2);assert.ok(buttons.every(node=>attribute(node,'type')==='button'&&attribute(node,'disabled')!==undefined));
 assert.equal(nodes(html,node=>node.tagName==='noscript').length,1);
 const assistance=nodes(html,node=>node.tagName==='a'&&(attribute(node,'href')??'').includes('subject=Card%20AI%20account%20deletion%20assistance'))[0];
 assert.ok(assistance,'users who cannot provide an account email can request assistance without the builder');
 const href=new URL(attribute(assistance,'href'));
 assert.equal(href.pathname,'support@tcgcard.fun');assert.match(href.searchParams.get('body'),/cannot access or do not remember/);
 assert.equal(nodes(html,node=>node.tagName==='script'&&attribute(node,'src')==='/assets/account-deletion.js'&&attribute(node,'type')==='module').length,1);
 assert.equal(nodes(resolvePage(new URL('/help','https://tcgcard.fun')).html,node=>node.tagName==='script'&&attribute(node,'src')==='/assets/account-deletion.js').length,0,'the request script is isolated from unrelated pages');
});

test('scope, draft and assistance states remain accessible without pretending a request was received',()=>{
 const {html}=resolvePage(new URL(accountPath,'https://tcgcard.fun'));
 for(const name of ['data-ios-subscription','data-deletion-details','data-deletion-platform-error','data-deletion-email-error']){
  const item=nodes(html,node=>attribute(node,name)!==undefined)[0];assert.ok(item,name);assert.notEqual(attribute(item,'hidden'),undefined,name);
 }
 const output=nodes(html,node=>node.tagName==='textarea'&&attribute(node,'data-deletion-template')!==undefined)[0];
 assert.notEqual(attribute(output,'readonly'),undefined);assert.equal(attribute(output,'name'),undefined);
 const status=nodes(html,node=>attribute(node,'data-deletion-status')!==undefined)[0];
 assert.equal(attribute(status,'role'),'status');assert.equal(attribute(status,'aria-live'),'polite');
 assert.match(html,/Nothing|does not send your request/);
 assert.match(html,/Profile → Account → Delete Account/);
 assert.match(html,/does not delete the other platform account/);
 assert.match(html,/service provider’s deletion process/);
 assert.doesNotMatch(html,/Request submitted|Account deleted|ticket number|within \d+ days|business days/i);
});

test('Help and both footer sections expose the existing deletion URL without adding a top-level destination',()=>{
 for(const path of ['/','/help','/privacy']){
  const {html}=resolvePage(new URL(path,'https://tcgcard.fun'));
  const links=nodes(html,node=>node.tagName==='a'&&attribute(node,'href')===accountPath);
  assert.ok(links.length>=2,path+' must keep the public deletion entry discoverable');
 }
 const help=resolvePage(new URL('/help','https://tcgcard.fun')).html;
 assert.match(help,/How can I delete my Card AI account after uninstalling/);
 const page=resolvePage(new URL(accountPath,'https://tcgcard.fun')).html;
 const helpLinks=nodes(page,node=>node.tagName==='a'&&attribute(node,'href')==='/help'&&attribute(node,'aria-current')==='page');
 assert.equal(helpLinks.length,1,'the page belongs to the existing Help navigation');
});

test('the dedicated client asset is served by the existing assets rule and makes no server or analytics requests',async()=>{
 const source=await readFile(new URL('../public/assets/account-deletion.js',import.meta.url),'utf8');
 assert.doesNotMatch(source,/\bfetch\s*\(|XMLHttpRequest|WebSocket|sendBeacon|localStorage|sessionStorage|\/api\/|console\./);
 const css=await readFile(new URL('../public/site.css',import.meta.url),'utf8');
 assert.match(css,/\.account-deletion-layout/);
 assert.match(css,/\.account-deletion-email\{[^}]*font-size:16px/);
});
