import assert from 'node:assert/strict';
import test from 'node:test';
import {calculateBorderRatios, calculateGradingCost, normalizedPhotoSize, validatePregradePhoto, validatePregradeResult, waitForAssessment} from '../public/assets/web-pregrade.js';
import {renderPregradePage} from '../src/pregrade-template.mjs';

const criterion = () => ({severity: 'none_visible', observation: 'No edge wear is visible in this photo.'});
const side = () => ({quality: 'good', issues: [], ...Object.fromEntries(['centering', 'corners', 'edges', 'surface', 'print'].map(name => [name, criterion()]))});
const payload = () => ({success: true, data: {status: 'estimated', range: {low: 8, high: 10}, summary: 'A photo-based range, not a professional grade.', issues: [], front: side(), back: side()}, meta: {method: 'photo-pregrade-v1', model: 'vision-model', assessedAt: '2026-11-16T08:00:00.000Z'}});

test('grading economics compare both net sale options and the complete entered service costs', () => {
 const result = calculateGradingCost({rawValue: 100, grade8Value: 110, grade9Value: 160, grade10Value: 300, serviceFee: 40, shippingInsurance: 20, sellingFeePercent: 10});
 assert.equal(result.rawNet, 90); assert.equal(result.cost, 60);
 assert.deepEqual(result.outcomes.map(outcome => outcome.netAfterGrading), [39, 84, 210]);
 assert.deepEqual(result.outcomes.map(outcome => outcome.difference), [-51, -6, 120]);
 assert.ok(Math.abs(result.breakEven - 166.6666666667) < 0.0001);
 const atBreakEven = calculateGradingCost({rawValue: 100, grade8Value: result.breakEven, grade9Value: result.breakEven, grade10Value: result.breakEven, serviceFee: 40, shippingInsurance: 20, sellingFeePercent: 10});
 assert.ok(atBreakEven.outcomes.every(outcome => Math.abs(outcome.difference) < 0.00001));
});

test('zero values are accepted but missing values, negatives and impossible fee rates do not become profit', () => {
 const values = {rawValue: 0, grade8Value: 0, grade9Value: 0, grade10Value: 0, serviceFee: 0, shippingInsurance: 0, sellingFeePercent: 0};
 const result = calculateGradingCost(values); assert.equal(result.breakEven, 0); assert.equal(result.outcomes[0].difference, 0);
 for (const invalid of [{...values, rawValue: undefined}, {...values, serviceFee: -1}, {...values, grade9Value: Infinity}, {...values, sellingFeePercent: 100}, {...values, rawValue: '100'}, {...values, rawValue: 10_000_001}]) assert.throws(() => calculateGradingCost(invalid));
});

test('border ratios come only from explicit border measurements, preserving each direction', () => {
 const measured = calculateBorderRatios({left: 55, right: 45, top: 40, bottom: 60});
 assert.ok(Math.abs(measured.left - 55) < 0.000001); assert.ok(Math.abs(measured.right - 45) < 0.000001); assert.equal(measured.top, 40); assert.equal(measured.bottom, 60);
 assert.deepEqual(calculateBorderRatios({left: 0, right: 20, top: 8, bottom: 8}), {left: 0, right: 100, top: 50, bottom: 50});
 for (const invalid of [{left: 0, right: 0, top: 1, bottom: 1}, {left: -1, right: 10, top: 1, bottom: 1}, {left: 1, right: 1, top: NaN, bottom: 1}]) assert.throws(() => calculateBorderRatios(invalid));
});

test('photos keep useful resolution without upscaling or sending unbounded originals', () => {
 assert.deepEqual(normalizedPhotoSize(1200, 1800), {width: 1067, height: 1600});
 assert.deepEqual(normalizedPhotoSize(640, 900), {width: 640, height: 900});
 for (const size of [[300, 500], [2000, 10_000], [6000, 5000], [Infinity, 900], [0, 0]]) assert.throws(() => normalizedPhotoSize(...size));
 assert.doesNotThrow(() => validatePregradePhoto({type: 'image/jpeg', size: 20 * 1024 * 1024}));
 for (const file of [{type: 'image/heic', size: 1000}, {type: 'image/jpeg', size: 0}, {type: 'image/png', size: 20 * 1024 * 1024 + 1}]) assert.throws(() => validatePregradePhoto(file));
});

test('photo limitations cannot be displayed alongside a numeric pregrade', () => {
 assert.equal(validatePregradeResult(payload()), true);
 const limited = payload(); limited.data.back.quality = 'limited'; assert.equal(validatePregradeResult(limited), false);
 const hidden = payload(); hidden.data.front.surface.severity = 'unassessable'; assert.equal(validatePregradeResult(hidden), false);
 hidden.data.status = 'needs_better_photos'; hidden.data.range = null; hidden.data.issues = ['Surface detail cannot be assessed.']; assert.equal(validatePregradeResult(hidden), true);
 for (const mutate of [value => { value.data.range.high = 11; }, value => { value.data.range.low = 10; value.data.range.high = 8; }, value => { value.data.front.edges.observation = ''; }, value => { value.meta.assessedAt = 'not a date'; }, value => { value.data.issues = '<script>'; }]) { const value = payload(); mutate(value); assert.equal(validatePregradeResult(value), false); }
});

test('cancelling an assessment releases its wait even when a service operation does not settle', async () => {
 const controller = new AbortController(), operation = new Promise(() => {}), waiting = waitForAssessment(operation, controller.signal);
 controller.abort(new Error('Cancelled by replacement photo'));
 await assert.rejects(waiting, /Cancelled by replacement photo/);
 assert.equal(await waitForAssessment(Promise.resolve('complete'), new AbortController().signal), 'complete');
});

test('the server-rendered page includes the real task, explicit photo permission and answer content', () => {
 const html = renderPregradePage();
 assert.match(html, /<h1>AI card grading/); assert.match(html, /data-photo-side="front"/); assert.match(html, /data-photo-side="back"/);
 assert.match(html, /data-pregrade-consent/); assert.match(html, /Cloudflare AI/); assert.match(html, /data-grading-cost-form/); assert.match(html, /data-centering-form/);
 assert.match(html, /PSA grading standards/); assert.match(html, /39\.99/); assert.match(html, /16 November 2026/); assert.match(html, /90–100 business-day/);
 assert.doesNotMatch(html, /pregrade-examples-title/); assert.match(html, /<noscript>/);
 const front = html.indexOf('data-photo-side="front"'), guide = html.indexOf('id="pregrade-standards-title"'); assert.ok(front > 0 && front < guide);
});

test('example output escapes source text and does not show incomplete or unsafe photo pairs', () => {
 const example = {title: '<script>card</script>', frontImage: '/assets/cards/front.jpg', backImage: '/assets/cards/back.jpg', result: 'Photo range 6–9', reason: 'Visible wear', sourceUrl: 'https://example.com/card', sourceLabel: 'Photo source'};
 assert.match(renderPregradePage({examples: [example]}), /&lt;script&gt;card&lt;\/script&gt;/);
 assert.doesNotMatch(renderPregradePage({examples: [{...example, backImage: ''}]}), /pregrade-examples-title/);
 assert.doesNotMatch(renderPregradePage({examples: [{...example, sourceUrl: 'javascript:alert(1)'}]}), /pregrade-examples-title/);
});

test('single catalog images stay separate from real physical pregrade examples', () => {
 const example = {kind: 'catalog_reference', name: 'Charizard', imageUrl: 'https://image.tcgcard.fun/cards/714372.jpg', imageKind: 'catalog_front', pregradeResult: null, href: '/cards/714372', priceHref: '/cards/714372?series=42', setName: '30th Celebration Classic Collection', number: '4/102', language: 'English', finish: 'Holofoil', price: {amount: 109.63, currency: 'USD', grader: 'RAW', condition: 'Near Mint', sourceLabel: 'TCGplayer', priceAsOf: '2026-11-15'}, checkedAt: '2026-11-16T08:00:00.000Z', gradeComparison: {available: false}};
 const html = renderPregradePage({catalogExamples: [example]});
 assert.match(html, /pregrade-catalog-title/); assert.match(html, /not photos of graded physical samples/); assert.match(html, /\/cards\/714372\?series=42/);
 assert.match(html, /109\.63/); assert.match(html, /Near Mint/); assert.match(html, /TCGplayer/); assert.match(html, /Grade 8, 9 and 10 price comparison is unavailable/); assert.doesNotMatch(html, /pregrade-examples-title/);
 assert.doesNotMatch(renderPregradePage({catalogExamples: [{...example, href: 'https://example.com/cards/714372'}]}), /pregrade-catalog-title/);
});

test('automatic geometry and local state are excluded from the photo upload request',async()=>{
 const {pregradeUploadPayload}=await import('../public/assets/web-pregrade.js');
 const source={dataUrl:'data:image/jpeg;base64,AA==',width:700,height:1000,measurement:{ratios:{left:45,right:55}},privatePixels:new Uint8Array(16)};
 assert.deepEqual(pregradeUploadPayload({front:source,back:{...source,width:800}}),{front:{dataUrl:source.dataUrl,width:700,height:1000},back:{dataUrl:source.dataUrl,width:800,height:1000}});
 assert.ok(source.measurement);
});
