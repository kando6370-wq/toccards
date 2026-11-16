const MAX_ORIGINAL_BYTES = 20 * 1024 * 1024;
const MAX_UPLOAD_BYTES = 1.5 * 1024 * 1024;
const MAX_PIXELS = 24_000_000;
const SIDES = ['front', 'back'];
const CRITERIA = ['centering', 'corners', 'edges', 'surface', 'print'];
const LABELS = {centering: 'Centering', corners: 'Corners', edges: 'Edges', surface: 'Surface', print: 'Print marks'};
const SEVERITIES = {none_visible: 'None visible', minor: 'Minor', moderate: 'Moderate', major: 'Major', unassessable: 'Not assessable'};
const QUALITIES = {good: 'Clear enough to assess', limited: 'Photo limits the assessment', unusable: 'Retake this photo'};

class PregradeError extends Error {
 constructor(message) { super(message); this.name = 'PregradeError'; }
}

export function validatePregradePhoto(file) {
 if (!file || !['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) throw new PregradeError('Choose a JPEG, PNG or WebP photo. Convert HEIC to JPEG first.');
 if (!Number.isSafeInteger(file.size) || file.size <= 0) throw new PregradeError('This photo is empty. Choose another photo.');
 if (file.size > MAX_ORIGINAL_BYTES) throw new PregradeError('This photo is over 20 MB. Resize it, then choose it again.');
}

export function normalizedPhotoSize(width, height) {
 if (![width, height].every(value => Number.isSafeInteger(value) && value > 0) || width * height > MAX_PIXELS) throw new PregradeError('Use a photo with no more than 24 megapixels.');
 const scale = Math.min(1, 1600 / Math.max(width, height));
 const size = {width: Math.round(width * scale), height: Math.round(height * scale)};
 if (Math.min(size.width, size.height) < 640) throw new PregradeError('Choose a sharper photo with at least 640 pixels on each side. Keep the card large in the frame.');
 return size;
}

// A canvas creates a new JPEG. Original EXIF, location and file metadata are not sent.
export async function preparePregradePhoto(file) {
 validatePregradePhoto(file);
 let image, objectUrl;
 try {
  if (typeof createImageBitmap === 'function') image = await createImageBitmap(file, {imageOrientation: 'from-image'});
  else {
   objectUrl = URL.createObjectURL(file);
   image = await new Promise((resolve, reject) => {
    const img = new Image(); img.onload = () => resolve(img); img.onerror = reject; img.src = objectUrl;
   });
  }
  const size = normalizedPhotoSize(image.width || image.naturalWidth, image.height || image.naturalHeight);
  const canvas = document.createElement('canvas'); canvas.width = size.width; canvas.height = size.height;
  const context = canvas.getContext('2d');
  if (!context) throw new PregradeError('This browser cannot prepare your photo. Try a current browser.');
  context.fillStyle = '#ffffff'; context.fillRect(0, 0, size.width, size.height);
  context.imageSmoothingEnabled = true; context.imageSmoothingQuality = 'high';
  context.drawImage(image, 0, 0, size.width, size.height);
  for (const quality of [0.92, 0.86, 0.8, 0.74, 0.68]) {
   const dataUrl = canvas.toDataURL('image/jpeg', quality);
   const bytes = Math.floor((dataUrl.length - dataUrl.indexOf(',') - 1) * 3 / 4);
   if (dataUrl.startsWith('data:image/jpeg;base64,') && bytes <= MAX_UPLOAD_BYTES) return {...size, dataUrl};
  }
  throw new PregradeError('This photo is too detailed to send within the upload limit. Resize it and try again.');
 } catch (failure) {
  if (failure instanceof PregradeError) throw failure;
  throw new PregradeError('This photo could not be opened. Save it as JPEG, PNG or WebP, then try again.');
 } finally {
  image?.close?.();
  if (objectUrl) URL.revokeObjectURL(objectUrl);
 }
}

export function calculateGradingCost(values) {
 const names = ['rawValue', 'grade8Value', 'grade9Value', 'grade10Value', 'serviceFee', 'shippingInsurance', 'sellingFeePercent'];
 if (!values || !names.every(name => typeof values[name] === 'number' && Number.isFinite(values[name]) && values[name] >= 0 && values[name] <= 10_000_000) || values.sellingFeePercent >= 100) throw new PregradeError('Enter all seven amounts. Use zero where a cost does not apply and a selling fee below 100%.');
 const rate = 1 - values.sellingFeePercent / 100;
 const cost = values.serviceFee + values.shippingInsurance;
 const rawNet = values.rawValue * rate;
 return {cost, rawNet, breakEven: values.rawValue + cost / rate, outcomes: [8, 9, 10].map(grade => {
  const salePrice = values['grade' + grade + 'Value'];
  const netAfterGrading = salePrice * rate - cost;
  return {grade, salePrice, netAfterGrading, difference: netAfterGrading - rawNet};
 })};
}

export function calculateBorderRatios(values) {
 if (!values || !['left', 'right', 'top', 'bottom'].every(name => typeof values[name] === 'number' && Number.isFinite(values[name]) && values[name] >= 0 && values[name] <= 100_000) || values.left + values.right === 0 || values.top + values.bottom === 0) throw new PregradeError('Enter four border measurements in the same unit. Each pair must have a total above zero.');
 const left = values.left / (values.left + values.right) * 100;
 const top = values.top / (values.top + values.bottom) * 100;
 return {left, right: 100 - left, top, bottom: 100 - top};
}

const validText = (value, limit = 900) => typeof value === 'string' && value.trim().length > 0 && value.length <= limit;
export function validatePregradeResult(payload) {
 const data = payload?.data;
 if (payload?.success !== true || !data || !['estimated', 'needs_better_photos'].includes(data.status) || !validText(data.summary, 1600) || !Array.isArray(data.issues) || data.issues.length > 10 || !data.issues.every(issue => validText(issue))) return false;
 if (data.status === 'estimated') {
  if (data.issues.length || !data.range || ![data.range.low, data.range.high].every(value => typeof value === 'number' && Number.isFinite(value) && value >= 1 && value <= 10) || data.range.low > data.range.high) return false;
 } else if (data.range !== null) return false;
 for (const side of SIDES) {
  const report = data[side];
  if (!report || !Object.hasOwn(QUALITIES, report.quality) || !Array.isArray(report.issues) || report.issues.length > 10 || !report.issues.every(issue => validText(issue))) return false;
  if (!CRITERIA.every(name => report[name] && Object.hasOwn(SEVERITIES, report[name].severity) && validText(report[name].observation))) return false;
  if (data.status === 'estimated' && (report.quality !== 'good' || report.issues.length || CRITERIA.some(name => report[name].severity === 'unassessable'))) return false;
 }
 return payload.meta?.method === 'photo-pregrade-v1' && validText(payload.meta.model, 160) && typeof payload.meta.assessedAt === 'string' && payload.meta.assessedAt.length <= 40 && Number.isFinite(Date.parse(payload.meta.assessedAt));
}

export function waitForAssessment(operation, signal) {
 return new Promise((resolve, reject) => {
  let settled = false;
  const finish = (complete, value) => { if (settled) return; settled = true; signal.removeEventListener('abort', cancel); complete(value); };
  const cancel = () => finish(reject, signal.reason ?? new DOMException('Assessment cancelled.', 'AbortError'));
  Promise.resolve(operation).then(value => finish(resolve, value), error => finish(reject, error));
  if (signal.aborted) cancel(); else signal.addEventListener('abort', cancel, {once: true});
 });
}

function node(tag, className, text) {
 const element = document.createElement(tag); if (className) element.className = className; if (text !== undefined) element.textContent = text; return element;
}
const currency = value => new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD'}).format(Math.abs(value) < 0.005 ? 0 : value);
const ratio = value => Number(value.toFixed(1)).toString();

function renderCost(root, result) {
 const box = root.querySelector('[data-cost-result]');
 const intro = node('p', '', 'Raw sale proceeds after the selling fee: ' + currency(result.rawNet) + '. Grading and round-trip shipping: ' + currency(result.cost) + '.');
 const table = node('table'), caption = node('caption', 'sr-only', 'Sale proceeds for each possible grade after the entered costs');
 const head = node('thead'), headRow = node('tr');
 for (const label of ['Outcome', 'Sale price', 'Net after grading', 'Difference vs raw']) { const th = node('th', '', label); th.scope = 'col'; headRow.append(th); }
 head.append(headRow); const body = node('tbody');
 for (const outcome of result.outcomes) {
  const row = node('tr'), title = node('th', '', 'Grade ' + outcome.grade); title.scope = 'row'; row.append(title);
  row.append(node('td', '', currency(outcome.salePrice)), node('td', '', currency(outcome.netAfterGrading)), node('td', outcome.difference < -0.005 ? 'pregrade-negative' : outcome.difference >= 0.005 ? 'pregrade-positive' : '', currency(outcome.difference)));
  body.append(row);
 }
 table.append(caption, head, body);
 const allLoss = result.outcomes.every(outcome => outcome.difference < 0);
 const someLoss = result.outcomes.some(outcome => outcome.difference < 0);
 const decision = node('p', '', allLoss ? 'At these prices, all three outcomes return less than selling raw after your entered costs.' : someLoss ? 'Some outcomes return less than selling raw. Inspect those outcomes before you choose a service.' : 'These three outcomes cover your entered costs. Confirm the sales and inspect your card before you submit it.');
 box.replaceChildren(intro, table, node('p', '', 'Break-even graded sale price: ' + currency(result.breakEven) + ' with these costs and this selling fee.'), decision); box.hidden = false;
}

function renderReport(root, payload) {
 const {data, meta} = payload;
 root.querySelector('[data-result-title]').textContent = data.status === 'estimated' ? 'A starting point for your decision.' : 'Better photos are needed.';
 root.querySelector('[data-result-range]').textContent = data.status === 'estimated' ? data.range.low + '–' + data.range.high + ' / 10' : 'No grade estimate';
 root.querySelector('[data-result-summary]').textContent = data.summary;
 const issues = root.querySelector('[data-result-issues]'); issues.replaceChildren();
 for (const issue of data.issues) issues.append(node('li', '', issue)); issues.hidden = data.issues.length === 0;
 const date = new Intl.DateTimeFormat('en-US', {month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC'}).format(new Date(meta.assessedAt));
 root.querySelector('[data-result-method]').textContent = 'Photo-based pregrade · ' + date + ' · This range is not calibrated to a specific grading company.';
 const sides = root.querySelector('[data-result-sides]'); sides.replaceChildren();
 for (const side of SIDES) {
  const report = data[side], section = node('section'), list = node('dl');
  section.append(node('h3', '', side === 'front' ? 'Card front' : 'Card back'), node('p', 'pregrade-quality', QUALITIES[report.quality]));
  if (report.issues.length) { const issues = node('ul'); for (const issue of report.issues) issues.append(node('li', '', issue)); section.append(issues); }
  for (const name of CRITERIA) {
   const criterion = node('div', 'pregrade-criterion'), title = node('dt', '', LABELS[name]); title.append(node('span', '', SEVERITIES[report[name].severity]));
   criterion.append(title, node('dd', '', report[name].observation)); list.append(criterion);
  }
  section.append(list); sides.append(section);
 }
 const result = root.querySelector('[data-pregrade-result]'); result.hidden = false; result.focus({preventScroll: true}); result.scrollIntoView({behavior: 'auto', block: 'start'});
}

function responseError(response) {
 if (response.status === 429) {
  const seconds = Number(response.headers.get('Retry-After'));
  return new PregradeError('The free assessment limit has been reached. Wait ' + (Number.isSafeInteger(seconds) && seconds > 0 && seconds <= 3600 ? seconds : 60) + ' seconds, then try again.');
 }
 if (response.status === 503) return new PregradeError('AI photo assessment is temporarily unavailable. Your photos have not been saved to a collection. Try again later.');
 if ([400, 413, 415, 422].includes(response.status)) return new PregradeError('These photos could not be accepted. Choose clear front and back photos again, then retry.');
 if (response.status === 403) return new PregradeError('This request could not be accepted. Reload this page, then choose your photos again.');
 return new PregradeError('The AI service could not complete this assessment. Try again later.');
}

async function readResult(response, signal) {
 if (!response.headers.get('Content-Type')?.toLowerCase().includes('application/json') || Number(response.headers.get('Content-Length')) > 65_536) throw new PregradeError('The assessment returned an incomplete result. Try again later.');
 const reader = response.body?.getReader(); if (!reader) throw new PregradeError('The assessment result was empty. Try again later.');
 let size = 0, text = ''; const decoder = new TextDecoder();
 try {
  while (true) {
   const {done, value} = await waitForAssessment(reader.read(), signal); if (done) break;
   size += value.byteLength; if (size > 65_536) throw new PregradeError('The assessment returned an incomplete result. Try again later.');
   text += decoder.decode(value, {stream: true});
  }
  text += decoder.decode(); return JSON.parse(text);
 } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
}

function formNumbers(form, names) {
 return Object.fromEntries(names.map(name => { const value = form.elements.namedItem(name)?.value; return [name, typeof value === 'string' && value.trim() ? Number(value) : NaN]; }));
}

export function initWebPregrade(root) {
 if (!root || root.dataset.pregradeReady === 'true') return null;
 const find = selector => root.querySelector(selector);
 const form = find('[data-pregrade-form]'), submit = find('[data-pregrade-submit]'), cancel = find('[data-pregrade-cancel]'), clear = find('[data-pregrade-clear]'), consent = find('[data-pregrade-consent]'), status = find('[data-pregrade-status]'), error = find('[data-pregrade-error]'), result = find('[data-pregrade-result]');
 const panels = Object.fromEntries(SIDES.map(side => [side, find('[data-photo-side="' + side + '"]')]));
 if (![form, submit, cancel, clear, consent, status, error, result, ...Object.values(panels)].every(Boolean)) return null;
 root.dataset.pregradeReady = 'true';
 const listeners = new AbortController(), photos = {front: null, back: null}, preparing = {front: false, back: false}, photoRevisions = {front: 0, back: 0};
 let revision = 0, request = null, disposed = false;
 const update = () => {
  const loading = preparing.front || preparing.back, busy = request !== null;
  submit.disabled = busy || loading || !photos.front || !photos.back || !consent.checked;
  submit.textContent = busy ? 'Assessing both sides…' : 'Get my pregrade'; submit.setAttribute('aria-busy', String(busy));
  cancel.hidden = !busy; clear.hidden = !loading && !photos.front && !photos.back && !busy;
 };
 const hideError = () => { error.hidden = true; error.textContent = ''; };
 const showError = message => { error.textContent = message; error.hidden = false; status.textContent = ''; };
 const invalidate = () => { revision++; request?.abort(); request = null; result.hidden = true; for (const selector of ['[data-result-title]', '[data-result-range]', '[data-result-summary]', '[data-result-method]', '[data-result-issues]', '[data-result-sides]']) find(selector).replaceChildren(); hideError(); };
 const currentStatus = () => { status.textContent = photos.front && photos.back ? 'Both photos are ready. Confirm the photo permission, then get your pregrade.' : photos.front ? 'Front photo ready. Choose the back of the same card.' : photos.back ? 'Back photo ready. Choose the front of the same card.' : 'Choose the front and back photos to start.'; };
 const resetSide = side => {
  photos[side] = null; preparing[side] = false; photoRevisions[side]++;
  const panel = panels[side]; panel.querySelector('[data-photo-preview]').hidden = true; panel.querySelector('[data-photo-image]').removeAttribute('src'); panel.querySelector('[data-photo-caption]').textContent = ''; panel.querySelector('[data-photo-remove]').hidden = true;
  panel.querySelector('[data-photo-file]').value = ''; panel.querySelector('[data-photo-camera-file]').value = '';
 };
 async function choose(side, file) {
  if (!file || disposed) return;
  invalidate(); resetSide(side); const current = photoRevisions[side]; preparing[side] = true; status.textContent = 'Preparing the ' + side + ' photo…'; update();
  try {
   const photo = await preparePregradePhoto(file);
   if (disposed || current !== photoRevisions[side]) return;
   const opposite = side === 'front' ? 'back' : 'front';
   if (photos[opposite]?.dataUrl === photo.dataUrl) throw new PregradeError('These are the same photo. Choose the front and the back of one card.');
   photos[side] = photo; const panel = panels[side];
   panel.querySelector('[data-photo-image]').src = photo.dataUrl; panel.querySelector('[data-photo-preview]').hidden = false; panel.querySelector('[data-photo-caption]').textContent = photo.width + ' × ' + photo.height + ' · metadata removed'; panel.querySelector('[data-photo-remove]').hidden = false; currentStatus();
  } catch (failure) {
   if (!disposed && current === photoRevisions[side]) showError(failure instanceof PregradeError ? failure.message : 'This photo could not be prepared. Choose another photo.');
  } finally { if (!disposed && current === photoRevisions[side]) { preparing[side] = false; update(); } }
 }
 async function assess(event) {
  event.preventDefault(); if (submit.disabled || disposed) return;
  if (photos.front.dataUrl === photos.back.dataUrl) { showError('Choose the front and the back of one card. The same photo cannot be used twice.'); return; }
  hideError(); result.hidden = true; const current = revision, controller = new AbortController(); request = controller;
  const timeout = setTimeout(() => controller.abort(new PregradeError('This assessment took too long. Try again later.')), 65_000);
  status.textContent = 'Assessing visible condition on both sides. This can take up to a minute…'; update();
  try {
   const response = await waitForAssessment(fetch('/site-api/v1/pregrade', {method: 'POST', credentials: 'same-origin', cache: 'no-store', headers: {'Content-Type': 'application/json'}, signal: controller.signal, body: JSON.stringify({front: photos.front, back: photos.back})}), controller.signal);
   if (!response.ok) throw responseError(response);
   const payload = await readResult(response, controller.signal);
   if (disposed || current !== revision) return;
   if (!validatePregradeResult(payload)) throw new PregradeError('The assessment returned an incomplete result. No grade estimate has been shown. Try again later.');
   renderReport(root, payload); status.textContent = payload.data.status === 'estimated' ? 'Assessment complete. Review both sides and compare the grading costs below.' : 'Review the photo issues below, then replace the photos and try again.';
  } catch (failure) {
   if (!disposed && current === revision && request === controller) showError(failure instanceof PregradeError ? failure.message : controller.signal.reason instanceof PregradeError ? controller.signal.reason.message : 'This assessment could not finish. Check your connection and try again.');
  } finally {
   clearTimeout(timeout); if (request === controller) { request = null; if (!disposed) update(); }
  }
 }
 for (const side of SIDES) {
  const panel = panels[side], camera = panel.querySelector('[data-photo-camera-file]');
  panel.querySelector('[data-photo-file]').addEventListener('change', event => { void choose(side, event.target.files?.[0]); }, {signal: listeners.signal});
  camera.addEventListener('change', event => { void choose(side, event.target.files?.[0]); }, {signal: listeners.signal});
  panel.querySelector('[data-photo-camera]').addEventListener('click', () => camera.click(), {signal: listeners.signal});
  panel.querySelector('[data-photo-remove]').addEventListener('click', () => { invalidate(); resetSide(side); currentStatus(); update(); }, {signal: listeners.signal});
 }
 form.addEventListener('submit', assess, {signal: listeners.signal});
 consent.addEventListener('change', () => { if (!consent.checked && request) { invalidate(); currentStatus(); } update(); }, {signal: listeners.signal});
 cancel.addEventListener('click', () => { invalidate(); status.textContent = 'Assessment cancelled. Your selected photos are still here. You can clear them or try again.'; update(); }, {signal: listeners.signal});
 clear.addEventListener('click', () => { invalidate(); for (const side of SIDES) resetSide(side); consent.checked = false; currentStatus(); update(); }, {signal: listeners.signal});
 const costForm = find('[data-grading-cost-form]');
 costForm?.addEventListener('submit', event => {
  event.preventDefault(); const costError = find('[data-cost-error]'); costError.hidden = true;
  try { renderCost(root, calculateGradingCost(formNumbers(costForm, ['rawValue', 'grade8Value', 'grade9Value', 'grade10Value', 'serviceFee', 'shippingInsurance', 'sellingFeePercent']))); }
  catch (failure) { find('[data-cost-result]').hidden = true; costError.textContent = failure.message; costError.hidden = false; }
 }, {signal: listeners.signal});
 costForm?.addEventListener('input', () => { find('[data-cost-result]').hidden = true; find('[data-cost-error]').hidden = true; }, {signal: listeners.signal});
 const centeringForm = find('[data-centering-form]');
 centeringForm?.addEventListener('submit', event => {
  event.preventDefault(); const output = find('[data-centering-result]');
  try { const borders = calculateBorderRatios(formNumbers(centeringForm, ['left', 'right', 'top', 'bottom'])); output.textContent = 'Left / right: ' + ratio(borders.left) + ' / ' + ratio(borders.right) + '. Top / bottom: ' + ratio(borders.top) + ' / ' + ratio(borders.bottom) + '. From your border measurements.'; }
  catch (failure) { output.textContent = failure.message; }
 }, {signal: listeners.signal});
 centeringForm?.addEventListener('input', () => { find('[data-centering-result]').textContent = ''; }, {signal: listeners.signal});
 const destroy = () => { disposed = true; invalidate(); listeners.abort(); for (const side of SIDES) resetSide(side); root.dataset.pregradeReady = 'false'; };
 window.addEventListener('pagehide', destroy, {once: true, signal: listeners.signal});
 update(); return {destroy};
}

if (typeof document !== 'undefined') for (const root of document.querySelectorAll('[data-web-pregrade]')) initWebPregrade(root);
if (typeof window !== 'undefined') window.addEventListener('pageshow', event => { if (event.persisted) for (const root of document.querySelectorAll('[data-web-pregrade]')) initWebPregrade(root); });
