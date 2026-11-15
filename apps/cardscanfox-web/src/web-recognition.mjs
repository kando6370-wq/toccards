const REQUEST_LIMIT = 32 * 1024;
const VECTOR_RESPONSE_LIMIT = 32 * 1024;
const CARD_RESPONSE_LIMIT = 256 * 1024;
const MAX_CANDIDATES = 5;
const JSON_TYPE = 'application/json';
const CARD_FIELDS = ['name', 'game', 'gameSlug', 'set_name', 'set_code', 'card_number', 'rarity', 'finish', 'language', 'object_type'];
const REFERENCE_FIELDS = ['seriesId', 'source', 'sourceLabel', 'metric', 'currency', 'language', 'finish', 'grader', 'gradeMin', 'gradeMax', 'condition', 'amount', 'priceAsOf', 'status', 'catalogVersion'];
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const jsonMime = message => message.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() === JSON_TYPE;
const usableId = value => typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$/.test(value);

class BodyLimitError extends Error {}

async function withSignal(promise, signal) {
 if (signal.aborted) { void Promise.resolve(promise).catch(() => {}); throw signal.reason; }
 let onAbort;
 const aborted = new Promise((_, reject) => {
  onAbort = () => reject(signal.reason);
  signal.addEventListener('abort', onAbort, {once:true});
 });
 try { return await Promise.race([promise, aborted]); }
 finally { signal.removeEventListener('abort', onAbort); }
}

async function boundedJson(message, limit, signal) {
 const declared = Number(message.headers.get('Content-Length'));
 if (Number.isFinite(declared) && declared > limit) throw new BodyLimitError();
 if (!message.body) throw new SyntaxError('Missing JSON body.');
 const reader = message.body.getReader(), chunks = [];
 let bytes = 0, complete = false;
 try {
  for (;;) {
   const {done, value} = await withSignal(reader.read(), signal);
   if (done) { complete = true; break; }
   bytes += value.byteLength;
   if (bytes > limit) throw new BodyLimitError();
   chunks.push(value);
  }
 } finally {
  if (!complete) void reader.cancel().catch(() => {});
  reader.releaseLock();
 }
 const body = new Uint8Array(bytes);
 let offset = 0;
 for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.byteLength; }
 return JSON.parse(new TextDecoder('utf-8', {fatal:true}).decode(body));
}

function recognitionInput(value) {
 if (!record(value) || !Array.isArray(value.vector) || value.vector.length !== 512 ||
     value.vector.some(n => typeof n !== 'number' || !Number.isFinite(n)) ||
     ![0, 1].includes(value.card_type) ||
     (value.game !== undefined && (value.game !== 'pokemon' || value.card_type !== 0))) return null;
 const norm = Math.hypot(...value.vector);
 if (!Number.isFinite(norm) || norm <= 0) return null;
 return {vector:value.vector, card_type:value.card_type, ...(value.game ? {game:value.game} : {})};
}

function recognitionCandidates(value) {
 if (!Array.isArray(value) || value.length > 50) return null;
 const seen = new Set(), candidates = [];
 for (const item of value) {
  if (!record(item)) return null;
  const id = Number.isInteger(item.product_id) && item.product_id >= 1 && item.product_id <= 4_294_967_295 ? String(item.product_id) : item.product_id;
  if (!usableId(id) || typeof item.confidence !== 'number' || !Number.isFinite(item.confidence) || item.confidence < 0 || item.confidence > 100) return null;
  if (!seen.has(id)) { seen.add(id); if (candidates.length < MAX_CANDIDATES) candidates.push({id, confidence:item.confidence}); }
 }
 return candidates;
}

function publicCard(card, candidate, input) {
 if (!record(card) || card.publicCardId !== candidate.id || typeof card.name !== 'string' || !card.name.trim() || card.name.length > 300) throw new Error('Invalid public card.');
 if (input.game === 'pokemon' && card.gameSlug !== 'pokemon') return null;
 if (input.card_type === 1 && card.object_type !== 'sports') return null;
 if (input.card_type === 0 && card.object_type === 'sports') return null;
 const price = card.price_usd ?? null;
 if (price !== null && (typeof price !== 'number' || !Number.isFinite(price) || price < 0)) throw new Error('Invalid published price.');
 const reference = record(card.reference) ? Object.fromEntries(REFERENCE_FIELDS.filter(key => card.reference[key] !== undefined).map(key => [key, card.reference[key]])) : null;
 const image = typeof card.image_url === 'string' ? card.image_url : '';
 let imageUrl;
 try { imageUrl = new URL(image, 'https://tcgcard.fun'); } catch { throw new Error('Invalid card image.'); }
 if (imageUrl.username || imageUrl.password || !((imageUrl.origin === 'https://image.tcgcard.fun' && imageUrl.pathname.startsWith('/cards/')) || (image.startsWith('/assets/cards/') && !image.startsWith('//')))) throw new Error('Invalid card image.');
 return {
  ...Object.fromEntries(CARD_FIELDS.map(key => [key, typeof card[key] === 'string' ? card[key] : null])),
  publicCardId:candidate.id, card_ref:candidate.id, product_id:candidate.id, confidence:candidate.confidence,
  image_url:image, price_usd:price, price_as_of:card.price_as_of ?? null, reference,
  detail_url:'/cards/' + encodeURIComponent(candidate.id),
 };
}

/** Public website-only vector matching. It never accepts images or writes App data. */
export async function handleWebRecognition(request, env) {
 const requestId = crypto.randomUUID();
 const headers = {'Content-Type':'application/json; charset=utf-8', 'Cache-Control':'no-store', 'X-Robots-Tag':'noindex, nofollow', 'X-Content-Type-Options':'nosniff', 'X-Request-Id':requestId};
 const respond = (body, status = 200, extra = {}) => new Response(request.method === 'HEAD' ? null : JSON.stringify(body), {status, headers:{...headers, ...extra}});
 const fail = (code, message, status, extra) => respond({success:false, error:{code, message}, meta:{requestId}}, status, extra);
 const unavailable = () => fail('WEB_SCANNER_UNAVAILABLE', 'Photo scanning is temporarily unavailable. Please try again later.', 503, {'Retry-After':'60'});
 const url = new URL(request.url);
 if (url.pathname !== '/site-api/v1/recognize') return fail('NOT_FOUND', 'Not found.', 404);
 if (request.method !== 'POST') return fail('METHOD_NOT_ALLOWED', 'Use POST for photo recognition.', 405, {'Allow':'POST'});
 if (request.headers.get('Origin') !== url.origin || request.headers.get('Sec-Fetch-Site') === 'cross-site') return fail('ORIGIN_NOT_ALLOWED', 'Use the scanner on this website.', 403);
 if (!jsonMime(request)) return fail('UNSUPPORTED_MEDIA_TYPE', 'Send an application/json request.', 415);
 if (url.search) return fail('VALIDATION_ERROR', 'Recognition does not accept URL parameters.', 422);
 const clientIp = request.headers.get('CF-Connecting-IP');
 if (!env.WEB_VECTOR_RECOGNITION?.fetch || !env.WEB_SCANNER_RATE_LIMITER?.limit || !env.SITE_DATA?.fetch ||
     !clientIp || clientIp.length > 64 || !/^[0-9a-f:.]+$/i.test(clientIp)) return unavailable();
 try {
  const limit = await withSignal(env.WEB_SCANNER_RATE_LIMITER.limit({key:'web-scan:' + clientIp}), AbortSignal.any([request.signal, AbortSignal.timeout(2000)]));
  if (!limit.success) return fail('RATE_LIMITED', 'Too many scans. Please wait before trying again.', 429, {'Retry-After':'60'});
 } catch { return unavailable(); }
 const bodySignal = AbortSignal.any([request.signal, AbortSignal.timeout(5000)]);
 let input;
 try { input = recognitionInput(await boundedJson(request, REQUEST_LIMIT, bodySignal)); }
 catch (error) {
  if (error instanceof BodyLimitError) return fail('PAYLOAD_TOO_LARGE', 'The recognition request is too large.', 413);
  if (bodySignal.aborted) return fail('REQUEST_TIMEOUT', 'The recognition request timed out.', 408);
  return fail('VALIDATION_ERROR', 'Invalid recognition request.', 422);
 }
 if (!input) return fail('VALIDATION_ERROR', 'Provide a valid 512-value vector and card type.', 422);
 const pipelineSignal = AbortSignal.any([request.signal, AbortSignal.timeout(20_000)]);
 const vectorSignal = AbortSignal.any([pipelineSignal, AbortSignal.timeout(10_000)]);
 let candidates;
 try {
  const upstream = await withSignal(env.WEB_VECTOR_RECOGNITION.fetch(new Request('https://recognize-vec.internal/recognize', {
   method:'POST', headers:{'Accept':JSON_TYPE, 'Content-Type':JSON_TYPE},
   body:JSON.stringify({vector:input.vector, card_type:input.card_type}), signal:vectorSignal, redirect:'manual',
  })), vectorSignal);
  if (!upstream.ok || !jsonMime(upstream)) { void upstream.body?.cancel().catch(() => {}); throw new Error('Recognition upstream unavailable.'); }
  candidates = recognitionCandidates((await boundedJson(upstream, VECTOR_RESPONSE_LIMIT, vectorSignal))?.candidates);
  if (!candidates) throw new Error('Invalid recognition response.');
 } catch {
  return vectorSignal.aborted ? fail('RECOGNITION_TIMEOUT', 'Card recognition timed out. Please try again.', 504) : fail('RECOGNITION_UNAVAILABLE', 'Card recognition is temporarily unavailable. Please try again.', 502);
 }
 let publicCandidates;
 const detailsController = new AbortController();
 try {
  publicCandidates = await Promise.all(candidates.map(async candidate => {
   const detailSignal = AbortSignal.any([pipelineSignal, detailsController.signal, AbortSignal.timeout(8000)]);
   const detail = await withSignal(env.SITE_DATA.fetch(new Request('https://site-data.internal/site-api/v1/cards/' + encodeURIComponent(candidate.id), {signal:detailSignal, redirect:'manual', headers:{'Accept':JSON_TYPE}})), detailSignal);
   if (detail.status === 404) { void detail.body?.cancel().catch(() => {}); return null; }
   if (!detail.ok || !jsonMime(detail)) { void detail.body?.cancel().catch(() => {}); throw new Error('Catalog unavailable.'); }
   const payload = await boundedJson(detail, CARD_RESPONSE_LIMIT, detailSignal);
   if (payload?.success !== true || payload.meta?.datasetMode !== 'published-read-only') throw new Error('Catalog is not public.');
   return publicCard(payload.data, candidate, input);
  }));
 } catch { detailsController.abort(); return fail('CATALOG_UNAVAILABLE', 'Card details are temporarily unavailable. Please try again later.', 503, {'Retry-After':'60'}); }
 const matches = publicCandidates.filter(Boolean);
 return respond({success:true, data:{status:matches.length ? 'matched' : 'no-match', candidates:matches}, meta:{requestId, datasetMode:'published-read-only'}});
}
