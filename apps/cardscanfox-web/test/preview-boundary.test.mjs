import assert from 'node:assert/strict';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {localAssetBinding} from '@kando/website-content/node-server';
import {build} from 'esbuild';import test from 'node:test';
const dir=await mkdtemp(join(tmpdir(),'cardscanfox-boundary-'));await build({entryPoints:[fileURLToPath(new URL('../worker/index.ts',import.meta.url))],outfile:join(dir,'worker.mjs'),bundle:true,platform:'neutral',format:'esm',target:'es2022'});const worker=(await import('file://'+join(dir,'worker.mjs'))).default;test.after(()=>rm(dir,{recursive:true,force:true}));
const assets={fetch:async()=>new Response('body{color:black}',{headers:{'Content-Type':'text/css'}})};
const env={DEPLOYMENT_MODE:'preview',LOCAL_DEVELOPMENT:'false',PUBLIC_ORIGIN:'https://tcgcard.fun',PREVIEW_USERNAME:'review',PREVIEW_PASSWORD:'test-only-long-review-password',ASSETS:assets,SITE_DATA:{fetch:async()=>new Response('{}',{headers:{'Content-Type':'application/json'}})}};
const authorization='Basic '+btoa('review:test-only-long-review-password');
test('preview authentication protects HTML and static assets before either is served',async()=>{for(const path of ['/','/site.css','/assets/cardscanfox-lime-mark.svg','/assets/cardscanfox-lime-wordmark.svg','/cards/714372']){const r=await worker.fetch(new Request('https://candidate.workers.dev'+path),env);assert.equal(r.status,401);assert.match(r.headers.get('X-Robots-Tag'),/noindex/);}});
test('authorized preview serves real content with noindex and no-store',async()=>{const r=await worker.fetch(new Request('https://candidate.workers.dev/blog/charizard-151-card-value',{headers:{Authorization:authorization}}),env);assert.equal(r.status,200);assert.match(r.headers.get('X-Robots-Tag'),/noindex/);assert.equal(r.headers.get('Cache-Control'),'no-store');assert.match(await r.text(),/006\/165/)});
test('the redesigned pages serve their linked stylesheets through the protected static asset routes',async()=>{
 const localAssets=localAssetBinding(fileURLToPath(new URL('../public/',import.meta.url)));
 const request=path=>new Request('https://candidate.workers.dev'+path,{headers:{Authorization:authorization}});
 const preview={...env,ASSETS:localAssets};
 for(const [path,theme]of [['/','home'],['/cards','page']]){
  const page=await worker.fetch(request(path),preview);
  assert.equal(page.status,200,path);
  const html=await page.text();
  for(const css of ['/assets/site-layout.css',`/assets/${theme}-layout.css`]){
   assert.ok(html.includes(`href="${css}"`),`${path} should link ${css}`);
   const unauthenticated=await worker.fetch(new Request('https://candidate.workers.dev'+css),preview);
   assert.equal(unauthenticated.status,401,css);
   const stylesheet=await worker.fetch(request(css),preview);
   assert.equal(stylesheet.status,200,css);
   assert.match(stylesheet.headers.get('Content-Type'),/^text\/css/);
  }
 }
});
test('missing preview credentials do not accidentally publish the candidate',async()=>{const r=await worker.fetch(new Request('https://candidate.workers.dev/'),{...env,PREVIEW_PASSWORD:''});assert.equal(r.status,401)});
test('the candidate refuses production mode until a reviewed cutover configuration exists',async()=>{const r=await worker.fetch(new Request('https://tcgcard.fun/'),{...env,DEPLOYMENT_MODE:'production'});assert.equal(r.status,503)});
test('legacy html aliases and blog trailing slash have explicit canonical redirects',async()=>{for(const [from,to]of [['/card-identifier.html','/card-identifier'],['/blog','/blog/'],['/blog/index.html','/blog/']]){const r=await worker.fetch(new Request('https://candidate.workers.dev'+from,{headers:{Authorization:authorization}}),env);assert.equal(r.status,308);assert.equal(r.headers.get('Location'),to)}});
test('data service failure returns 503 and does not fall back to the app production API',async()=>{const r=await worker.fetch(new Request('https://candidate.workers.dev/site-api/v1/cards',{headers:{Authorization:authorization}}),{...env,SITE_DATA:{fetch:async()=>{throw new Error('offline')}}});assert.equal(r.status,503);assert.equal((await r.json()).error.code,'SITE_DATA_UNAVAILABLE')});
test('the preview config declares no production route or business database binding',async()=>{const c=JSON.parse(await readFile(new URL('../wrangler.jsonc',import.meta.url),'utf8'));assert.equal(c.name,'cardscanfox-website-preview');assert.equal(c.vars.DEPLOYMENT_MODE,'preview');assert.equal(c.routes,undefined);assert.equal(c.hyperdrive,undefined);assert.equal(c.d1_databases,undefined);assert.equal(c.assets.run_worker_first,true)});

test('service mode cannot silently fall back to the review catalog',async()=>{const failing={...env,LOCAL_DEVELOPMENT:'true',CATALOG_MODE:'service',SITE_DATA:{fetch:async()=>new Response('offline',{status:503})}};const r=await worker.fetch(new Request('https://candidate.workers.dev/cards'),failing);assert.equal(r.status,503);assert.doesNotMatch(await r.text(),/145\.78/);const article=await worker.fetch(new Request('https://candidate.workers.dev/card-identifier'),failing);assert.equal(article.status,200)});
test('approved production settings do not expose review API payloads or carry preview noindex into old pages',async()=>{const production={...env,DEPLOYMENT_MODE:'production',CATALOG_MODE:'service',PUBLISH_READY:'true',SITE_DATA:{fetch:async()=>new Response(JSON.stringify({success:true,data:{items:[]},meta:{datasetMode:'review-snapshot'}}),{headers:{'Content-Type':'application/json'}})}};const api=await worker.fetch(new Request('https://tcgcard.fun/site-api/v1/cards'),production);assert.equal(api.status,503);const page=await worker.fetch(new Request('https://tcgcard.fun/card-identifier'),production);assert.equal(page.status,200);assert.equal(page.headers.get('X-Robots-Tag'),'index, follow');assert.match(await page.text(),/content="index,follow"/);const deletion=await worker.fetch(new Request('https://tcgcard.fun/Account/AccountSetup'),production);assert.equal(deletion.status,200);assert.equal(deletion.headers.get('X-Robots-Tag'),'noindex, follow');assert.match(await deletion.text(),/mailto:support@tcgcard\.fun/);const sitemap=await worker.fetch(new Request('https://tcgcard.fun/sitemap.xml'),production);assert.equal(sitemap.status,200);assert.match(await sitemap.text(),/https:\/\/tcgcard.fun\/sitemaps\/site.xml/);const site=await worker.fetch(new Request('https://tcgcard.fun/sitemaps/site.xml'),production),siteBody=await site.text();assert.match(siteBody,/https:\/\/tcgcard.fun\/privacy/);assert.doesNotMatch(siteBody,/Account\/AccountSetup/)});

test('production keeps the saved page out of robots blocking and exposes noindex nofollow',async()=>{const production={...env,DEPLOYMENT_MODE:'production',CATALOG_MODE:'service',PUBLISH_READY:'true',SITE_DATA:{fetch:async()=>new Response(JSON.stringify({success:true,data:{games:[],cards:[],sets:[],capturedAt:'2026-11-12'},meta:{datasetMode:'published-read-only',catalogVersion:'saved-test'}}),{headers:{'Content-Type':'application/json'}})}};const robots=await worker.fetch(new Request('https://tcgcard.fun/robots.txt'),production);assert.equal(robots.status,200);const robotsBody=await robots.text();assert.match(robotsBody,/Allow: \/\n/);assert.doesNotMatch(robotsBody,/Disallow: \/saved/);const saved=await worker.fetch(new Request('https://tcgcard.fun/saved'),production);assert.equal(saved.status,200);assert.equal(saved.headers.get('X-Robots-Tag'),'noindex, nofollow');assert.equal(saved.headers.get('Cache-Control'),'no-store');assert.match(await saved.text(),/content="noindex,nofollow"/);});


test('production HTML cache serves repeat requests without reloading the data service and supports conditional GET',async()=>{
 const original=globalThis.caches,entries=new Map(),pending=[];let calls=0;
 globalThis.caches={default:{match:async key=>entries.get(key.url)?.clone()??null,put:async(key,response)=>{entries.set(key.url,response.clone());}}};
 const c={publicCardId:'717605',card_ref:'717605',name:'Cache Test Card',game:'Pokemon',gameSlug:'pokemon',publicSetId:'db-C',set_name:'Cache Set',set_code:'CACHE',card_number:'001/010',image_url:'https://image.tcgcard.fun/cards/717605.jpg',price_usd:null,price_as_of:null,references:[]};
 const data={games:[{id:'1',slug:'pokemon',name:'Pokemon',cardCount:null}],sets:[{id:'db-C',name:'Cache Set',code:'CACHE',gameSlug:'pokemon',catalogedCount:null}],cards:[c],card:c,trend:{points:[]},capturedAt:'2026-11-07'};
 const configured={...env,DEPLOYMENT_MODE:'production',CATALOG_MODE:'service',PUBLISH_READY:'true',CF_VERSION_METADATA:{id:'cache-v1'},SITE_DATA:{fetch:async()=>{calls++;return new Response(JSON.stringify({success:true,data,meta:{datasetMode:'published-read-only',catalogVersion:'cache'}}));}}};
 const context={waitUntil:p=>pending.push(p)};
 try{const request=new Request('https://tcgcard.fun/cards/717605');const first=await worker.fetch(request,configured,context);assert.equal(first.status,200);assert.equal(first.headers.get('X-Robots-Tag'),'index, follow');await Promise.all(pending.splice(0));const tag=first.headers.get('ETag');assert.ok(tag);const conditional=await worker.fetch(new Request(request.url,{headers:{'If-None-Match':tag}}),configured,context);assert.equal(conditional.status,304);assert.equal(calls,1);await worker.fetch(request,{...configured,CF_VERSION_METADATA:{id:'cache-v2'}},context);assert.equal(calls,2);await Promise.all(pending);
 const paused={...c,publicCardId:'unlisted-printing',card_ref:'unlisted-printing'};
 const pausedEnv={...configured,SITE_DATA:{fetch:async()=>new Response(JSON.stringify({success:true,data:{...data,cards:[paused],card:paused},meta:{datasetMode:'published-read-only',catalogVersion:'paused'}}))}};
 const pausedResponse=await worker.fetch(new Request('https://tcgcard.fun/cards/unlisted-printing'),pausedEnv,context);
 assert.equal(pausedResponse.status,200);assert.equal(pausedResponse.headers.get('X-Robots-Tag'),'noindex, follow');assert.match(await pausedResponse.text(),/content="noindex,follow"/);await Promise.all(pending);
}finally{if(original===undefined)delete globalThis.caches;else globalThis.caches=original;}
});

test('production IndexNow key is readable as UTF-8 text without inherited preview robot directives',async()=>{
 const key='444eeb2ada28d44a7a587aee0cbe0591',path='/'+key+'.txt';
 const keyed={...env,ASSETS:{fetch:async()=>new Response(key+'\n',{headers:{'Content-Type':'text/plain','X-Robots-Tag':'noindex, nofollow, noarchive'}})}};
 const production={...keyed,DEPLOYMENT_MODE:'production',CATALOG_MODE:'service',PUBLISH_READY:'true'};
 for(const method of ['GET','HEAD']){const r=await worker.fetch(new Request('https://tcgcard.fun'+path,{method}),production);assert.equal(r.status,200);assert.equal(r.headers.get('X-Robots-Tag'),null);assert.equal(r.headers.get('Content-Type'),'text/plain; charset=utf-8');assert.equal(await r.text(),method==='HEAD'?'':key+'\n');}
 const locked=await worker.fetch(new Request('https://candidate.workers.dev'+path),keyed);assert.equal(locked.status,401);
 const preview=await worker.fetch(new Request('https://candidate.workers.dev'+path,{headers:{Authorization:authorization}}),keyed);assert.match(preview.headers.get('X-Robots-Tag'),/noindex/);
});

test('every published IndexNow key file contains its exact UTF-8 filename value and is served as a public production asset',async()=>{
 const {readdir}=await import('node:fs/promises');const root=new URL('../public/',import.meta.url);
 const files=(await readdir(root)).filter(f=>/^[a-f0-9]{32}\.txt$/.test(f));assert.ok(files.length>=1);
 for(const file of files){const text=await readFile(new URL(file,root),'utf8');assert.equal(text,file.slice(0,-4));const r=await worker.fetch(new Request('https://tcgcard.fun/'+file),{...env,DEPLOYMENT_MODE:'production',CATALOG_MODE:'service',PUBLISH_READY:'true',ASSETS:{fetch:async()=>new Response(text,{headers:{'X-Robots-Tag':'noindex'}})}});assert.equal(await r.text(),text);assert.equal(r.headers.get('X-Robots-Tag'),null);assert.equal(r.headers.get('Content-Type'),'text/plain; charset=utf-8');}
});

const crawlerAgent = 'Mozilla/5.0 (compatible; ChatGPT-User/1.0)';
const crawlerEnv = {
  ...env,
  DEPLOYMENT_MODE: 'production',
  CATALOG_MODE: 'service',
  PUBLISH_READY: 'true',
  PVUV_SITE: 'test-site',
  PVUV_INGEST_TOKEN: 'test-only-crawler-token',
};

test('production reports the crawler response in the background without sending the query or request headers', async t => {
  const pending = [];
  let finishReport;
  const collectorResponse = new Promise(resolve => { finishReport = resolve; });
  const collector = t.mock.method(globalThis, 'fetch', () => collectorResponse);
  const request = new Request('https://tcgcard.fun/blog?private=value', {
    method: 'HEAD',
    headers: { 'User-Agent': crawlerAgent, 'CF-Connecting-IP': '192.0.2.1', Cookie: 'session=test' },
  });
  const response = await worker.fetch(request, crawlerEnv, { waitUntil: promise => pending.push(promise) });
  assert.equal(response.status, 308);
  assert.equal(response.headers.get('Location'), '/blog/?private=value');
  assert.equal(pending.length, 1);
  assert.equal(collector.mock.callCount(), 1);
  const [url, options] = collector.mock.calls[0].arguments;
  assert.equal(url, 'https://api.pvuv.ai/v1/sites/test-site/crawler_hits');
  assert.equal(options.method, 'POST');
  assert.equal(options.redirect, 'manual');
  assert.deepEqual(options.headers, {
    Authorization: 'Bearer test-only-crawler-token',
    'Content-Type': 'application/json',
  });
  const { hits: [hit] } = JSON.parse(options.body);
  assert.ok(Number.isInteger(hit.ts));
  assert.deepEqual(hit, { ua: crawlerAgent, path: '/blog', ip: '192.0.2.1', status: 308, ts: hit.ts });
  finishReport(new Response('{}'));
  await Promise.all(pending);
});

test('PVUV skips normal traffic, API calls, assets, previews and sites without a token', async t => {
  const collector = t.mock.method(globalThis, 'fetch');
  const context = { waitUntil: () => assert.fail('Unexpected crawler report') };
  const request = (path, options) => new Request('https://tcgcard.fun' + path, {
    headers: { 'User-Agent': crawlerAgent },
    ...options,
  });
  await worker.fetch(request('/', { headers: { 'User-Agent': 'Mozilla/5.0' } }), crawlerEnv, context);
  await worker.fetch(request('/', { method: 'POST' }), crawlerEnv, context);
  for (const path of ['/site-api/v1/cards', '/%73ite-api/v1/cards', '/api/v1/config', '/_health', '/assets/site-layout.css']) {
    await worker.fetch(request(path), crawlerEnv, context);
  }
  await worker.fetch(request('/'), { ...crawlerEnv, DEPLOYMENT_MODE: 'preview' }, context);
  await worker.fetch(request('/'), { ...crawlerEnv, PUBLISH_READY: 'false' }, context);
  await worker.fetch(request('/'), { ...crawlerEnv, PVUV_INGEST_TOKEN: undefined }, context);
  await worker.fetch(new Request('https://preview.example/robots.txt', { headers: { 'User-Agent': crawlerAgent } }), crawlerEnv, context);
  assert.equal(collector.mock.callCount(), 0);
});

test('a rejected PVUV request leaves the production page response usable', async t => {
  t.mock.method(globalThis, 'fetch', async () => { throw new Error('collector offline'); });
  const warn = t.mock.method(console, 'warn', () => {});
  const pending = [];
  const response = await worker.fetch(
    new Request('https://tcgcard.fun/robots.txt', { headers: { 'User-Agent': 'Googlebot/2.1' } }),
    crawlerEnv,
    { waitUntil: promise => pending.push(promise) },
  );
  assert.equal(response.status, 200);
  assert.match(await response.text(), /Allow: \//);
  assert.equal(pending.length, 1);
  await Promise.all(pending);
  assert.deepEqual(warn.mock.calls[0].arguments, [{ event: 'pvuv_crawler_report_failed' }]);
});

test('GEO pages serve canonical HTML and llms.txt through the Worker', async () => {
 const localAssets = localAssetBinding(fileURLToPath(new URL('../public/', import.meta.url)));
 const production = {...env, DEPLOYMENT_MODE:'production', CATALOG_MODE:'service', PUBLISH_READY:'true', ASSETS:localAssets};
 const origin = 'https://tcgcard.fun';
 const policy = [
  ['/about', '/about/'],
  ['/compare/', '/compare'],
  ['/ai-card-recognition-accuracy/', '/ai-card-recognition-accuracy'],
  ['/card-price-data-methodology/', '/card-price-data-methodology'],
 ];
 const sitemap = await (await worker.fetch(new Request(origin + '/sitemaps/site.xml'), production)).text();
 for (const [path, alias] of policy) {
  const response = await worker.fetch(new Request(origin + path), production);
  assert.equal(response.status, 200, path);
  assert.equal(response.headers.get('X-Robots-Tag'), 'index, follow', path);
  assert.ok((await response.text()).includes('<link rel="canonical" href="' + origin + path + '">'), path);
  assert.ok(sitemap.includes('<loc>' + origin + path + '</loc>'), path);
  const redirected = await worker.fetch(new Request(origin + alias + '?ref=test'), production);
  assert.equal(redirected.status, 301, alias);
  assert.equal(redirected.headers.get('Location'), path + '?ref=test');
 }
 const manifest = await worker.fetch(new Request(origin + '/llms.txt'), production);
 assert.equal(manifest.status, 200);
 assert.equal(manifest.headers.get('Content-Type'), 'text/plain; charset=utf-8');
 assert.match(await manifest.text(), /^# CardScanFox/);
});

test('public scanner assets revalidate across visits while preview and failed assets remain private', async () => {
 const paths=['/assets/scanner/pe_core_t16_image_fp16.onnx','/assets/scanner/ort-wasm-simd-threaded.wasm'];
 const assetHeaders={'Cache-Control':'public, max-age=900',ETag:'"scanner"'};
 const binding={fetch:async req=>new Response(null,{status:req.headers.has('If-None-Match')?304:200,headers:assetHeaders})};
 const production={...env,DEPLOYMENT_MODE:'production',PUBLISH_READY:'true',CATALOG_MODE:'service',ASSETS:binding};
 for(const path of paths){
  const url='https://tcgcard.fun'+path;
  for(const method of ['GET','HEAD']){
   const fresh=await worker.fetch(new Request(url,{method}),production);
   assert.equal(fresh.headers.get('Cache-Control'),assetHeaders['Cache-Control']);
   assert.equal(fresh.headers.get('ETag'),assetHeaders.ETag);
   const hit=await worker.fetch(new Request(url,{method,headers:{'If-None-Match':assetHeaders.ETag}}),production);
   assert.equal(hit.status,304);assert.equal(hit.headers.get('Cache-Control'),assetHeaders['Cache-Control']);
  }
  const preview=await worker.fetch(new Request(url,{headers:{Authorization:authorization}}),{...env,ASSETS:binding});
  assert.equal(preview.headers.get('Cache-Control'),'no-store');
  const missing=await worker.fetch(new Request(url),{...production,ASSETS:{fetch:async()=>new Response(null,{status:404,headers:assetHeaders})}});
  assert.equal(missing.headers.get('Cache-Control'),'no-store');
 }
 const noPolicy={...production,ASSETS:{fetch:async()=>new Response(null,{headers:{ETag:'"site"'}})}};
 const css=await worker.fetch(new Request('https://tcgcard.fun/site.css'),noPolicy);
 assert.equal(css.headers.get('Cache-Control'),'public, max-age=0, must-revalidate');
 assert.equal(css.headers.get('ETag'),'"site"');
 const manifest=await worker.fetch(new Request('https://tcgcard.fun/release-manifest.json'),production);
 assert.equal(manifest.headers.get('Cache-Control'),'no-store');
});
