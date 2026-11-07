import assert from 'node:assert/strict';import test from 'node:test';
import {build} from 'esbuild';import{mkdtemp,rm}from'node:fs/promises';import{join}from'node:path';import{tmpdir}from'node:os';
import {hasPrice,money,queryCards} from '@kando/website-content';
const dir=await mkdtemp(join(tmpdir(),'cardscanfox-read-api-'));await build({entryPoints:[new URL('../src/worker.ts',import.meta.url).pathname],outfile:join(dir,'worker.mjs'),bundle:true,platform:'node',format:'esm',target:'es2022'});const {default:worker,createWebsiteService}=await import('file://'+join(dir,'worker.mjs'));test.after(()=>rm(dir,{recursive:true,force:true}));
const get=path=>worker.fetch(new Request('https://site-data.internal/site-api/v1'+path),{DEPLOYMENT_MODE:'preview'});
test('the isolated read API exposes actual snapshot totals and stable pagination',async()=>{const r=await get('/cards?pageSize=4');assert.equal(r.status,200);const b=await r.json();assert.equal(b.data.total,30);assert.equal(b.data.returnedCount,4);assert.equal(b.data.hasMore,true);assert.equal(b.data.nextPage,2);assert.equal(b.meta.datasetMode,'review-snapshot')});
test('filtered totals are not the current page length',async()=>{const r=await get('/cards?q=Umbreon&pageSize=2');const b=await r.json();assert.equal(b.data.total,5);assert.equal(b.data.returnedCount,2)});
test('invalid paging, excessive search and unsupported history windows fail explicitly',async()=>{for(const path of ['/cards?page=0','/cards?pageSize=999','/cards?sort=unknown','/cards?q='+('a'.repeat(129)),'/cards/714372/trend?days=90']){const r=await get(path);assert.equal(r.status,400,path);assert.equal((await r.json()).error.code,'INVALID_QUERY')}});
test('only the fixed 30-day trend is exposed, without fabricated history for other records',async()=>{const available=await(await get('/cards/714372/trend')).json();assert.equal(available.data.days,30);assert.equal(available.data.points.length,29);assert.ok(available.data.points.every(p=>p.date>='2026-10-08'));const missing=await(await get('/cards/722598/trend')).json();assert.equal(missing.data.status,'missing');assert.deepEqual(missing.data.points,[])});
test('zero and absent price remain different states',()=>{assert.equal(hasPrice({price_usd:0}),true);assert.equal(money(0),'$0.00');assert.equal(hasPrice({}),false);assert.equal(money(null),'Price unavailable')});
test('price sorting keeps missing records last rather than coercing them to zero',()=>{const rows=queryCards(new URLSearchParams({sort:'price-asc',pageSize:'48'})).items;const firstMissing=rows.findIndex(c=>!hasPrice(c));assert.ok(firstMissing>0);assert.ok(rows.slice(firstMissing).every(c=>!hasPrice(c)))});
test('unknown cards and old app/admin namespaces do not leak or proxy business data',async()=>{assert.equal((await get('/cards/not-found')).status,404);for(const path of ['/api/v1/auth/me','/api/v1/admin/users','/site-admin-api/v1/pages'])assert.equal((await worker.fetch(new Request('https://site-data.internal'+path),{DEPLOYMENT_MODE:'preview'})).status,404)});
test('the read API cannot write',async()=>{const r=await worker.fetch(new Request('https://site-data.internal/site-api/v1/cards',{method:'POST'}),{DEPLOYMENT_MODE:'preview'});assert.equal(r.status,405)});

test('database mode requires its own connection and never falls back to review data',async()=>{const r=await worker.fetch(new Request('https://site-data.internal/site-api/v1/cards'),{DEPLOYMENT_MODE:'preview',CATALOG_MODE:'postgres'});assert.equal(r.status,503);assert.equal((await r.json()).error.code,'CATALOG_UNAVAILABLE')});
test('production refuses the local review dataset',async()=>{const r=await worker.fetch(new Request('https://site-data.internal/site-api/v1/cards'),{DEPLOYMENT_MODE:'production',CATALOG_MODE:'snapshot'});assert.equal(r.status,503);assert.equal((await r.json()).error.code,'REVIEW_DATA_NOT_PUBLICATION_READY')});
test('duplicate and unknown parameters are rejected before any data operation',async()=>{for(const path of ['/cards?page=1&page=2','/cards?admin=true','/cards/714372/trend?days=365']){const r=await get(path);assert.equal(r.status,400,path)}});


test('the database budget rejects excess cold reads before opening a database connection',async()=>{
 let opened=0;const limited=createWebsiteService(async()=>{opened++;throw new Error('must not connect')});
 const env={DEPLOYMENT_MODE:'preview',CATALOG_MODE:'postgres',CATALOG_READ_BUDGET:{limit:async()=>({success:false})}};
 const response=await limited.fetch(new Request('https://site-data.internal/site-api/v1/cards'),env);
 assert.equal(response.status,429);assert.equal(response.headers.get('Retry-After'),'60');assert.equal(opened,0);assert.equal((await response.json()).error.code,'CATALOG_READ_BUDGET_EXCEEDED');
});

test('rankings are read from a complete snapshot without opening the business database',async()=>{
 let opened=0;const readonly=createWebsiteService(async()=>{opened++;throw Error('must not query')});
 const snapshot={schemaVersion:1,generatedAt:'2026-11-07T00:00:00Z',anchorDate:'2026-11-07',catalogVersion:'published-ranking',counts:{total:1},boards:{gainers:{kind:'gainers',items:[{rank:1,publicCardId:'100'}]},highest:{kind:'highest',items:[{rank:1,publicCardId:'100'}]}}};
 const env={DEPLOYMENT_MODE:'preview',CATALOG_MODE:'postgres',SITE_CACHE:{get:async()=>snapshot}};
 const r=await readonly.fetch(new Request('https://site-data.internal/site-api/v1/rankings/gainers'),env);assert.equal(r.status,200);assert.equal((await r.json()).data.items.length,1);assert.equal(opened,0);
 const missing=await readonly.fetch(new Request('https://site-data.internal/site-api/v1/rankings/gainers'),{...env,SITE_CACHE:{get:async()=>null}});assert.equal(missing.status,503);assert.equal(opened,0);
});
