import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
const dir=await mkdtemp(join(tmpdir(),'cardscanfox-pages-'));
await build({entryPoints:[fileURLToPath(new URL('../worker/pages.ts',import.meta.url))],outfile:join(dir,'pages.mjs'),bundle:true,platform:'neutral',format:'esm',target:'es2022'});
const pages=(await import('file://'+join(dir,'pages.mjs'))).default;
test.after(()=>rm(dir,{recursive:true,force:true}));
const card={publicCardId:'live-900',card_ref:'live-900',name:'Published catalog card',game:'Pokemon',gameSlug:'pokemon',publicSetId:'db-L',set_name:'Live Set',set_code:'LIVE',card_number:'009/100',image_url:'https://image.tcgcard.fun/cards/live-900.jpg',price_usd:25.5,price_as_of:'2026-11-07',reference:{seriesId:'900',sourceLabel:'Published source',metric:'market',priceAsOf:'2026-11-07',amount:25.5,condition:'Near Mint',grader:'RAW'},references:[]};
const data={games:[{id:'1',slug:'pokemon',name:'Pokemon',cardCount:null}],sets:[{id:'db-L',name:'Live Set',code:'LIVE',gameSlug:'pokemon',catalogedCount:null}],cards:[card],card,trend:{reference:card.reference,points:[{date:'2026-11-06',price:25},{date:'2026-11-07',price:25.5}]},capturedAt:'2026-11-07',result:{items:[card],page:1,pageSize:24,total:null,returnedCount:1,hasMore:false}};
const env={ASSETS:{fetch:async()=>new Response('{"sourceCommit":"test-commit"}',{headers:{'Content-Type':'application/json'}})},SITE_DATA:{fetch:async()=>new Response(JSON.stringify({success:true,data,meta:{datasetMode:'published-read-only',catalogVersion:'live-publication'}}))}};
test('Pages renders a real catalog record outside the review build without adding a login or opening indexing',async()=>{
 const r=await pages.fetch(new Request('https://preview.pages.dev/cards/live-900'),env,{});
 assert.equal(r.status,200);assert.match(r.headers.get('X-Robots-Tag'),/noindex/);assert.equal(r.headers.get('Cache-Control'),'no-store');
 const html=await r.text();assert.match(html,/Published catalog card/);assert.match(html,/\$25\.50/);assert.match(html,/Published source/);assert.doesNotMatch(html,/145\.78/);
});
test('Pages never serves frozen card prices when its live service is missing; retained articles remain readable',async()=>{
 const unavailable={...env,SITE_DATA:{fetch:async()=>{throw new Error('not bound')}}};
 assert.equal((await pages.fetch(new Request('https://preview.pages.dev/cards'),unavailable,{})).status,503);
 assert.equal((await pages.fetch(new Request('https://preview.pages.dev/card-identifier'),unavailable,{})).status,200);
});
test('Pages keeps its build identity available and rejects mutations and preview sitemaps',async()=>{
 const manifest=await pages.fetch(new Request('https://preview.pages.dev/release-manifest.json'),env,{});assert.equal(manifest.status,200);assert.equal((await manifest.json()).sourceCommit,'test-commit');
 assert.equal((await pages.fetch(new Request('https://preview.pages.dev/site-api/v1/cards',{method:'POST'}),env,{})).status,405);
 assert.equal((await pages.fetch(new Request('https://preview.pages.dev/sitemap.xml'),env,{})).status,404);
});


test('live pages offer price sorting after a set is selected and show the required action in the catalog',async()=>{
 const global=await(await pages.fetch(new Request('https://preview.pages.dev/cards'),env,{})).text();assert.match(global,/Choose a set and apply filters/);assert.doesNotMatch(global,/<option value="price-desc"/);
 const scoped=await(await pages.fetch(new Request('https://preview.pages.dev/cards?set=db-L'),env,{})).text();assert.match(scoped,/<option value="price-desc"/);
 const prices=await(await pages.fetch(new Request('https://preview.pages.dev/prices'),env,{})).text();assert.match(prices,/name="set"/);assert.doesNotMatch(prices,/<option value="price-desc"/);
});

test('live navigation, download choices and paging explain the visitor task without internal review labels',async()=>{
 const pageData={...data,result:{...data.result,page:2,pageSize:24,total:241,totalKind:'cached-scan',returnedCount:24,hasPrevious:true,hasMore:true,previousCursor:'live-900',nextCursor:'live-999',countedAt:'2026-11-07T00:00:00Z'}};
 const real={...env,SITE_DATA:{fetch:async()=>new Response(JSON.stringify({success:true,data:pageData,meta:{datasetMode:'published-read-only',catalogVersion:'live'}}))}};
 const html=await(await pages.fetch(new Request('https://preview.pages.dev/cards?page=2&after=live-899'),real,{})).text();
 assert.doesNotMatch(html,/Independent review site|Total not computed/);assert.match(html,/Top 100/);assert.match(html,/rel="prev"/);assert.match(html,/before=live-900/);assert.match(html,/page=3/);assert.match(html,/Page <strong>2/);assert.match(html,/of about <strong>11/);assert.match(html,/About 241 cards/);assert.match(html,/href="\/download"/);
 const download=await(await pages.fetch(new Request('https://preview.pages.dev/download'),real,{})).text();assert.match(download,/Card AI for iOS/);assert.match(download,/Card AI for Android/);assert.match(download,/Coming soon/);assert.match(download,/chromewebstore\.google\.com/);assert.match(download,/apps\.apple\.com/);assert.doesNotMatch(download,/play\.google\.com/);
});
test('ranking rows link to the exact published price series and expose dates and comparison values',async()=>{
 const ranked={...card,rank:1,baseline_7d_price:20,baseline_7d_on:'2026-10-31',price_change_7d_percent:27.5};
 const real={...env,SITE_DATA:{fetch:async()=>new Response(JSON.stringify({success:true,data:{kind:'gainers',items:[ranked],generatedAt:'2026-11-07T00:00:00Z',anchorDate:'2026-11-07'},meta:{datasetMode:'published-read-only',catalogVersion:'ranked'}}))}};
 const html=await(await pages.fetch(new Request('https://preview.pages.dev/prices/top-gainers'),real,{})).text();assert.match(html,/27\.5%/);assert.match(html,/series=900/);assert.match(html,/\$20\.00/);assert.match(html,/Raw single cards/);assert.match(html,/7 Nov 2026/);
 const failed={...env,SITE_DATA:{fetch:async()=>new Response('Updating',{status:503})}};const pending=await pages.fetch(new Request('https://preview.pages.dev/prices/most-valuable'),failed,{});assert.equal(pending.status,503);assert.match(await pending.text(),/ranking is being prepared/);
});

test('homepage hero image, price record and detail link identify the same first featured printing',async()=>{
 const picks=[{...card,publicCardId:'home-a',name:'Home Charizard',price_usd:11},{...card,publicCardId:'home-b',name:'Home Pikachu',price_usd:22},{...card,publicCardId:'home-c',name:'Home Mew',price_usd:33}];
 const binding={fetch:async()=>new Response(JSON.stringify({success:true,data:{...data,cards:picks},meta:{catalogVersion:'home-test',datasetMode:'published-read-only'}}))};
 const response=await pages.fetch(new Request('https://preview.pages.dev/'),{...env,SITE_DATA:binding},{});const html=await response.text();
 assert.match(html,/href="\/cards\/home-a" class="scene-card scene-front"/);assert.match(html,/<a class="scene-record" href="\/cards\/home-a">[\s\S]*?Home Charizard[\s\S]*?\$11\.00/);
 assert.match(html,/Find the card you’re looking for/);assert.match(html,/physical TCG and sports cards/);assert.match(html,/href="\/games\/pokemon">Check Pokémon card prices/);assert.match(html,/class="fox-text-action" href="\/cards"/);assert.match(html,/Explore these Pokémon topics/);assert.match(html,/href="\/blog\/delta-reign-pokemon"/);assert.match(html,/href="\/blog\/mega-rayquaza-ex-card-values"/);
});
