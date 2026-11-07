import { readBoundedJson } from './read-json.mjs';
import { createRenderer, legacyByPath, errorPage } from './render.mjs';
export const isCatalogPage = path => ['/', '/cards', '/games', '/sets', '/prices', '/saved'].includes(path) || /^\/(cards|games|sets)\/[^/]+$/.test(path);
function homeWithoutCatalog(url){const renderer=createRenderer({catalog:{mode:'published-read-only',catalogVersion:'unavailable',capturedAt:null},cards:[],sets:[],games:[],getCard:()=>null});const result=renderer.resolvePage(url);result.html=result.html.replace('<section id="homeView">','<section id="homeView"><p class="notice" role="status">The card catalog is temporarily unavailable. Product information and existing guides remain available.</p>');return result;}
export async function resolveServicePage(url, binding) {
 if (!isCatalogPage(url.pathname) || (legacyByPath.has(url.pathname) && url.pathname !== '/')) return null;
 const params=new URLSearchParams(url.searchParams);params.set('path',url.pathname);
 let response;try{response=await binding.fetch(new Request('https://site-data.internal/site-api/v1/page-data?'+params,{signal:AbortSignal.timeout(6500)}));}catch(error){if(url.pathname==='/')return homeWithoutCatalog(url);throw error;}
 if(response.status===400){const error=new Error('Check the catalog query and selected price context.');error.name='QueryError';throw error;}
 if(!response.ok){if(url.pathname==='/')return homeWithoutCatalog(url);throw new Error('CATALOG_UNAVAILABLE');}
 const payload=await readBoundedJson(response);const data=payload.data;
 if(payload.meta?.datasetMode!=='published-read-only'||!payload.success||!data||!Array.isArray(data.games)||!Array.isArray(data.cards)||!Array.isArray(data.sets))throw new Error('INVALID_CATALOG_RESPONSE');
 if(data.notFound)return {html:errorPage(404,'This catalog record does not exist or is not published.'),status:404};
 const labels=Object.fromEntries(data.games.map(g=>[g.slug,g.name]));
 const model={setPage:url.pathname==='/sets'?data.result:null,catalog:{mode:'published-read-only',catalogVersion:payload.meta.catalogVersion,capturedAt:data.capturedAt,sourceUrl:'https://api.tcgcard.fun/api/v1'},gameLabels:labels,games:data.games,sets:data.sets,cards:data.cards,getCard:id=>data.cards.find(c=>c.publicCardId===id)??null,getSet:id=>data.sets.find(s=>s.id===id)??null,getTrend:()=>data.trend??{points:[]},queryCards:()=>data.result??{items:[],page:1,pageSize:24,total:null,returnedCount:0,hasMore:false,nextPage:null}};
 const result=createRenderer(model).resolvePage(url);return {...result,dataAvailable:url.pathname==='/sets'?data.sets.length>0:url.pathname==='/games'?data.games.length>0:data.cards.length>0};
}
