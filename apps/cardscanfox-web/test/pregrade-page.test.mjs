import assert from 'node:assert/strict';
import test from 'node:test';
import {build} from 'esbuild';
import {mkdtemp,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {parse} from 'parse5';
import {resolvePage,allStaticPaths} from '../src/render.mjs';
import {mayIndex,publicSitemap} from '../src/publication.mjs';
const dir=await mkdtemp(join(tmpdir(),'cardscanfox-pregrade-'));
await build({entryPoints:[fileURLToPath(new URL('../worker/index.ts',import.meta.url))],outfile:join(dir,'worker.mjs'),bundle:true,platform:'neutral',format:'esm',target:'es2022'});
const worker=(await import('file://'+join(dir,'worker.mjs'))).default;
test.after(()=>rm(dir,{recursive:true,force:true}));
const env={DEPLOYMENT_MODE:'production',PUBLISH_READY:'true',CATALOG_MODE:'service',LOCAL_DEVELOPMENT:'false',SITE_DATA:{fetch:()=>{throw Error('The grading page must not query the catalog on every view.');}}};
const walk=(n,f)=>{f(n);for(const c of n.childNodes??[])walk(c,f);};
test('pregrading has a single SSR owner with a tool, dated references and separate catalog examples',()=>{
 const result=resolvePage(new URL('https://tcgcard.fun/ai-card-grading'));assert.equal(result.status,200);
 const doc=parse(result.html);let h1=0;walk(doc,n=>{if(n.tagName==='h1')h1++;});assert.equal(h1,1);
 for(const value of ['data-pregrade-form','data-photo-side="front"','data-photo-side="back"','data-pregrade-result','data-grading-cost-form','data-centering-form','/assets/web-pregrade.js'])assert.ok(result.html.includes(value),value);
 assert.match(result.html,/<title>AI Card Grading/);assert.match(result.html,/rel="canonical" href="https:\/\/tcgcard.fun\/ai-card-grading"/);
 assert.match(result.html,/Charizard/);assert.match(result.html,/Pikachu/);assert.match(result.html,/Gengar ex/);assert.match(result.html,/2026-11-15|Nov 15, 2026|15 Nov 2026/);
 assert.match(result.html,/catalog/i);assert.match(result.html,/not.{0,80}(?:pregrad|assessment|physical)/i);
 assert.ok(allStaticPaths.includes('/ai-card-grading'));assert.equal(mayIndex(new URL('https://tcgcard.fun/ai-card-grading')),true);assert.equal(mayIndex(new URL('https://tcgcard.fun/ai-card-grading?result=1')),false);
 assert.match(publicSitemap(),/https:\/\/tcgcard.fun\/ai-card-grading/);
});
test('the revised legal pages still explain what happens to pregrading photos and what estimates mean',()=>{
 const privacy=resolvePage(new URL('https://tcgcard.fun/privacy'));
 const terms=resolvePage(new URL('https://tcgcard.fun/terms'));
 for(const page of [privacy,terms]){
  assert.equal(page.status,200);
  assert.match(page.html,/Version date: November 26, 2026/);
 }
 assert.match(privacy.html,/sent to Cloudflare Workers AI/);
 assert.match(privacy.html,/does not save pregrading photos or results/);
 assert.match(terms.html,/separate from professional authentication and certified grading/);
});
test('production serves the independent page and never caches or indexes the assessment API',async()=>{
 const page=await worker.fetch(new Request('https://tcgcard.fun/ai-card-grading'),env);assert.equal(page.status,200);assert.equal(page.headers.get('X-Robots-Tag'),'index, follow');assert.match(page.headers.get('Content-Security-Policy'),/img-src 'self' data: blob:/);
 const response=await worker.fetch(new Request('https://tcgcard.fun/site-api/v1/pregrade',{method:'POST',headers:{Origin:'https://tcgcard.fun','Content-Type':'application/json'},body:'{}'}),env);
 assert.equal(response.status,503);assert.equal((await response.json()).error.code,'PREGRADING_UNAVAILABLE');assert.equal(response.headers.get('Cache-Control'),'no-store');assert.match(response.headers.get('X-Robots-Tag'),/noindex/);
 const get=await worker.fetch(new Request('https://tcgcard.fun/site-api/v1/pregrade'),env);assert.equal(get.status,405);assert.equal(get.headers.get('Allow'),'POST');
});
test('AI upload is behind the existing private preview gate',async()=>{
 const response=await worker.fetch(new Request('https://preview.workers.dev/site-api/v1/pregrade',{method:'POST',body:'{}'}),{...env,DEPLOYMENT_MODE:'preview'});
 assert.equal(response.status,401);assert.match(response.headers.get('WWW-Authenticate'),/Basic/);
});
