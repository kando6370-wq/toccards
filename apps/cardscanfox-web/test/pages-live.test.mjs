import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
const dir=await mkdtemp(join(tmpdir(),'cardscanfox-pages-'));
await build({entryPoints:[new URL('../worker/pages.ts',import.meta.url).pathname],outfile:join(dir,'pages.mjs'),bundle:true,platform:'neutral',format:'esm',target:'es2022'});
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
