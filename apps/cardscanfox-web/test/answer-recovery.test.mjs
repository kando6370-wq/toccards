import assert from 'node:assert/strict';
import test from 'node:test';
import {parse} from 'parse5';
import {createRenderer,allStaticPaths} from '../src/render.mjs';
import {mayIndex,publicSitemap} from '../src/publication.mjs';
const renderer=createRenderer({liveSite:true});
const render=path=>renderer.resolvePage(new URL(path,'https://tcgcard.fun')).html;
const visit=(node,fn)=>{fn(node);for(const child of node.childNodes??[])visit(child,fn);};
const attr=(node,name)=>node.attrs?.find(a=>a.name===name)?.value;
const text=node=>node.nodeName==='#text'?node.value:(node.childNodes??[]).map(text).join('');

test('DCC directly answers the checklist and pack questions with all 100 unique main numbers',()=>{
 const html=render('/blog/dungeon-crawler-carl-trading-cards'),numbers=[];
 visit(parse(html),node=>{if(node.tagName==='table'&&attr(node,'class')==='dcc-checklist')visit(node,row=>{if(row.tagName==='tr'&&row.childNodes.some(c=>c.tagName==='td'))numbers.push(Number(text(row.childNodes.find(c=>c.tagName==='td'))));});});
 assert.deepEqual(numbers,Array.from({length:100},(_,i)=>i+1));
 for(const answer of ['seven base cards and one chase card','Renegade','Where can you buy',"Borant\'s official card catalog"])assert.ok(html.includes(answer),answer);
 assert.doesNotMatch(html,/we have not verified|none guarantees|do not guarantee/i);
});

test('the anniversary card page contains all 191 linked single-card records with individual price dates',()=>{
 const html=render('/blog/pokemon-tcg-30th-celebration-card-prices'),rows=[];
 visit(parse(html),node=>{if(node.tagName==='tr'&&node.childNodes.some(c=>c.tagName==='td')){const cells=node.childNodes.filter(c=>c.tagName==='td');if(cells.length===4&&text(cells[2]).startsWith('$'))rows.push(cells);}});
 assert.equal(rows.length,191);
 for(const cells of rows){assert.match(text(cells[3]),/^\d{1,2} Nov 2026$/);let target;visit(cells[1],n=>{if(n.tagName==='a')target=attr(n,'href');});assert.match(target,/^\/cards\/\d+$/);}
 assert.ok(rows.some(c=>text(c[0])==='B/RGB'&&text(c[3])==='6 Nov 2026'));
 const upc=render('/blog/pokemon-upc-30th-anniversary');
 for(const answer of ['Espeon ex','Umbreon ex','November 6, 2026','29 regular booster packs','three-card Classic Collection pack'])assert.ok(upc.includes(answer),answer);
});

test('public pages use CardScanFox in copy, metadata and source attribution',()=>{
 for(const path of [...allStaticPaths,'/cards/714372','/not-a-real-article']){
  const html=render(path);
  assert.match(html,/<link rel="icon" href="\/assets\/card-ai-icon\.svg"/,path);
  assert.equal((html.match(/<img class="brand-icon" src="\/assets\/card-ai-icon\.svg" alt=""/g)??[]).length,2,path);
  assert.equal((html.match(/<span class="brand-name">CardScanFox<\/span>/g)??[]).length,2,path);
  assert.match(html,/aria-label="CardScanFox home"/,path);
  assert.match(html,/<meta property="og:site_name" content="CardScanFox">/,path);
  assert.match(html,/>Get CardScanFox /,path);
  if(path==='/')assert.match(html,/class="fox-final-mark" src="\/assets\/card-ai-icon\.svg"/,path);
  assert.doesNotMatch(html,/\/assets\/(?:card-ai-wordmark\.svg|legacy\/card-ai-logo\.png)/,path);
  // These pages identify the store app in its listing, approved policies or deletion request.
  if(!['/privacy','/terms','/Account/AccountSetup'].includes(path)){
   const copy = html.replaceAll('Card AI: TCG Card Scanner', '');
   assert.doesNotMatch(copy, /\bCard\s+AI\b/i, path);
  }
  visit(parse(html),node=>{if(node.tagName!=='script'||attr(node,'type')!=='application/ld+json')return;const json=text(node);const data=JSON.parse(json);if(path==='/blog/delta-reign-pokemon'&&data['@type']==='Article')assert.equal(data.publisher.logo.url,'https://tcgcard.fun/assets/cardscanfox-lime-wordmark.svg');for(const field of ['author','publisher'])if(data[field]){assert.match(data[field].name,/CardScanFox/,path+' '+field);}});
 }
 assert.match(render('/download'),/Listed on the App Store as <strong>Card AI: TCG Card Scanner<\/strong>/);
 assert.match(render('/download'),/Listed on Google Play as <strong>Card AI: TCG Card Scanner<\/strong>/);
 assert.match(render('/download'),/id6793017224/);
});

test('the retired generic value guide leaves discovery while the hub keeps its detailed printing guidance',()=>{
 const old='/blog/pokemon-card-values';assert.ok(!allStaticPaths.includes(old));assert.equal(mayIndex(new URL(old,'https://tcgcard.fun')),false);assert.doesNotMatch(publicSitemap(),/\/blog\/pokemon-card-values/);assert.doesNotMatch(render('/blog/category/values'),/href="\/blog\/pokemon-card-values"/);
 const hub=render('/games/pokemon');for(const answer of ['Browse card values by Pokemon','SV49/SV94','GG10/GG70','217/203','Check a number within its set'])assert.ok(hub.includes(answer),answer);
 assert.match(hub,/href="\/pokemon-card-scanner"/);assert.equal(renderer.resolvePage(new URL('/pokemon-card-scanner','https://tcgcard.fun')).status,200);
});


test('long checklist tables have focusable scroll regions instead of widening the whole article',()=>{
 for(const path of ['/blog/dungeon-crawler-carl-trading-cards','/blog/pokemon-tcg-30th-celebration-card-prices']){
  visit(parse(render(path)),node=>{if(node.tagName!=='table')return;const wrapper=node.parentNode;assert.equal(attr(wrapper,'class'),'reference-table-wrap');assert.equal(attr(wrapper,'role'),'region');assert.equal(attr(wrapper,'tabindex'),'0');});
 }
});
