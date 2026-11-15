const ASSET_ROOT = '/assets/scanner/';
const INPUT_SIZE = 384;
const VECTOR_SIZE = 512;
const MAX_FILE_BYTES = 20 * 1024 * 1024;
const MAX_PIXELS = 24_000_000;
const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
let runtimePromise;
let sessionPromise;

class ScannerError extends Error {
 constructor(message) { super(message); this.name = 'ScannerError'; }
}

// Cancel this scan's wait without cancelling model loading shared by later scans.
export function waitForScan(operation, signal) {
 return new Promise((resolve, reject) => {
  let settled = false;
  const finish = (complete, value) => {
   if (settled) return;
   settled = true; signal.removeEventListener('abort', cancel); complete(value);
  };
  const cancel = () => finish(reject, signal.reason ?? new DOMException('Scan cancelled.', 'AbortError'));
  Promise.resolve(operation).then(value => finish(resolve, value), error => finish(reject, error));
  if (signal.aborted) cancel();
  else signal.addEventListener('abort', cancel, {once: true});
 });
}

export function validatePhoto(file) {
 if (!file || !IMAGE_TYPES.has(file.type)) throw new ScannerError('Choose a JPEG, PNG or WebP photo. Convert HEIC photos to JPEG first.');
 if (!Number.isSafeInteger(file.size) || file.size <= 0) throw new ScannerError('This photo is empty. Choose another photo.');
 if (file.size > MAX_FILE_BYTES) throw new ScannerError('This photo is over 20 MB. Choose a smaller photo.');
}

function loadRuntime() {
 if (!runtimePromise) {
  runtimePromise = new Promise((resolve, reject) => {
   const script = document.createElement('script');
   script.src = ASSET_ROOT + 'ort.wasm.min.js';
   script.async = true;
   script.onload = () => {
    if (!globalThis.ort?.InferenceSession) { script.remove(); reject(new ScannerError('The scanner could not load. Reload the page and try again.')); return; }
    const runtime = globalThis.ort;
    runtime.env.logLevel = 'error';
    runtime.env.wasm.numThreads = 1;
    runtime.env.wasm.proxy = false;
    runtime.env.wasm.wasmPaths = new URL(ASSET_ROOT, window.location.origin).href;
    resolve(runtime);
   };
   script.onerror = () => { script.remove(); reject(new ScannerError('The scanner files could not download. Check your connection and try again.')); };
   document.head.append(script);
  }).catch(error => { runtimePromise = null; throw error; });
 }
 return runtimePromise;
}

async function loadSession() {
 if (!sessionPromise) {
  sessionPromise = loadRuntime().then(async runtime => ({
   runtime,
   session: await runtime.InferenceSession.create(ASSET_ROOT + 'pe_core_t16_image_fp16.onnx', {
    executionProviders: ['wasm'], graphOptimizationLevel: 'all',
   }),
  })).catch(() => {
   sessionPromise = null;
   throw new ScannerError('The scanner could not start. Check your connection and try again in a current browser.');
  });
 }
 return sessionPromise;
}

async function decodePhoto(file, url) {
 let image;
 try {
  if (typeof createImageBitmap === 'function') image = await createImageBitmap(file);
  else image = await new Promise((resolve, reject) => {
   const element = new Image();
   element.onload = () => resolve(element);
   element.onerror = reject;
   element.src = url;
  });
 } catch { throw new ScannerError('This photo could not be opened. Save it as JPEG, PNG or WebP and try again.'); }
 const width = image.width || image.naturalWidth;
 const height = image.height || image.naturalHeight;
 if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0 || width * height > MAX_PIXELS) {
  image.close?.();
  throw new ScannerError('This photo is over 24 megapixels or has invalid dimensions. Resize it and try again.');
 }
 return image;
}

export function cardImageTensor(image, runtime, canvas = document.createElement('canvas')) {
 canvas.width = INPUT_SIZE; canvas.height = INPUT_SIZE;
 const context = canvas.getContext('2d', {willReadFrequently: true});
 if (!context) throw new ScannerError('This browser cannot prepare the photo. Try another browser or use text lookup.');
 context.imageSmoothingEnabled = true;
 context.imageSmoothingQuality = 'high';
 context.drawImage(image, 0, 0, INPUT_SIZE, INPUT_SIZE);
 const pixels = context.getImageData(0, 0, INPUT_SIZE, INPUT_SIZE).data;
 const plane = INPUT_SIZE * INPUT_SIZE, values = new Float32Array(plane * 3);
 for (let index = 0; index < plane; index++) {
  values[index] = pixels[index * 4] / 127.5 - 1;
  values[plane + index] = pixels[index * 4 + 1] / 127.5 - 1;
  values[plane * 2 + index] = pixels[index * 4 + 2] / 127.5 - 1;
 }
 return new runtime.Tensor('float32', values, [1, 3, INPUT_SIZE, INPUT_SIZE]);
}

async function extractVector(image, model) {
 const input = cardImageTensor(image, model.runtime);
 let outputs;
 try {
  outputs = await model.session.run({image: input});
  const embedding = outputs.embedding || outputs[model.session.outputNames[0]];
  const vector = embedding ? Array.from(embedding.data, Number) : [];
  if (vector.length !== VECTOR_SIZE || vector.some(value => !Number.isFinite(value)) || !vector.some(value => value !== 0)) {
   throw new ScannerError('The scanner could not read this photo. Try a clear, tightly framed photo of the card front.');
  }
  return vector;
 } finally {
  input.dispose?.();
  for (const tensor of new Set(Object.values(outputs || {}))) tensor.dispose?.();
 }
}

function element(tag, className, content) {
 const node = document.createElement(tag);
 if (className) node.className = className;
 if (content !== undefined) node.textContent = content;
 return node;
}

function cardPath(candidate) {
 const id = candidate.publicCardId ?? candidate.product_id;
 if (typeof id !== 'string' || !id || id.length > 128 || id !== id.trim() || /[\u0000-\u0020\u007f/\\]/.test(id) || id === '.' || id === '..') return null;
 return '/cards/' + encodeURIComponent(id);
}

function safeImage(value) {
 if (typeof value !== 'string') return null;
 try {
  const url = new URL(value, window.location.origin);
  if (url.origin === window.location.origin && url.pathname.startsWith('/assets/cards/')) return url.href;
  if (url.protocol === 'https:' && url.hostname === 'image.tcgcard.fun' && !url.port && !url.username && !url.password && url.pathname.startsWith('/cards/')) return url.href;
 } catch { /* A missing or invalid image does not invalidate the card record. */ }
 return null;
}

function priceDate(value) {
 if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
 const date = new Date(value + 'T12:00:00Z');
 if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) return null;
 return new Intl.DateTimeFormat('en-US', {month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC'}).format(date);
}

function candidateTile(candidate, path) {
 const item = element('article', 'web-scanner-candidate');
 const artwork = safeImage(candidate.image_url);
 if (artwork) {
  const image = element('img'); image.src = artwork; image.alt = candidate.name; image.width = 100; image.height = 140; image.loading = 'lazy'; image.referrerPolicy = 'no-referrer';
  image.addEventListener('error', () => { image.hidden = true; }, {once: true});
  item.append(image);
 }
 const copy = element('div', 'web-scanner-candidate-copy'), heading = element('h4'), link = element('a', '', candidate.name);
 link.href = path; heading.append(link); copy.append(heading);
 copy.append(element('p', 'web-scanner-card-number', [candidate.set_name, candidate.card_number].filter(value => typeof value === 'string' && value).join(' · ')));
 const printing = [candidate.language, candidate.finish].filter(value => typeof value === 'string' && value);
 if (printing.length) copy.append(element('p', 'small-note', printing.join(' · ')));
 const available = typeof candidate.price_usd === 'number' && Number.isFinite(candidate.price_usd) && candidate.price_usd >= 0;
 copy.append(element('p', 'web-scanner-price', available ? new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD'}).format(candidate.price_usd) : 'Price unavailable'));
 if (available) {
  const date = priceDate(candidate.price_as_of);
  copy.append(element('p', 'small-note', date ? 'USD reference · ' + date : 'USD reference · observation date not listed'));
 }
 if (typeof candidate.reference?.sourceLabel === 'string' && candidate.reference.sourceLabel) copy.append(element('p', 'small-note', 'Source: ' + candidate.reference.sourceLabel));
 const action = element('a', 'text-link', 'View card details'); action.href = path; copy.append(action);
 item.append(copy);
 return item;
}

function httpError(response) {
 if (response.status === 429) {
  const seconds = Number(response.headers.get('Retry-After'));
  return new ScannerError('Too many scans. Wait ' + (Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 3600 ? seconds : 60) + ' seconds, then try again.');
 }
 if (response.status === 503) return new ScannerError('Photo scanning is temporarily unavailable. Use text lookup below, or try again later.');
 if (response.status === 403) return new ScannerError('This scan could not be accepted. Reload this page and try again, or use text lookup below.');
 if (response.status === 413) return new ScannerError('This scan could not be sent. Try again, or use text lookup below.');
 if (response.status === 400 || response.status === 415 || response.status === 422) return new ScannerError('The scanner could not read this request. Reload the page and choose the photo again.');
 return new ScannerError('The matching service could not complete this scan. Try again, or use text lookup below.');
}

export function initWebScanner(root) {
 if (!root || root.dataset.scannerReady === 'true') return null;
 const mode = root.dataset.mode;
 if (!['pokemon', 'sports', 'tcg'].includes(mode)) return null;
 const find = selector => root.querySelector(selector);
 const form = find('[data-scan-form]'), fileInput = find('[data-scan-file]'), cameraInput = find('[data-camera-file]'), cameraButton = find('[data-open-camera]');
 const submit = find('[data-scan-submit]'), reset = find('[data-scan-reset]'), preview = find('[data-scan-preview]'), previewImage = find('[data-preview-image]'), caption = find('[data-preview-caption]');
 const status = find('[data-scan-status]'), error = find('[data-scan-error]'), results = find('[data-scan-results]'), candidates = find('[data-scan-candidates]');
 if (![form, fileInput, cameraInput, cameraButton, submit, reset, preview, previewImage, caption, status, error, results, candidates].every(Boolean)) return null;
 root.dataset.scannerReady = 'true';
 let selected = null, objectUrl = null, revision = 0, busy = false, preparing = false, activeRequest = null, disposed = false;
 const listeners = new AbortController();
 const controls = () => { submit.disabled = busy || preparing || !selected; submit.textContent = busy ? 'Identifying…' : 'Identify card'; submit.setAttribute('aria-busy', String(busy)); };
 const clearError = () => { error.hidden = true; error.textContent = ''; };
 const showError = message => { status.textContent = ''; error.textContent = message; error.hidden = false; };
 const releasePhoto = () => {
  selected?.close?.(); selected = null;
  preview.hidden = true; previewImage.removeAttribute('src'); caption.textContent = '';
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = null;
 };
 const clearResults = () => { results.hidden = true; candidates.replaceChildren(); };
 const cancelScan = () => {
  const previous = activeRequest;
  activeRequest = null; busy = false;
  previous?.abort();
 };
 const clearPhoto = () => {
  revision++; cancelScan(); releasePhoto(); preparing = false;
  fileInput.value = ''; cameraInput.value = ''; reset.hidden = true; clearError(); clearResults();
  status.textContent = 'Choose a card photo to start.'; controls();
 };
 async function choosePhoto(event) {
  const file = event.target.files?.[0];
  if (!file) return;
  const current = ++revision;
  cancelScan(); releasePhoto(); clearError(); clearResults();
  preparing = true; reset.hidden = false; status.textContent = 'Opening your photo…'; controls();
  let url;
  try {
   validatePhoto(file);
   url = URL.createObjectURL(file);
   const image = await decodePhoto(file, url);
   if (disposed || current !== revision) { image.close?.(); URL.revokeObjectURL(url); return; }
   selected = image; objectUrl = url; previewImage.src = url; preview.hidden = false;
   caption.textContent = file.name || 'Selected card photo';
   status.textContent = 'Photo ready. Select Identify card to find catalog matches.';
  } catch (failure) {
   if (url) URL.revokeObjectURL(url);
   if (!disposed && current === revision) showError(failure instanceof ScannerError ? failure.message : 'This photo could not be opened. Choose another photo.');
  } finally {
   if (!disposed && current === revision) { preparing = false; controls(); }
  }
 }
 async function scan(event) {
  event.preventDefault();
  if (busy || preparing || !selected || disposed) return;
  const current = revision;
  busy = true; clearError(); clearResults(); status.textContent = 'Loading scanner files (about 26 MB on first use)…'; controls();
  const controller = new AbortController(); activeRequest = controller;
  const totalTimeout = setTimeout(() => controller.abort(new ScannerError('This scan took too long. Check your connection and try again, or use text lookup below.')), 90_000);
  let timeout;
  try {
   const model = await waitForScan(loadSession(), controller.signal);
   if (disposed || current !== revision) return;
   status.textContent = 'Reading your card photo…';
   await waitForScan(new Promise(resolve => requestAnimationFrame(resolve)), controller.signal);
   if (disposed || current !== revision) return;
   const vector = await waitForScan(extractVector(selected, model), controller.signal);
   if (disposed || current !== revision) return;
   status.textContent = 'Finding matching cards and their published prices…';
   timeout = setTimeout(() => controller.abort(), 25_000);
   const response = await waitForScan(fetch('/site-api/v1/recognize', {
    method: 'POST', headers: {'Content-Type': 'application/json'}, credentials: 'same-origin', cache: 'no-store', signal: controller.signal,
    body: JSON.stringify({vector, card_type: mode === 'sports' ? 1 : 0, ...(mode === 'pokemon' ? {game: 'pokemon'} : {})}),
   }), controller.signal);
   if (!response.ok) throw httpError(response);
   const payload = await waitForScan(response.json(), controller.signal);
   if (disposed || current !== revision) return;
   if (payload?.success !== true || !['matched', 'no-match'].includes(payload.data?.status) || !Array.isArray(payload.data.candidates)) throw new ScannerError('The scan returned an incomplete result. Try again or use text lookup below.');
   const seen = new Set(), matches = [];
   for (const candidate of payload.data.candidates.slice(0, 20)) {
    if (!candidate || typeof candidate.name !== 'string' || !candidate.name.trim()) continue;
    if (mode === 'pokemon' && candidate.gameSlug !== 'pokemon') continue;
    if (mode === 'sports' && candidate.object_type !== 'sports') continue;
    if (mode === 'tcg' && candidate.object_type !== 'tcg') continue;
    const path = cardPath(candidate);
    if (!path || seen.has(path)) continue;
    seen.add(path); matches.push({candidate, path});
    if (matches.length === 5) break;
   }
   if (!matches.length) { status.textContent = 'No matching ' + (mode === 'pokemon' ? 'Pokémon card' : mode === 'tcg' ? 'trading card' : 'sports card') + ' was found. Try a clearer, tightly framed photo or use text lookup below.'; return; }
   for (const match of matches) candidates.append(candidateTile(match.candidate, match.path));
   results.hidden = false;
   status.textContent = matches.length + (matches.length === 1 ? ' candidate found. Compare it with your card below.' : ' candidates found. Compare them with your card below.');
  } catch (failure) {
   if (!disposed && current === revision) showError(failure instanceof ScannerError ? failure.message : controller.signal.aborted ? 'This scan took too long. Try again or use text lookup below.' : 'This scan could not finish. Check your connection and try again.');
  } finally {
   clearTimeout(timeout); clearTimeout(totalTimeout);
   if (activeRequest === controller) {
    activeRequest = null; busy = false;
    if (!disposed) controls();
   }
  }
 }
 fileInput.addEventListener('change', choosePhoto, {signal: listeners.signal});
 cameraInput.addEventListener('change', choosePhoto, {signal: listeners.signal});
 cameraButton.addEventListener('click', () => cameraInput.click(), {signal: listeners.signal});
 form.addEventListener('submit', scan, {signal: listeners.signal});
 reset.addEventListener('click', clearPhoto, {signal: listeners.signal});
 const destroy = () => { disposed = true; revision++; cancelScan(); listeners.abort(); releasePhoto(); root.dataset.scannerReady = 'false'; };
 window.addEventListener('pagehide', destroy, {once: true, signal: listeners.signal});
 clearPhoto();
 return {destroy};
}

if (typeof document !== 'undefined') for (const root of document.querySelectorAll('[data-web-scanner]')) initWebScanner(root);
if (typeof window !== 'undefined') window.addEventListener('pageshow', event => {
 if (event.persisted) for (const root of document.querySelectorAll('[data-web-scanner]')) initWebScanner(root);
});
