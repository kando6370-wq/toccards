import {htmlCacheKey,htmlEtag,conditionalHtml} from '../src/html-cache.mjs';
import { readBoundedJson } from '../src/read-json.mjs';
import { resolveServicePage } from '../src/live-render.mjs';
import { publishHtml, publicSitemap, sitemapIndex, mayIndex } from '../src/publication.mjs';
import { createRenderer, resolvePage, errorPage, legacyByPath } from '../src/render.mjs';

type RuntimeVariables = 'DEPLOYMENT_MODE'|'CATALOG_MODE'|'LOCAL_DEVELOPMENT'|'PUBLISH_READY';
type OptionalBindings = 'PREVIEW_USERNAME'|'PREVIEW_PASSWORD'|'CF_VERSION_METADATA';
export type WebsiteEnv = Omit<Env,RuntimeVariables|OptionalBindings> & Record<RuntimeVariables,string> & Partial<Pick<Env,OptionalBindings>>;
async function equalSecret(left: string, right: string): Promise<boolean> {
 const enc=new TextEncoder();const [a,b]=await Promise.all([crypto.subtle.digest('SHA-256',enc.encode(left)),crypto.subtle.digest('SHA-256',enc.encode(right))]);
 const x=new Uint8Array(a),y=new Uint8Array(b);let difference=0;for(let i=0;i<x.length;i++)difference|=x[i]^y[i];return difference===0;
}
async function previewAllowed(request: Request,env: WebsiteEnv):Promise<boolean>{
 if(String(env.LOCAL_DEVELOPMENT)==='true')return true;
 if(!env.PREVIEW_USERNAME||!env.PREVIEW_PASSWORD||env.PREVIEW_PASSWORD.length<12)return false;
 const authorization=request.headers.get('Authorization')??'';if(authorization.length>1024||!authorization.startsWith('Basic '))return false;
 try{return await equalSecret(atob(authorization.slice(6)),env.PREVIEW_USERNAME+':'+env.PREVIEW_PASSWORD)}catch{return false}
}
const liveContent=createRenderer({liveSite:true});
const securityHeaders={
 'X-Robots-Tag':'noindex, nofollow, noarchive',
 'Cache-Control':'no-store',
 'X-Content-Type-Options':'nosniff',
 'Referrer-Policy':'strict-origin-when-cross-origin',
 'X-Frame-Options':'DENY',
 'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'; base-uri 'self'"
};
export function createWebsiteHandler({publicPreview=false}={}) { return {
 async fetch(request:Request,env:WebsiteEnv,context?:ExecutionContext):Promise<Response>{
  const requestId=crypto.randomUUID();const headers=new Headers({...securityHeaders,'X-Request-Id':requestId,'X-Site-Release':'cardscanfox-independent-review'});
  const production=String(env.DEPLOYMENT_MODE)==='production';
  if(!['preview','production'].includes(String(env.DEPLOYMENT_MODE))||(production&&(String(env.PUBLISH_READY)!=='true'||String(env.CATALOG_MODE)!=='service')))return new Response('This candidate has no approved production cutover configuration.',{status:503,headers});
  if(!production&&!publicPreview&&!await previewAllowed(request,env)){headers.set('WWW-Authenticate','Basic realm="CardScanFox review", charset="UTF-8"');return new Response('Authorized review access is required.',{status:401,headers});}
  if(!['GET','HEAD'].includes(request.method)){headers.set('Allow','GET, HEAD');return new Response('Method not allowed',{status:405,headers});}
  const url=new URL(request.url);if(production)headers.delete('X-Robots-Tag');let pathname:string;try{pathname=decodeURI(url.pathname)}catch{return new Response('Invalid URL',{status:400,headers})}
  if(pathname.startsWith('/site-api/v1/')){
   try{const upstream=await env.SITE_DATA.fetch(new Request('https://site-data.internal'+url.pathname+url.search,{method:request.method,signal:AbortSignal.timeout(6500)}));if(production&&upstream.ok&&request.method!=='HEAD'){const body=await readBoundedJson(upstream);if(body.meta?.datasetMode!=='published-read-only')throw new Error('REVIEW_DATA_NOT_PUBLIC');const result=new Response(JSON.stringify(body),upstream);for(const [key,value]of headers)result.headers.set(key,value);return result;}const response=new Response(request.method==='HEAD'?null:upstream.body,upstream);for(const [key,value]of headers)response.headers.set(key,value);return response;}
   catch{headers.set('Content-Type','application/json; charset=utf-8');return new Response(JSON.stringify({success:false,error:{code:'SITE_DATA_UNAVAILABLE',requestId}}),{status:503,headers});}
  }
  if(pathname==='/robots.txt'){headers.set('Content-Type','text/plain; charset=utf-8');return new Response(request.method==='HEAD'?null:production?'User-agent: *\nAllow: /\nDisallow: /saved\nDisallow: /site-api/\nSitemap: https://tcgcard.fun/sitemap.xml\n':'User-agent: *\nDisallow: /\n',{headers});}
  if(pathname==='/sitemap.xml'||pathname.startsWith('/sitemaps/')){
   if(!production)return new Response('The review deployment does not publish a sitemap.',{status:404,headers});
   headers.set('Content-Type','application/xml; charset=utf-8');
   if(pathname==='/sitemaps/site.xml')return new Response(request.method==='HEAD'?null:publicSitemap(),{headers});
   try{const asset=await env.ASSETS.fetch(new Request('https://site-assets.internal/sitemaps/catalog-manifest.json'));const manifest=asset.ok&&asset.headers.get('Content-Type')?.includes('json')?await readBoundedJson(asset):{shards:[]};
    if(!Array.isArray(manifest.shards))throw new Error('Invalid sitemap manifest');
    if(pathname==='/sitemap.xml')return new Response(request.method==='HEAD'?null:sitemapIndex(manifest.shards),{headers});
    if(!manifest.shards.some((s:{path:string})=>s.path===pathname))return new Response('Not found',{status:404,headers});
    const source=await env.ASSETS.fetch(request);if(!source.ok)throw new Error('Missing sitemap asset');return new Response(request.method==='HEAD'?null:source.body,{headers});
   }catch{return new Response('Sitemap temporarily unavailable',{status:503,headers});}
  }
  if(pathname.endsWith('.html')){const canonical=pathname==='/index.html'?'/':pathname==='/blog/index.html'?'/blog/':pathname.slice(0,-5);if(legacyByPath.has(canonical)){headers.set('Location',canonical+url.search);return new Response(null,{status:308,headers});}}
  if(pathname==='/blog'){headers.set('Location','/blog/'+url.search);return new Response(null,{status:308,headers});}
  if(pathname.startsWith('/assets/')||['/site.css','/site.js','/444eeb2ada28d44a7a587aee0cbe0591.txt','/google406556797e3e830d.html','/release-manifest.json','/route-manifest.json'].includes(pathname)){
   const response=await env.ASSETS.fetch(request);const result=new Response(request.method==='HEAD'?null:response.body,response);for(const [key,value]of headers)result.headers.set(key,value);
   if(production&&pathname==='/444eeb2ada28d44a7a587aee0cbe0591.txt'){result.headers.delete('X-Robots-Tag');result.headers.set('Content-Type','text/plain; charset=utf-8');}
   return result;
  }
  const htmlCache=production&&typeof caches!=='undefined'&&'default' in caches?caches.default:null;
  const cacheKey=production?htmlCacheKey(request,env.CF_VERSION_METADATA?.id??'local'):null;
  if(htmlCache&&cacheKey){try{const cached=await htmlCache.match(cacheKey);if(cached){const freshHeaders=new Headers(cached.headers);freshHeaders.set('X-Request-Id',requestId);return conditionalHtml(request,cached.body,freshHeaders,cached.status);}}catch{console.error(JSON.stringify({event:'html_cache_read_failed',requestId}));}}
  try{const page=(String(env.CATALOG_MODE)==='service'?await resolveServicePage(url,env.SITE_DATA):null)??(String(env.CATALOG_MODE)==='service'?liveContent.resolvePage(url):resolvePage(url));headers.set('Content-Type','text/html; charset=utf-8');if(production){headers.set('X-Robots-Tag',mayIndex(url,page.status,page)?'index, follow':'noindex, follow');headers.set('Cache-Control',page.status===200&&url.pathname!=='/saved'?'public, max-age=0, s-maxage=60':'no-store');}const html=production?publishHtml(page.html,url,page.status,page):page.html;
   if(production&&page.status===200){headers.set('ETag',await htmlEtag(html));if(htmlCache&&cacheKey&&context&&request.method==='GET')context.waitUntil(htmlCache.put(cacheKey,new Response(html,{headers})).catch(()=>console.error(JSON.stringify({event:'html_cache_write_failed',requestId}))));return conditionalHtml(request,html,headers,page.status);}
   return new Response(request.method==='HEAD'?null:html,{status:page.status,headers});}
  catch(error){const invalid=error instanceof Error&&(error.name==='QueryError'||error instanceof URIError||error.message==='Invalid pricing selection.');const status=invalid?400:503;console.error(JSON.stringify({requestId,event:'page_render_failed',status,path:url.pathname,errorType:error instanceof Error?error.name:'Unknown'}));headers.set('Content-Type','text/html; charset=utf-8');return new Response(request.method==='HEAD'?null:errorPage(status,invalid?'Check the query or pricing selection.':'The catalog is temporarily unavailable. Existing articles and product guides remain available.'),{status,headers});}
 }
}; }
export default createWebsiteHandler();
