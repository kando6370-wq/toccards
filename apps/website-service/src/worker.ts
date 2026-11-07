import { catalog, games, sets, getCard, getSet, getTrend, queryCards, publicEnvelope } from '@kando/website-content';
import { withReadOnlyCatalog } from './read-connection.mjs';

function connectionString(env: Env): string {
 const binding: unknown = Reflect.get(env, 'CATALOG_DB');
 if (binding && typeof binding === 'object' && 'connectionString' in binding && typeof binding.connectionString === 'string') return binding.connectionString;
 // The Node loopback runner supplies only its task-specific private variable.
 const local: unknown = Reflect.get(env, 'LOCAL_CATALOG_DATABASE_URL');
 if (typeof local === 'string' && local) return local;
 throw new Error('CATALOG_READ_CONNECTION_NOT_CONFIGURED');
}
const allowedParams = new Set(['q', 'game', 'set', 'language', 'finish', 'price', 'sort', 'page', 'pageSize', 'days', 'series', 'condition', 'grader', 'path', 'after']);
export function createWebsiteService(read = withReadOnlyCatalog) {
 return {
  async fetch(request: Request, env: Env, context?: ExecutionContext): Promise<Response> {
   const requestId = crypto.randomUUID();
   const headers: Record<string,string> = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex, nofollow', 'X-Content-Type-Options': 'nosniff', 'X-Request-Id': requestId };
   const respond = (data: unknown, status = 200) => new Response(request.method === 'HEAD' ? null : JSON.stringify(data), { status, headers });
   if (!['preview', 'production'].includes(String(env.DEPLOYMENT_MODE))) return respond({ success: false, error: { code: 'ENVIRONMENT_NOT_CONFIGURED', requestId } }, 503);
   if (!['GET', 'HEAD'].includes(request.method)) return respond({ success: false, error: { code: 'METHOD_NOT_ALLOWED', requestId } }, 405);
   const url = new URL(request.url), prefix = '/site-api/v1';
   if (!url.pathname.startsWith(prefix + '/')) return respond({ success: false, error: { code: 'NOT_FOUND', requestId } }, 404);
   const path = url.pathname.slice(prefix.length);
   try {
    if ([...url.searchParams.keys()].some(key => !allowedParams.has(key)) || [...url.searchParams].some(([key]) => url.searchParams.getAll(key).length !== 1)) return respond({ success: false, error: { code: 'INVALID_QUERY', requestId } }, 400);
    const mode = String(env.CATALOG_MODE ?? 'snapshot');
    if (String(env.DEPLOYMENT_MODE) === 'production' && mode !== 'postgres') return respond({ success: false, error: { code: 'REVIEW_DATA_NOT_PUBLICATION_READY', requestId } }, 503);
    let data: unknown;
    if (mode === 'snapshot') {
     if (path === '/health') data = { status: 'ok', mode: 'independent-read-only-review', capturedAt: catalog.capturedAt };
     else if (path === '/games') data = { items: games };
     else if (path === '/cards' || path === '/prices') data = queryCards(url.searchParams);
     else if (path === '/sets') { const game = url.searchParams.get('game'); const items = sets.filter(s => !game || game === 'all' || s.gameSlug === game); data = { items, total: items.length, returnedCount: items.length, hasMore: false, nextPage: null }; }
     else if (/^\/cards\/[^/]+\/trend$/.test(path)) data = getTrend(decodeURIComponent(path.split('/')[2]), url.searchParams);
     else if (/^\/cards\/[^/]+$/.test(path)) data = getCard(decodeURIComponent(path.split('/')[2]));
     else if (/^\/sets\/[^/]+$/.test(path)) { const set = getSet(decodeURIComponent(path.split('/')[2])); data = set ? { ...set, ...queryCards(new URLSearchParams({ ...Object.fromEntries(url.searchParams), set: set.id })) } : null; }
     else return respond({ success: false, error: { code: 'NOT_FOUND', requestId } }, 404);
     return data === null ? respond({ success: false, error: { code: 'NOT_FOUND', requestId } }, 404) : respond(publicEnvelope(data, requestId));
    }
    if (mode !== 'postgres') throw new Error('CATALOG_MODE_NOT_CONFIGURED');
    if (!['/health', '/games', '/cards', '/prices', '/sets', '/page-data'].includes(path) && !/^\/(?:cards\/[^/]+(?:\/trend)?|sets\/[^/]+)$/.test(path)) return respond({ success: false, error: { code: 'NOT_FOUND', requestId } }, 404);
    if (path.endsWith('/trend') && url.searchParams.has('days') && url.searchParams.get('days') !== '30') return respond({ success: false, error: { code: 'INVALID_QUERY', requestId } }, 400);
    const normalized = new URLSearchParams([...url.searchParams].sort(([a], [b]) => a.localeCompare(b)));
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('prod-catalog|'+(env.CF_VERSION_METADATA?.id??'local')+'|'+path + '?' + normalized));
    const key = new Request('https://catalog-cache.internal/' + Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, '0')).join(''));
    const cache = typeof caches !== 'undefined' && 'default' in caches ? caches.default : null;
    const cached = cache && path !== '/health' ? await cache.match(key) : null;
    if (cached) { const body = await cached.json() as { data: unknown; meta: object }; return respond({ success: true, ...body, meta: { ...body.meta, requestId } }); }
    if(env.CATALOG_READ_BUDGET&&!((await env.CATALOG_READ_BUDGET.limit({key:'catalog-database'})).success)){
     headers['Retry-After']='60';
     return respond({success:false,error:{code:'CATALOG_READ_BUDGET_EXCEEDED',requestId}},429);
    }
    const result = await read(connectionString(env), async store => {
     const meta = await store.context();
     if (path === '/health') data = { status: 'ok', mode: 'published-read-only' };
     else if (path === '/games') data = { items: meta.games };
     else if (path === '/page-data') data = await store.pageData(url.searchParams, meta);
     else if (path === '/cards' || path === '/prices') data = await store.listCards(url.searchParams, meta);
     else if (path === '/sets') data = await store.listSets(url.searchParams, meta);
     else if (path.endsWith('/trend')) data = await store.trend(decodeURIComponent(path.split('/')[2]), url.searchParams, meta);
     else if (path.startsWith('/cards/')) data = await store.getCard(decodeURIComponent(path.split('/')[2]), url.searchParams, meta);
     else data = await store.getSet(decodeURIComponent(path.split('/')[2]), url.searchParams, meta);
     return { data, meta: { requestId, catalogVersion: meta.catalogVersion, snapshotCapturedAt: meta.snapshotCapturedAt, datasetMode: meta.datasetMode, versionScope:'price-publication-pointers', directorySnapshot:false } };
    });
    if (result.data === null) return respond({ success: false, error: { code: 'NOT_FOUND', requestId } }, 404);
    const payload = { success: true, ...result };
    if (cache && path !== '/health' && context) context.waitUntil(cache.put(key, new Response(JSON.stringify(payload), { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=60' } })));
    return respond(payload);
   } catch (error) {
    const bad = error instanceof Error && (error.name === 'QueryError' || error instanceof URIError);
    console.error(JSON.stringify({ event: 'website_catalog_request_failed', requestId, status: bad ? 400 : 503, errorType: error instanceof Error ? error.name : 'Unknown' }));
    return respond({ success: false, error: { code: bad ? 'INVALID_QUERY' : 'CATALOG_UNAVAILABLE', message: bad && error instanceof Error ? error.message : 'The catalog is temporarily unavailable.', requestId } }, bad ? 400 : 503);
   }
  }
 };
}
export default createWebsiteService();
