import assert from 'node:assert/strict';import test from 'node:test';
import {mkdtemp,rm} from 'node:fs/promises';import {tmpdir} from 'node:os';import {join} from 'node:path';import {fileURLToPath} from 'node:url';import {build} from 'esbuild';
const dir=await mkdtemp(join(tmpdir(),'cardscanfox-backoff-'));await build({entryPoints:[fileURLToPath(new URL('../worker/index.ts',import.meta.url))],outfile:join(dir,'worker.mjs'),bundle:true,platform:'neutral',format:'esm',target:'es2022'});const worker=(await import('file://'+join(dir,'worker.mjs'))).default;test.after(()=>rm(dir,{recursive:true,force:true}));
const environment=response=>({DEPLOYMENT_MODE:'production',LOCAL_DEVELOPMENT:'false',CATALOG_MODE:'service',PUBLISH_READY:'true',ASSETS:{fetch:async()=>new Response('unused')},SITE_DATA:{fetch:async()=>response()}});
const page=(path='/cards/717605',method='GET')=>new Request('https://tcgcard.fun'+path,{method});
test('limited catalog keeps the HTML503 contract and gives safe backoff without a retry or price fallback',async()=>{
 let calls=0;const logs=[];const original=console.error;console.error=v=>logs.push(v);
 try{const env=environment(()=>{calls++;return new Response('private-upstream-body',{status:429,headers:{'Retry-After':'60'}})});const r=await worker.fetch(page(),env);assert.equal(r.status,503);assert.equal(r.headers.get('Retry-After'),'60');assert.equal(r.headers.get('Cache-Control'),'no-store');assert.match(r.headers.get('X-Robots-Tag'),/noindex/);const h=await r.text();assert.match(h,/temporarily busy/);assert.doesNotMatch(h,/private-upstream-body|145\.78/);assert.equal(calls,1);const log=JSON.parse(logs[0]);assert.equal(log.upstreamStatus,429);assert.equal(log.reason,'UPSTREAM_RATE_LIMITED');assert.doesNotMatch(logs.join(''),/private-upstream-body/);}finally{console.error=original;}
});
test('invalid, missing and excessive backoff values are not copied; a valid HTTP date is preserved',async()=>{
 for(const value of [null,'later','-1','86401','999999999']){const headers=value===null?{}:{'Retry-After':value};const r=await worker.fetch(page(),environment(()=>new Response('',{status:429,headers})));assert.equal(r.status,503);assert.equal(r.headers.get('Retry-After'),null);}
 const date='Wed, 11 Nov 2026 12:00:00 GMT';const r=await worker.fetch(page(),environment(()=>new Response('',{status:429,headers:{'Retry-After':date}})));assert.equal(r.headers.get('Retry-After'),date);
});
test('home product information remains200 when catalog is busy; HEAD has no body',async()=>{
 const env=environment(()=>new Response('',{status:429,headers:{'Retry-After':'60'}}));const home=await worker.fetch(page('/'),env);assert.equal(home.status,200);const html=await home.text();assert.match(html,/temporarily busy/);assert.match(html,/Look up TCG and sports/);assert.doesNotMatch(html,/145\.78/);const head=await worker.fetch(page('/cards/717605','HEAD'),env);assert.equal(head.status,503);assert.equal(head.headers.get('Retry-After'),'60');assert.equal(await head.text(),'');
});
test('other faults stay generic503, invalid queries stay400 and the direct API keeps429',async()=>{
 for(const response of [()=>new Response('offline',{status:503}),()=>new Response('invalid-json'),()=>{throw new Error('upstream-timeout')}]){const r=await worker.fetch(page(),environment(response));assert.equal(r.status,503);assert.equal(r.headers.get('Retry-After'),null);assert.doesNotMatch(await r.text(),/temporarily busy/);}
 const invalid=await worker.fetch(page(),environment(()=>new Response('',{status:400})));assert.equal(invalid.status,400);
 const absent=await worker.fetch(page(),environment(()=>Response.json({success:true,data:{games:[],sets:[],cards:[],notFound:true},meta:{datasetMode:'published-read-only'}})));assert.equal(absent.status,404);
 const api=await worker.fetch(page('/site-api/v1/cards'),environment(()=>new Response('',{status:429,headers:{'Retry-After':'60'}})));assert.equal(api.status,429);assert.equal(api.headers.get('Retry-After'),'60');
});
