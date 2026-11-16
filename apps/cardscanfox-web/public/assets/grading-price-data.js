const MAX_BYTES = 262_144;
const MAX_REFERENCES = 200;
const REQUEST_TIMEOUT = 12_000;
const GRADES = [8, 9, 10];
const PRICE_NAMES = ['rawValue', 'grade8Value', 'grade9Value', 'grade10Value'];
const NAMED_GRADERS = new Set(['PSA', 'BGS', 'CGC', 'SGC', 'TAG', 'AGS']);
const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const isText = (value, max = 300) => typeof value === 'string' && value.trim().length > 0 && value.length <= max && !/[\u0000-\u001f]/.test(value);
const optionalText = value => isText(value, 128) ? value.trim() : null;
const knownQualifier = value => isText(value, 128) && !['UNKNOWN', 'NOT LISTED', 'UNSPECIFIED', 'N/A'].includes(value.trim().toUpperCase());
const validId = value => typeof value === 'string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value);
const validSeries = value => typeof value === 'string' && /^\d{1,30}$/.test(value);
const sameDimensions = (left, right) => ['cardId', 'source', 'currency', 'language', 'finish'].every(key => left[key] === right[key]);
export class GradingPriceError extends Error {}

function priceDate(value) {
 if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
 const date = new Date(value + 'T00:00:00Z');
 return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value ? value : null;
}

function cardIdentity(card) {
 if (!isRecord(card) || !validId(card.publicCardId) || !isText(card.name) || !isText(card.set_name) || typeof card.card_number !== 'string' || card.card_number.length > 128) throw new GradingPriceError('The catalog returned an incomplete card record. Try the lookup again.');
 return card.publicCardId;
}

/** Keep every public qualifier. Unknown values can be shown but cannot enable autofill. */
export function groupPriceContexts(card) {
 const cardId = cardIdentity(card);
 if (!Array.isArray(card.references) || card.references.length > MAX_REFERENCES) throw new GradingPriceError('The card returned an incomplete set of price references.');
 const groups = new Map(), seenSeries = new Set();
 for (const ref of card.references) {
  if (!isRecord(ref) || !validSeries(ref.seriesId) || seenSeries.has(ref.seriesId) || !isText(ref.source, 63) || !/^[a-z0-9][a-z0-9_-]{0,62}$/.test(ref.source) || !isText(ref.grader, 64) || ref.amount !== null && !(typeof ref.amount === 'number' && Number.isFinite(ref.amount) && ref.amount >= 0)) throw new GradingPriceError('The catalog returned an invalid price reference. No prices have been filled.');
  seenSeries.add(ref.seriesId);
  const grader = ref.grader.trim().toUpperCase();
  if (grader === 'RAW' && (ref.gradeMin !== null || ref.gradeMax !== null)) throw new GradingPriceError('The raw price reference has an invalid grade context.');
  const grade = ref.gradeMin === ref.gradeMax && GRADES.includes(ref.gradeMin) ? ref.gradeMin : null;
  if (grader !== 'RAW' && grade === null) continue;
  const identity = {cardId, source: ref.source.trim(), currency: typeof ref.currency === 'string' && /^[A-Z]{3}$/.test(ref.currency) ? ref.currency : null, language: optionalText(ref.language), finish: optionalText(ref.finish), grader};
  const key = JSON.stringify(Object.values(identity));
  if (!groups.has(key)) groups.set(key, {...identity, key, sourceLabel: isText(ref.sourceLabel, 128) ? ref.sourceLabel.trim() : identity.source, raw: [], grades: {8: [], 9: [], 10: []}});
  const group = groups.get(key);
  const row = {seriesId: ref.seriesId, amount: ref.amount, date: priceDate(ref.priceAsOf), condition: optionalText(ref.condition), metric: optionalText(ref.metric), available: ref.status === 'available' && ref.amount !== null, grade};
  if (grader === 'RAW') group.raw.push(row); else group.grades[grade].push(row);
 }
 return [...groups.values()].sort((a, b) => Number(a.grader !== 'RAW') - Number(b.grader !== 'RAW') || a.source.localeCompare(b.source) || a.grader.localeCompare(b.grader) || String(a.language).localeCompare(String(b.language)) || String(a.finish).localeCompare(String(b.finish)));
}

function metricFamily(metric, grade) {
 if (!metric) return null;
 return metric.replace(new RegExp('[_-](?:' + grade + '|' + grade * 10 + ')$'), '');
}

function usableRow(row) {
 return row?.available === true && priceDate(row.date) !== null && isText(row.metric, 128) && typeof row.amount === 'number' && row.amount >= 0 && row.amount <= 10_000_000;
}

/** A missing or ambiguous field prevents filling; no company or finish is inferred. */
export function comparablePriceStatus(groups, groupKey) {
 if (!Array.isArray(groups)) return {comparison: null, reason: 'No matching price context is selected.'};
 const group = groups.find(candidate => candidate.key === groupKey);
 if (!group || group.grader === 'RAW') return {comparison: null, reason: 'Choose a graded price context to compare grade 8, 9 and 10.'};
 if (!NAMED_GRADERS.has(group.grader)) return {comparison: null, reason: 'This source does not identify a supported grading company. Shared grade buckets cannot fill company-specific prices.'};
 if (group.currency !== 'USD' || !knownQualifier(group.language) || !knownQualifier(group.finish)) return {comparison: null, reason: 'A matching USD currency, language and finish is needed before prices can fill the cost form.'};
 const graded = {};
 for (const grade of GRADES) {
  const rows = group.grades[grade];
  if (rows.length !== 1 || !usableRow(rows[0])) return {comparison: null, reason: 'A single dated ' + group.grader + ' grade ' + grade + ' price is missing or ambiguous. Keep the cost inputs manual.'};
  graded[grade] = rows[0];
 }
 if (new Set(GRADES.map(grade => metricFamily(graded[grade].metric, grade))).size !== 1) return {comparison: null, reason: 'The grade references use different price metrics. They cannot fill a single comparison.'};
 const raw = groups.filter(candidate => candidate.grader === 'RAW' && sameDimensions(candidate, group)).flatMap(candidate => candidate.raw).filter(row => usableRow(row) && ['NM', 'NEAR MINT'].includes(row.condition?.toUpperCase()));
 if (raw.length !== 1) return {comparison: null, reason: 'A single matching raw Near Mint reference is missing or ambiguous. No raw condition has been assumed.'};
 return {comparison: {...group, raw: raw[0], graded}, reason: 'Matching raw Near Mint and same-company grade 8, 9 and 10 references are available.'};
}

export function selectComparableSet(groups, groupKey) {
 return comparablePriceStatus(groups, groupKey).comparison;
}

function abortable(operation, signal) {
 return new Promise((resolve, reject) => {
  let finished = false;
  const finish = (fn, value) => { if (finished) return; finished = true; signal.removeEventListener('abort', cancel); fn(value); };
  const cancel = () => finish(reject, signal.reason ?? new GradingPriceError('Price lookup cancelled.'));
  Promise.resolve(operation).then(value => finish(resolve, value), error => finish(reject, error));
  if (signal.aborted) cancel(); else signal.addEventListener('abort', cancel, {once: true});
 });
}

async function readPriceJson(response, signal) {
 if (response.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'application/json' || Number(response.headers.get('Content-Length')) > MAX_BYTES || !response.body) throw new GradingPriceError('The price service returned an unreadable response. Try again later.');
 const reader = response.body.getReader(), chunks = []; let size = 0, complete = false;
 try {
  for (;;) {
   const {done, value} = await abortable(reader.read(), signal);
   if (done) { complete = true; break; }
   size += value.byteLength;
   if (size > MAX_BYTES) throw new GradingPriceError('The price response is too large. Try a more specific card.');
   chunks.push(value);
  }
 } finally { if (!complete) void reader.cancel().catch(() => {}); reader.releaseLock(); }
 const bytes = new Uint8Array(size); let offset = 0;
 for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
 try { return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); }
 catch { throw new GradingPriceError('The price service returned an unreadable response. Try again later.'); }
}

export async function fetchGradingPriceData(path, {fetcher = globalThis.fetch, signal, timeoutMs = REQUEST_TIMEOUT} = {}) {
 if (typeof path !== 'string' || !/^\/site-api\/v1\/cards(?:\/[A-Za-z0-9_-]+)?(?:\?[^#]*)?$/.test(path)) throw new GradingPriceError('Use the price lookup on this website.');
 if (signal?.aborted) throw signal.reason ?? new GradingPriceError('Price lookup cancelled.');
 const controller = new AbortController();
 const cancel = () => controller.abort(signal.reason);
 signal?.addEventListener('abort', cancel, {once: true});
 const timer = setTimeout(() => controller.abort(new GradingPriceError('The price lookup took too long. Retry when your connection is ready.')), timeoutMs);
 try {
  const response = await abortable(fetcher(path, {method: 'GET', headers: {Accept: 'application/json'}, credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: controller.signal}), controller.signal);
  if (!response.ok) {
   if (response.status === 400) throw new GradingPriceError('Check the card name or number, then search again.');
   if (response.status === 404) throw new GradingPriceError('This card is not available in the published catalog. Choose another record.');
   if (response.status === 429) { const wait = Number(response.headers.get('Retry-After')); throw new GradingPriceError('Card prices are temporarily busy. ' + (Number.isInteger(wait) && wait > 0 && wait <= 3600 ? 'Wait ' + wait + ' seconds, then retry.' : 'Please wait a minute, then retry.')); }
   throw new GradingPriceError('Card prices are temporarily unavailable. Your manual cost inputs are still available.');
  }
  const payload = await readPriceJson(response, controller.signal);
  if (payload?.success !== true || payload.meta?.datasetMode !== 'published-read-only' || !isRecord(payload.data)) throw new GradingPriceError('Published prices could not be confirmed. No review or estimated prices have been substituted.');
  return payload.data;
 } catch (failure) {
  if (controller.signal.aborted) throw controller.signal.reason;
  throw failure instanceof GradingPriceError ? failure : new GradingPriceError('The price lookup could not finish. Check your connection and retry.');
 } finally { controller.abort(); clearTimeout(timer); signal?.removeEventListener('abort', cancel); }
}

export async function searchPublishedCards(query, options) {
 const q = typeof query === 'string' ? query.trim() : '';
 if (!q || q.length > 128 || /[\u0000-\u001f]/.test(q)) throw new GradingPriceError('Enter a card name, set or collector number of up to 128 characters.');
 const data = await fetchGradingPriceData('/site-api/v1/cards?' + new URLSearchParams({q, pageSize: '6'}), options);
 if (!Array.isArray(data.items) || data.items.length > 6) throw new GradingPriceError('The catalog returned an incomplete search result.');
 for (const card of data.items) cardIdentity(card);
 return data.items;
}

export async function loadPublishedCard(id, options) {
 if (!validId(id)) throw new GradingPriceError('Choose a published card record.');
 const card = await fetchGradingPriceData('/site-api/v1/cards/' + encodeURIComponent(id), options);
 if (cardIdentity(card) !== id) throw new GradingPriceError('The returned card does not match your selection. No prices have been filled.');
 return {card, groups: groupPriceContexts(card)};
}

const make = (tag, className, text) => { const element = document.createElement(tag); if (className) element.className = className; if (text !== undefined) element.textContent = text; return element; };
const cardHref = (id, seriesId) => '/cards/' + encodeURIComponent(id) + (seriesId ? '?series=' + encodeURIComponent(seriesId) : '');
const contextLabel = group => [group.sourceLabel, group.currency ?? 'Currency not listed', group.language ?? 'Language not listed', group.finish ?? 'Finish not listed', ['GENERIC', 'GRADE'].includes(group.grader) ? 'Shared grade bucket · company not supplied' : group.grader === 'RAW' ? 'Raw condition' : group.grader].join(' · ');
const money = (amount, currency) => { if (amount === null || currency === null) return 'Price unavailable'; try { return new Intl.NumberFormat('en-US', {style: 'currency', currency}).format(amount); } catch { return 'Price unavailable'; } };

export function gradingPriceProvenance(card, comparison) {
 cardIdentity(card);
 const printing = [card.name, card.card_number, card.set_name].filter(Boolean).join(' · ');
 return printing + '. ' + contextLabel(comparison) + '. Raw condition: Near Mint, observed ' + comparison.raw.date + '. Grade dates: ' + GRADES.map(grade => grade + ': ' + comparison.graded[grade].date).join('; ') + '. Prices are rounded to USD cents.';
}

export function initGradingPriceLookup(root, {fetcher = globalThis.fetch} = {}) {
 if (root.dataset.gradingPriceReady === 'true') return null;
 root.dataset.gradingPriceReady = 'true';
 const find = selector => root.querySelector(selector), form = find('[data-grading-price-search]'), query = form.querySelector('[name="q"]'), status = find('[data-grading-price-status]'), error = find('[data-grading-price-error]'), retry = find('[data-grading-price-retry]'), cancel = find('[data-grading-price-cancel]'), submit = find('[data-grading-price-submit]'), candidates = find('[data-grading-price-candidates]'), detail = find('[data-grading-price-detail]');
 const pregradeRoot = root.closest('[data-web-pregrade]'), costForm = pregradeRoot?.querySelector('[data-grading-cost-form]');
 const listeners = new AbortController(), imported = new Map();
 let revision = 0, request = null, retryAction = null, disposed = false, applying = false, provenance = null, importedDescription = '';
 const priceInput = name => costForm?.querySelector('[name="' + name + '"]');
 const removeImported = () => {
  applying = true; let cleared = false;
  for (const [name, value] of imported) { const input = priceInput(name); if (input && input.value === value) { input.value = ''; cleared = true; input.dispatchEvent(new Event('input', {bubbles: true})); } }
  if (cleared) { const result = costForm?.closest('[data-web-pregrade]')?.querySelector('[data-cost-result]'); if (result) result.hidden = true; }
  applying = false; imported.clear(); provenance?.remove(); provenance = null; importedDescription = '';
 };
 const idle = () => { submit.disabled = false; cancel.hidden = true; };
 const invalidate = () => { revision++; request?.abort(); request = null; candidates.replaceChildren(); detail.replaceChildren(); removeImported(); error.hidden = true; error.textContent = ''; retry.hidden = true; retryAction = null; idle(); };
 const showFailure = failure => { error.textContent = failure instanceof GradingPriceError ? failure.message : 'The lookup could not finish. Retry the price lookup.'; error.hidden = false; retry.hidden = retryAction === null; status.textContent = ''; };
 function applyPrices(comparison, card) {
  if (!costForm || !PRICE_NAMES.every(name => priceInput(name))) return;
  removeImported(); applying = true;
  const values = {rawValue: comparison.raw.amount, grade8Value: comparison.graded[8].amount, grade9Value: comparison.graded[9].amount, grade10Value: comparison.graded[10].amount};
  for (const [name, amount] of Object.entries(values)) { const input = priceInput(name), value = amount.toFixed(2); input.value = value; imported.set(name, value); input.dispatchEvent(new Event('input', {bubbles: true})); }
  applying = false;
  importedDescription = gradingPriceProvenance(card, comparison);
  provenance = make('p', 'small-note grading-price-provenance', 'Filled price references for ' + importedDescription + ' Enter your service costs, then compare outcomes.');
  provenance.setAttribute('role', 'status'); provenance.setAttribute('aria-live', 'polite'); costForm.prepend(provenance);
  status.textContent = 'The four matching prices are filled in the cost form. Review their context and dates before adding your fees.';
  costForm.dispatchEvent(new CustomEvent('grading-prices-applied', {bubbles: true, detail: {cardId: comparison.cardId, context: contextLabel(comparison)}}));
 }
 function renderCard(card, groups) {
  const renderedRevision = revision;
  const heading = make('h3'), link = make('a', '', card.name + (card.card_number ? ' · ' + card.card_number : '')); link.href = cardHref(card.publicCardId); heading.append(link);
  detail.append(heading, make('p', 'small-note', [card.set_name, card.language, card.finish].filter(Boolean).join(' · ')));
  if (!groups.length) { detail.append(make('p', 'notice', 'No published raw or grade 8, 9 and 10 references are available for this record. Keep the cost inputs manual.')); return; }
  detail.append(make('p', 'small-note', 'Open a price context to inspect its references. Different companies and finishes stay separate. Scroll within a table to see its price date on a small screen.'));
  for (const group of groups) {
   const panel = make('details', 'grading-price-context'), summary = make('summary', '', contextLabel(group)); panel.append(summary); panel.open = group.grader === 'RAW';
   const wrap = make('div', 'price-table-wrap'), table = make('table', 'price-metadata-table'), caption = make('caption', 'sr-only', contextLabel(group)), head = make('thead'), headRow = make('tr'), body = make('tbody');
   wrap.tabIndex = 0; wrap.setAttribute('role', 'region'); wrap.setAttribute('aria-label', 'Price references: ' + contextLabel(group));
   for (const text of ['Grade or condition', 'Published reference', 'Observed']) { const th = make('th', '', text); th.scope = 'col'; headRow.append(th); } head.append(headRow);
   const row = (label, ref) => {
    const tr = make('tr'), th = make('th', '', label); th.scope = 'row'; tr.append(th);
    const value = make('td'), date = make('td', '', ref?.date ?? 'Date not listed');
    if (ref?.available) { const a = make('a', '', money(ref.amount, group.currency)); a.href = cardHref(group.cardId, ref.seriesId); value.append(a); } else value.textContent = 'Price unavailable';
    tr.append(value, date); body.append(tr);
   };
   if (group.grader === 'RAW') for (const ref of group.raw) row('Raw · ' + (ref.condition ?? 'Condition not listed'), ref);
   else for (const grade of GRADES) { const refs = group.grades[grade]; if (!refs.length) row('Grade ' + grade, null); else for (const ref of refs) row('Grade ' + grade, ref); }
   table.append(caption, head, body); wrap.append(table); panel.append(wrap);
   if (group.grader !== 'RAW') {
    const availability = comparablePriceStatus(groups, group.key); panel.append(make('p', 'small-note', availability.reason));
    if (availability.comparison && costForm) { const button = make('button', 'btn btn-outline', 'Fill matching prices in cost form'); button.type = 'button'; button.addEventListener('click', () => { if (!disposed && renderedRevision === revision) applyPrices(availability.comparison, card); }, {signal: listeners.signal}); panel.append(button); }
   }
   detail.append(panel);
  }
 }
 async function run(action) {
  if (disposed) return;
  invalidate(); const current = revision, controller = new AbortController(); request = controller; retryAction = action; submit.disabled = true; cancel.hidden = false;
  status.textContent = action.kind === 'search' ? 'Finding matching published card records…' : 'Loading the selected card’s published price contexts…';
  try {
   const options = {fetcher, signal: controller.signal};
   if (action.kind === 'search') {
    const cards = await searchPublishedCards(action.query, options); if (disposed || current !== revision) return;
    if (!cards.length) { status.textContent = 'No matching published records. Check the name or full number, then search again.'; return; }
    candidates.append(make('h3', '', 'Choose the exact printing.'));
    const list = make('ul', 'grading-price-card-list');
    for (const card of cards) { const item = make('li'), button = make('button', 'btn btn-outline', [card.name, card.card_number, card.set_name, card.language, card.finish].filter(Boolean).join(' · ')); button.type = 'button'; button.addEventListener('click', () => { void run({kind: 'card', id: card.publicCardId}); }, {signal: listeners.signal}); item.append(button); list.append(item); }
    candidates.append(list); status.textContent = (cards.length === 6 ? 'Showing the first six matches. Add a set or full number if your printing is missing. ' : '') + 'Choose a matching printing to see its separate raw and graded references.';
   } else {
    const {card, groups} = await loadPublishedCard(action.id, options); if (disposed || current !== revision) return;
    renderCard(card, groups); status.textContent = 'Published references loaded. Review the source, language, finish, company and price dates.';
   }
  } catch (failure) { if (!disposed && current === revision && !controller.signal.aborted) showFailure(failure); }
  finally { if (request === controller) { request = null; if (!disposed) idle(); } }
 }
 form.addEventListener('submit', event => { event.preventDefault(); if (!submit.disabled) void run({kind: 'search', query: query.value}); }, {signal: listeners.signal});
 query.addEventListener('input', () => { invalidate(); status.textContent = 'Search by name, set or full card number.'; }, {signal: listeners.signal});
 for (const button of root.querySelectorAll('[data-grading-card-id]')) button.addEventListener('click', () => { void run({kind: 'card', id: button.dataset.gradingCardId}); }, {signal: listeners.signal});
 retry.addEventListener('click', () => { if (retryAction) void run(retryAction); }, {signal: listeners.signal});
 cancel.addEventListener('click', () => { invalidate(); status.textContent = 'Price lookup cancelled. You can search again or keep your manual cost inputs.'; }, {signal: listeners.signal});
 costForm?.addEventListener('input', event => { if (!applying && PRICE_NAMES.includes(event.target.name)) { imported.delete(event.target.name); if (provenance) provenance.textContent = imported.size ? 'You edited a price. Review each input. Unedited imported values use these references: ' + importedDescription : 'All price inputs have been edited. They are now your own scenario values.'; } }, {signal: listeners.signal});
 pregradeRoot?.addEventListener('pregrade-photos-changed', () => { invalidate(); status.textContent = 'Photos changed. Choose the matching printing for these photos before filling prices.'; }, {signal: listeners.signal});
 const destroy = () => { disposed = true; invalidate(); listeners.abort(); root.dataset.gradingPriceReady = 'false'; };
 window.addEventListener('pagehide', destroy, {once: true, signal: listeners.signal});
 return {destroy};
}

if (typeof document !== 'undefined') for (const root of document.querySelectorAll('[data-grading-price-lookup]')) initGradingPriceLookup(root);
if (typeof window !== 'undefined') window.addEventListener('pageshow', event => { if (event.persisted) for (const root of document.querySelectorAll('[data-grading-price-lookup]')) initGradingPriceLookup(root); });
