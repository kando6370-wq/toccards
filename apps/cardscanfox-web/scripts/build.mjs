import { mkdir, readFile, writeFile, cp, rm, rename } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { build } from 'esbuild';
import { parse } from 'parse5';
import { inventory, hash, releaseFingerprint } from './release-tools.mjs';
import { copyCatalogSitemaps } from './copy-sitemaps.mjs';
import { compileFromProject } from './compile-articles.mjs';
await import('./import-legacy.mjs');
await compileFromProject();
const { resolvePage, allStaticPaths, errorPage, legacyPages }=await import('../src/render.mjs');
const { validateIndexPolicy }=await import('../src/publication.mjs');validateIndexPolicy();
const { catalogVersion }=await import('@kando/website-content');
const root=new URL('../',import.meta.url),dist=new URL('dist/',root),staging=new URL('.local/build-'+randomUUID()+'/',root),previous=new URL('.local/previous-dist/',root);
const visible=n=>['script','style','noscript'].includes(n.tagName)?'':n.nodeName==='#text'?n.value:(n.childNodes??[]).map(visible).join('');
const normalized=s=>s.replace(/\s+/g,' ').trim();
const routes=[];
await mkdir(staging,{recursive:true});
try{
 await cp(new URL('public/',root),staging,{recursive:true});
 await copyCatalogSitemaps(process.env.CATALOG_SITEMAPS_DIR??fileURLToPath(new URL('content/sitemaps/',root)),fileURLToPath(new URL('sitemaps/',staging)));
 for(const path of allStaticPaths){
  const result=resolvePage(new URL(path,'https://tcgcard.fun'));if(result.status!==200)throw new Error('Build route failed: '+path);
  const legacy=legacyPages.find(p=>p.path===path);
  if(legacy&&!normalized(visible(parse(result.html))).includes(normalized(visible(parse(legacy.bodyHtml)))))throw new Error('Protected content missing: '+path);
  const relative=path==='/'?'index.html':path.endsWith('/')?path.slice(1)+'index.html':path.slice(1)+'.html';
  const target=new URL(relative,staging);await mkdir(new URL('.',target),{recursive:true});await writeFile(target,result.html);
  routes.push({path,file:relative,protected:!!legacy,sourceBodyHash:legacy?.sourceBodyHash??null,htmlSha256:hash(result.html)});
 }
 await writeFile(new URL('404.html',staging),errorPage(404,'Return to the existing article address, catalog or homepage.'));
 await writeFile(new URL('robots.txt',staging),'User-agent: *\nDisallow: /\n');
 await writeFile(new URL('route-manifest.json',staging),JSON.stringify({mode:'review',routeCount:routes.length,routes},null,2)+'\n');
 if(process.argv.includes('--pages')){
  await build({entryPoints:[fileURLToPath(new URL('worker/pages.ts',root))],outfile:fileURLToPath(new URL('_worker.js',staging)),bundle:true,platform:'neutral',format:'esm',target:'es2022'});
  await writeFile(new URL('_routes.json',staging),JSON.stringify({version:1,include:['/*'],exclude:[]})+'\n');
 }
 const runtimeSources=[];for(const [prefix,source]of [['web/src',new URL('src/',root)],['web/worker',new URL('worker/',root)],['web/scripts',new URL('scripts/',root)],['service/src',new URL('../website-service/src/',root)],['content/src',new URL('../../packages/website-content/src/',root)],['content/data',new URL('../../packages/website-content/data/',root)]])for(const file of await inventory(fileURLToPath(source)))runtimeSources.push({path:prefix+'/'+file.path,sha256:file.sha256});runtimeSources.push({path:'pnpm-lock.yaml',sha256:hash(await readFile(new URL('../../pnpm-lock.yaml',root)))});for(const file of ['content/index-policy.json','content/seo-pages.json','content/answer-faqs.json','content/blog-topics.json','content/articles.json','wrangler.jsonc','wrangler.production.example.jsonc','wrangler.production.jsonc','wrangler.service-preview.example.jsonc'])runtimeSources.push({path:'web/'+file,sha256:hash(await readFile(new URL(file,root)))});
 const sourceCommit=process.env.CF_PAGES_COMMIT_SHA??process.env.WORKERS_CI_COMMIT_SHA??null;
 if(sourceCommit!==null&&!/^[a-f0-9]{40}$/.test(sourceCommit))throw new Error('Invalid build commit identity.');
 const manifest={schemaVersion:1,mode:'preview',sourceCommit,catalogVersion,runtimeSources,createdAt:new Date().toISOString(),routes,files:await inventory(fileURLToPath(staging))};manifest.releaseId=releaseFingerprint(manifest);
 await writeFile(new URL('release-manifest.json',staging),JSON.stringify(manifest,null,2)+'\n');
 await mkdir(new URL('.local/',root),{recursive:true});await rm(previous,{recursive:true,force:true});
 let moved=false;try{await rename(dist,previous);moved=true;}catch(error){if(error.code!=='ENOENT')throw error;}
 try{await rename(staging,dist);}catch(error){if(moved)await rename(previous,dist);throw error;}
 console.log(`Built ${routes.length} HTML routes, including ${legacyPages.length} protected legacy URLs. Release ${manifest.releaseId.slice(0,12)}. Review only; no publication.`);
}catch(error){await rm(staging,{recursive:true,force:true});throw error;}
