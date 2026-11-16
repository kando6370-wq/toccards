import assert from 'node:assert/strict';
import test from 'node:test';
import {parse} from 'parse5';
import {renderGradingPriceLookup} from '../src/grading-price-template.mjs';
import {groupPriceContexts, comparablePriceStatus, selectComparableSet, gradingPriceProvenance, fetchGradingPriceData, searchPublishedCards, loadPublishedCard, initGradingPriceLookup, GradingPriceError} from '../public/assets/grading-price-data.js';

// Contract fixtures only. These are not real market prices or certified samples.
const reference = (overrides = {}) => ({seriesId: '100', source: 'published-source', sourceLabel: 'Published source', metric: 'market', currency: 'USD', language: 'English', finish: 'Holofoil', grader: 'RAW', gradeMin: null, gradeMax: null, condition: 'Near Mint', amount: 100, priceAsOf: '2026-11-16', status: 'available', ...overrides});
const graded = (grade, overrides = {}) => reference({seriesId: String(100 + grade), grader: 'PSA', gradeMin: grade, gradeMax: grade, condition: null, amount: grade * 100, metric: 'psa_' + grade * 10, ...overrides});
const card = (references = [reference(), ...[8, 9, 10].map(grade => graded(grade))], overrides = {}) => ({publicCardId: 'fixture-1', name: 'Fixture Pokémon', set_name: 'Fixture set', card_number: '001/100', language: 'English', finish: 'Holofoil', references, ...overrides});
const named = groups => groups.find(group => group.grader === 'PSA');
const envelope = (data, mode = 'published-read-only') => Response.json({success: true, data, meta: {datasetMode: mode}});

test('a comparison keeps one printing, source, language, finish and company with an explicit raw condition', () => {
 const groups = groupPriceContexts(card()), comparison = selectComparableSet(groups, named(groups).key);
 assert.equal(groups.length, 2); assert.equal(comparison.cardId, 'fixture-1'); assert.equal(comparison.grader, 'PSA');
 assert.equal(comparison.raw.condition, 'Near Mint'); assert.equal(comparison.raw.amount, 100);
 assert.deepEqual([8, 9, 10].map(grade => comparison.graded[grade].amount), [800, 900, 1000]);
 assert.deepEqual([8, 9, 10].map(grade => comparison.graded[grade].seriesId), ['108', '109', '110']);
 assert.ok(comparison.graded[8].date); assert.match(comparablePriceStatus(groups, comparison.key).reason, /same-company/);
});

test('imported price provenance identifies the exact card, printing, company and observation dates', () => {
 const selected = card(), groups = groupPriceContexts(selected), comparison = selectComparableSet(groups, named(groups).key);
 const provenance = gradingPriceProvenance(selected, comparison);
 for (const value of ['Fixture Pokémon', '001/100', 'Fixture set', 'Published source', 'PSA', 'English', 'Holofoil', 'Near Mint', '8: 2026-11-16', '9: 2026-11-16', '10: 2026-11-16']) assert.ok(provenance.includes(value), value);
});

test('shared grade 8 and 9 never become PSA grades or complete a PSA 10 comparison', () => {
 const groups = groupPriceContexts(card([reference(), graded(8, {grader: 'GENERIC', metric: 'grade_80'}), graded(9, {grader: 'GENERIC', metric: 'grade_90'}), graded(10)]));
 assert.equal(groups.length, 3);
 const shared = groups.find(group => group.grader === 'GENERIC');
 assert.equal(shared.grades[8][0].amount, 800); assert.equal(shared.grades[9][0].amount, 900);
 assert.equal(selectComparableSet(groups, shared.key), null); assert.equal(selectComparableSet(groups, named(groups).key), null);
 assert.match(comparablePriceStatus(groups, shared.key).reason, /Shared grade buckets/);
});

test('multiple raw contexts stay first in a stable source order', () => {
 const groups = groupPriceContexts(card([reference({source: 'z-source'}), reference({seriesId: '200', source: 'a-source'}), graded(10, {source: 'a-source'})]));
 assert.deepEqual(groups.map(group => [group.grader, group.source]), [['RAW', 'a-source'], ['RAW', 'z-source'], ['PSA', 'a-source']]);
});

test('missing, unknown or different raw dimensions prevent autofill without assuming Near Mint', () => {
 for (const overrides of [{condition: null}, {condition: 'Lightly Played'}, {source: 'other-source'}, {currency: 'EUR'}, {language: 'Japanese'}, {finish: 'Normal'}, {amount: null}, {priceAsOf: null}, {priceAsOf: '2026-02-30'}]) {
  const groups = groupPriceContexts(card([reference(overrides), ...[8, 9, 10].map(grade => graded(grade))]));
  assert.equal(selectComparableSet(groups, named(groups).key), null, JSON.stringify(overrides));
 }
 for (const qualifier of [null, 'Unknown', 'Not listed', 'Unspecified']) {
  const groups = groupPriceContexts(card([reference({finish: qualifier}), ...[8, 9, 10].map(grade => graded(grade, {finish: qualifier}))]));
  assert.equal(selectComparableSet(groups, named(groups).key), null);
 }
});

test('different companies, card identities and grade ranges remain separate', () => {
 for (const replacement of [graded(9, {grader: 'BGS'}), graded(9, {gradeMin: 8.5, gradeMax: 9}), graded(9, {language: 'Japanese'}), graded(9, {finish: 'Reverse Holofoil'})]) {
  const groups = groupPriceContexts(card([reference(), graded(8), replacement, graded(10)]));
  assert.equal(selectComparableSet(groups, named(groups).key), null);
 }
 const first = groupPriceContexts(card([graded(8), graded(9), graded(10)]));
 const other = groupPriceContexts(card([reference()], {publicCardId: 'another-card'}));
 assert.equal(selectComparableSet([...first, ...other], named(first).key), null);
});

test('ambiguous records and incompatible price metrics do not select the highest or newest number', () => {
 for (const refs of [
  [reference(), ...[8, 9, 10].map(grade => graded(grade)), graded(9, {seriesId: '999', amount: 9000})],
  [reference(), reference({seriesId: '998', amount: 90}), ...[8, 9, 10].map(grade => graded(grade))],
  [reference(), graded(8), graded(9, {metric: 'asking_price'}), graded(10)],
 ]) {
  const groups = groupPriceContexts(card(refs)); assert.equal(selectComparableSet(groups, named(groups).key), null);
 }
});

test('zero is a valid published amount; missing amounts and dates stay explicit', () => {
 const groups = groupPriceContexts(card([reference({amount: 0}), graded(8, {amount: 0}), graded(9), graded(10)]));
 const comparison = selectComparableSet(groups, named(groups).key); assert.equal(comparison.raw.amount, 0); assert.equal(comparison.graded[8].amount, 0);
 const missing = groupPriceContexts(card([reference(), graded(8, {amount: null, priceAsOf: null}), graded(9), graded(10)]));
 assert.equal(named(missing).grades[8][0].amount, null); assert.equal(named(missing).grades[8][0].date, null); assert.equal(selectComparableSet(missing, named(missing).key), null);
});

test('oversized or malformed references cannot be shown as a valid comparison', () => {
 for (const value of [card(Array.from({length: 201}, () => reference())), card([reference({amount: -1})]), card([reference({amount: Infinity})]), card([reference({seriesId: 'not-a-series'})]), card([reference({gradeMin: 8, gradeMax: 8})]), card([reference(), reference()])]) assert.throws(() => groupPriceContexts(value), GradingPriceError);
 const groups = groupPriceContexts(card([reference(), graded(8, {amount: 10_000_001}), graded(9), graded(10)]));
 assert.equal(selectComparableSet(groups, named(groups).key), null);
});

test('search requests only six public records and details validate the selected identity', async () => {
 const calls = [], row = card([]);
 const items = await searchPublishedCards('  Charizard 199/165  ', {fetcher: async (path, options) => { calls.push({path, options}); return envelope({items: [row]}); }});
 const url = new URL(calls[0].path, 'https://tcgcard.fun'); assert.equal(url.pathname, '/site-api/v1/cards'); assert.equal(url.searchParams.get('pageSize'), '6'); assert.equal(url.searchParams.get('q'), 'Charizard 199/165');
 assert.equal(calls[0].options.cache, 'no-store'); assert.equal(calls[0].options.credentials, 'same-origin'); assert.equal(calls[0].options.method, 'GET'); assert.equal(items[0].publicCardId, 'fixture-1');
 const loaded = await loadPublishedCard('fixture-1', {fetcher: async () => envelope(card())}); assert.equal(loaded.groups.length, 2);
 await assert.rejects(loadPublishedCard('another-card', {fetcher: async () => envelope(card())}), /does not match/);
 await assert.rejects(searchPublishedCards(' ', {fetcher: async () => { throw Error('must not fetch'); }}), /Enter a card name/);
});

test('review data, bad lists and unsafe paths are refused instead of becoming live prices', async () => {
 await assert.rejects(searchPublishedCards('card', {fetcher: async () => envelope({items: [card()]}, 'snapshot')}), /Published prices could not be confirmed/);
 await assert.rejects(searchPublishedCards('card', {fetcher: async () => envelope({items: Array.from({length: 7}, () => card())})}), /incomplete search result/);
 await assert.rejects(fetchGradingPriceData('https://other.example/cards', {fetcher: async () => { throw Error('must not fetch'); }}), /this website/);
 await assert.rejects(fetchGradingPriceData('//other.example/cards'), /this website/);
 await assert.rejects(loadPublishedCard('../private'), /Choose a published card/);
});

test('service errors give a bounded retry message without substituting old prices', async () => {
 const cases = [[400, /Check the card name/], [404, /not available/], [429, /Wait 60 seconds/], [503, /temporarily unavailable/]];
 for (const [status, expected] of cases) await assert.rejects(searchPublishedCards('card', {fetcher: async () => new Response('', {status, headers: {'Retry-After': '60'}})}), expected);
 await assert.rejects(searchPublishedCards('card', {fetcher: async () => new Response('<html>not JSON</html>', {headers: {'Content-Type': 'text/html'}})}), /unreadable response/);
 await assert.rejects(searchPublishedCards('card', {fetcher: async () => new Response('{', {headers: {'Content-Type': 'application/json'}})}), /unreadable response/);
});

test('a response cannot bypass the size limit by omitting Content-Length', async () => {
 let cancelled = false;
 const stream = new ReadableStream({pull(controller) { controller.enqueue(new Uint8Array(262_145)); }, cancel() { cancelled = true; }});
 await assert.rejects(fetchGradingPriceData('/site-api/v1/cards/fixture-1', {fetcher: async () => new Response(stream, {headers: {'Content-Type': 'application/json'}})}), /too large/);
 assert.equal(cancelled, true);
});

test('cancellation and timeout stop a pending fetch even when the transport ignores the signal', async () => {
 const controller = new AbortController(); let late;
 const pending = fetchGradingPriceData('/site-api/v1/cards/fixture-1', {signal: controller.signal, fetcher: () => new Promise(resolve => { late = resolve; })});
 controller.abort(new GradingPriceError('cancelled for a new card')); await assert.rejects(pending, /cancelled for a new card/); late(envelope(card()));
 await assert.rejects(fetchGradingPriceData('/site-api/v1/cards/fixture-1', {timeoutMs: 5, fetcher: () => new Promise(() => {})}), /took too long/);
 const already = new AbortController(); already.abort(new GradingPriceError('already cancelled'));
 await assert.rejects(fetchGradingPriceData('/site-api/v1/cards/fixture-1', {signal: already.signal, fetcher: () => { throw Error('must not fetch'); }}), /already cancelled/);
});

test('a hanging response body is bounded by the same request deadline', async () => {
 let cancelled = false;
 const response = new Response(new ReadableStream({cancel() { cancelled = true; }}), {headers: {'Content-Type': 'application/json'}});
 await assert.rejects(fetchGradingPriceData('/site-api/v1/cards/fixture-1', {timeoutMs: 5, fetcher: async () => response}), /took too long/);
 assert.equal(cancelled, true);
});

test('SSR provides a labelled lookup and a text fallback before any prices are requested', () => {
 const doc = parse(renderGradingPriceLookup()), nodes = [];
 const visit = node => { nodes.push(node); for (const child of node.childNodes ?? []) visit(child); }; visit(doc);
 const attr = (node, key) => node.attrs?.find(value => value.name === key)?.value;
 assert.equal(nodes.filter(node => node.tagName === 'form' && attr(node, 'role') === 'search').length, 1);
 assert.ok(nodes.some(node => node.tagName === 'label' && attr(node, 'for') === 'grading-price-query'));
 assert.ok(nodes.some(node => node.tagName === 'input' && attr(node, 'maxlength') === '128'));
 assert.ok(nodes.some(node => node.tagName === 'noscript'));
 assert.ok(nodes.some(node => node.tagName === 'script' && attr(node, 'src') === '/assets/grading-price-data.js'));
});

// Minimal DOM events for the cross-tool invalidation contract. No model or real
// market result is simulated here; the prices remain the contract fixtures above.
class Field extends EventTarget {
 constructor(tag = 'div') { super(); this.tagName = tag; this.children = []; this.dataset = {}; this.value = ''; this.hidden = false; this.parentElement = null; this.selectors = new Map(); }
 addEventListener(type, handler) { super.addEventListener(type, handler); }
 append(...nodes) { for (const child of nodes) { child.parentElement = this; this.children.push(child); } }
 prepend(child) { child.parentElement = this; this.children.unshift(child); }
 replaceChildren(...nodes) { for (const child of this.children) child.parentElement = null; this.children = []; this.append(...nodes); }
 remove() { if (this.parentElement) this.parentElement.children = this.parentElement.children.filter(child => child !== this); this.parentElement = null; }
 setAttribute() {}
 querySelector(selector) { return this.selectors.get(selector) ?? null; }
 querySelectorAll(selector) { return this.selectors.get(selector) ?? []; }
 closest() { return this.owner; }
 dispatchEvent(event) { if (!Object.hasOwn(event, 'target')) Object.defineProperty(event, 'target', {value: this}); const result = super.dispatchEvent(event); if (event.bubbles && this.parentElement) this.parentElement.dispatchEvent(event); return result; }
}

function priceView() {
 const root = new Field(), owner = new Field(), form = new Field('form'), query = new Field('input'), costForm = new Field('form'), costResult = new Field();
 root.owner = owner; costForm.owner = owner; owner.selectors.set('[data-grading-cost-form]', costForm); owner.selectors.set('[data-cost-result]', costResult);
 root.selectors.set('[data-grading-price-search]', form); form.selectors.set('[name="q"]', query);
 for (const selector of ['status', 'error', 'retry', 'cancel', 'submit', 'candidates', 'detail']) root.selectors.set('[data-grading-price-' + selector + ']', new Field());
 const example = new Field('button'); example.dataset.gradingCardId = 'fixture-1'; root.selectors.set('[data-grading-card-id]', [example]);
 const inputs = {};
 for (const name of ['rawValue', 'grade8Value', 'grade9Value', 'grade10Value']) { const input = new Field('input'); input.name = name; input.parentElement = costForm; inputs[name] = input; costForm.selectors.set('[name="' + name + '"]', input); }
 return {root, owner, costForm, costResult, inputs, example, detail: root.querySelector('[data-grading-price-detail]'), status: root.querySelector('[data-grading-price-status]')};
}

const descendant = (node, predicate) => predicate(node) ? node : node.children?.map(child => descendant(child, predicate)).find(Boolean);
async function settleUntil(predicate) { for (let i = 0; i < 10; i++) { if (predicate()) return; await new Promise(resolve => setImmediate(resolve)); } assert.ok(predicate(), 'The price view did not reach its expected state.'); }

test('changing a photo clears imported prices and stale ROI while keeping a user-edited value', async () => {
 const previousDocument = globalThis.document, previousWindow = globalThis.window;
 globalThis.document = {createElement: tag => new Field(tag)}; globalThis.window = new EventTarget();
 const view = priceView(); let handle;
 try {
  handle = initGradingPriceLookup(view.root, {fetcher: async () => envelope(card())}); view.example.dispatchEvent(new Event('click'));
  await settleUntil(() => descendant(view.detail, node => node.textContent === 'Fill matching prices in cost form'));
  const fill = descendant(view.detail, node => node.textContent === 'Fill matching prices in cost form'); fill.dispatchEvent(new Event('click'));
  assert.deepEqual(Object.fromEntries(Object.entries(view.inputs).map(([name, input]) => [name, input.value])), {rawValue: '100.00', grade8Value: '800.00', grade9Value: '900.00', grade10Value: '1000.00'});
  assert.match(view.costForm.children[0].textContent, /Fixture Pokémon.*001\/100.*Fixture set/);
  view.inputs.grade8Value.value = '777'; view.inputs.grade8Value.dispatchEvent(new Event('input', {bubbles: true}));
  assert.match(view.costForm.children[0].textContent, /Published source.*PSA/); view.costResult.hidden = false;
  view.owner.dispatchEvent(new Event('pregrade-photos-changed'));
  assert.equal(view.inputs.rawValue.value, ''); assert.equal(view.inputs.grade9Value.value, ''); assert.equal(view.inputs.grade10Value.value, ''); assert.equal(view.inputs.grade8Value.value, '777');
  assert.equal(view.costResult.hidden, true); assert.equal(view.costForm.children.length, 0); assert.equal(view.detail.children.length, 0); assert.match(view.status.textContent, /Photos changed/);
  fill.dispatchEvent(new Event('click')); assert.equal(view.inputs.rawValue.value, ''); assert.equal(view.inputs.grade8Value.value, '777');
 } finally { handle?.destroy(); if (previousDocument === undefined) delete globalThis.document; else globalThis.document = previousDocument; if (previousWindow === undefined) delete globalThis.window; else globalThis.window = previousWindow; }
});

test('a photo change ignores a detail response that arrives after the selection was invalidated', async () => {
 const previousDocument = globalThis.document, previousWindow = globalThis.window;
 globalThis.document = {createElement: tag => new Field(tag)}; globalThis.window = new EventTarget();
 const view = priceView(); let handle, finish;
 try {
  handle = initGradingPriceLookup(view.root, {fetcher: () => new Promise(resolve => { finish = resolve; })}); view.example.dispatchEvent(new Event('click'));
  view.owner.dispatchEvent(new Event('pregrade-photos-changed')); finish(envelope(card())); await new Promise(resolve => setImmediate(resolve));
  assert.equal(view.detail.children.length, 0); assert.match(view.status.textContent, /Photos changed/); assert.equal(view.inputs.rawValue.value, '');
 } finally { handle?.destroy(); if (previousDocument === undefined) delete globalThis.document; else globalThis.document = previousDocument; if (previousWindow === undefined) delete globalThis.window; else globalThis.window = previousWindow; }
});
