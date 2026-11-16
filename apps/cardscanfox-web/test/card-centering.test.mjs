import assert from 'node:assert/strict';
import test from 'node:test';
import {detectCardCentering, measureFromQuads} from '../public/assets/card-centering.js';

const rectangle = (left, top, right, bottom) => [{x: left, y: top}, {x: right, y: top}, {x: right, y: bottom}, {x: left, y: bottom}];
const outer = rectangle(50, 36, 330, 476);
const inner = rectangle(78, 58, 316, 432); // Borders: 28/14 and 22/44.
const cross = (a, b, p) => (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
const contains = (quad, p) => quad.every((point, index) => cross(point, quad[(index + 1) % 4], p) >= 0);

// These known geometric outlines and artificial colors are measurement fixtures,
// not photographs, physical grading samples, or evidence of a professional grade.
function photograph({outside = outer, inside = inner, noise = 0, fullArt = false, width = 384, height = 512} = {}) {
 const data = new Uint8ClampedArray(width * height * 4);
 let seed = 641;
 const next = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed / 2 ** 32; };
 for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
  const offset = (y * width + x) * 4, p = {x: x + 0.5, y: y + 0.5};
  let color = [24, 31, 40].map(value => value + Math.round((next() * 2 - 1) * noise));
  if (contains(outside, p)) {
   color = [226, 200, 97];
   if (fullArt) color = [(x * 31 + y * 17) % 231 + 20, (x * 13 + y * 29) % 231 + 20, (x * 23 + y * 11) % 231 + 20];
   else if (inside && contains(inside, p)) color = [72, 116, 182];
  }
  data.set([...color, 255], offset);
 }
 return {data, width, height};
}

function expectRatios(result, horizontal, vertical, tolerance = 0) {
 assert.equal(result.status, 'measured', result.reason);
 assert.ok(Math.abs(result.ratios.left - horizontal) <= tolerance, JSON.stringify(result.ratios));
 assert.ok(Math.abs(result.ratios.top - vertical) <= tolerance, JSON.stringify(result.ratios));
 assert.equal(result.ratios.left + result.ratios.right, 100);
 assert.equal(result.ratios.top + result.ratios.bottom, 100);
}

test('confirmed outlines preserve a real non-50/50 offset and report all four pixel widths', () => {
 const result = measureFromQuads(outer, inner);
 expectRatios(result, 67, 33);
 assert.deepEqual(result.borders, {left: 28, right: 14, top: 22, bottom: 44});
 assert.deepEqual(result.dimensions, {width: 280, height: 440});
 assert.deepEqual(result.outerQuad, outer); assert.deepEqual(result.innerQuad, inner);
 assert.equal(result.uncertainty, null);
});

test('confirmed perspective outlines use the card plane rather than raw photograph widths', () => {
 const project = point => {
  const denominator = 1 + 0.00025 * point.x + 0.00005 * point.y;
  return {x: (0.98 * point.x + 0.04 * point.y + 20) / denominator, y: (0.035 * point.x + 0.96 * point.y + 14) / denominator};
 };
 const result = measureFromQuads(outer.map(project), inner.map(project));
 expectRatios(result, 67, 33);
 const rawRatio = ((result.innerQuad[0].x + result.innerQuad[3].x) / 2 - (result.outerQuad[0].x + result.outerQuad[3].x) / 2) /
  (((result.innerQuad[0].x + result.innerQuad[3].x) / 2 - (result.outerQuad[0].x + result.outerQuad[3].x) / 2) +
   ((result.outerQuad[1].x + result.outerQuad[2].x) / 2 - (result.innerQuad[1].x + result.innerQuad[2].x) / 2)) * 100;
 assert.ok(Math.abs(rawRatio - 66.6666666667) > 0.5, 'This fixture must expose the raw-image perspective bias.');
});

test('automatic measurement detects known offset borders instead of returning a default center', () => {
 const result = detectCardCentering(photograph());
 expectRatios(result, 67, 33, 3);
 assert.equal(result.outerQuad.length, 4); assert.equal(result.innerQuad.length, 4);
 assert.ok(result.borders.left > result.borders.right); assert.ok(result.borders.bottom > result.borders.top);
 assert.ok(result.uncertainty.leftRight > 0); assert.ok(result.uncertainty.topBottom > 0);
 assert.match(result.uncertainty.basis, /not calibrated accuracy/);
});

test('minor background noise does not turn a known offset into 50/50', () => {
 const result = detectCardCentering(photograph({noise: 8}));
 expectRatios(result, 67, 33, 3);
});

test('automatic measurement corrects a mildly tilted, projective card outline', () => {
 const project = point => {
  const denominator = 1 + 0.00025 * point.x + 0.00005 * point.y;
  return {x: (0.98 * point.x + 0.04 * point.y + 20) / denominator, y: (0.035 * point.x + 0.96 * point.y + 14) / denominator};
 };
 const result = detectCardCentering(photograph({outside: outer.map(project), inside: inner.map(project)}));
 expectRatios(result, 67, 33, 4);
});

test('a cropped outer card edge is rejected rather than treated as the photo boundary', () => {
 const result = detectCardCentering(photograph({outside: rectangle(-8, 36, 280, 476), inside: rectangle(20, 58, 266, 432)}));
 assert.equal(result.status, 'unavailable'); assert.equal(result.ratios, null); assert.equal(result.borders, null);
 assert.equal(result.dimensions, null);assert.equal(result.innerQuad, null);assert.ok(result.reason.length>10);
});

test('full-art pixels without one continuous printed frame do not get invented ratios', () => {
 const result = detectCardCentering(photograph({fullArt: true}));
 assert.equal(result.status, 'unavailable'); assert.equal(result.innerQuad, null); assert.equal(result.ratios, null);
 assert.match(result.reason, /printed frame|printed border/);
});

test('a featureless card cannot produce a 50/50 fallback', () => {
 const result = detectCardCentering(photograph({inside: null}));
 assert.equal(result.status, 'unavailable'); assert.equal(result.ratios, null);
});

test('a busy image perimeter requests a plain background', () => {
 const image = photograph({noise: 110});
 const result = detectCardCentering(image);
 assert.equal(result.status, 'unavailable'); assert.equal(result.ratios, null); assert.match(result.reason, /plain background/);
});

test('severe perspective or an unstable outer shape is rejected before any numeric result', () => {
 const result = detectCardCentering(photograph({outside: [{x: 30, y: 30}, {x: 340, y: 150}, {x: 260, y: 480}, {x: 80, y: 480}], inside: null}));
 assert.equal(result.status, 'unavailable'); assert.equal(result.ratios, null);
});

test('invalid pixels and invalid or crossing outlines fail explicitly', () => {
 for (const image of [undefined, {}, {width: 100, height: 100, data: new Uint8ClampedArray(40_000)}, {width: 300, height: 400, data: []}, {width: 300, height: 400, data: new Uint8ClampedArray(30)}, {width: 4000, height: 4000, data: new Uint8ClampedArray(0)}]) {
  const result = detectCardCentering(image); assert.equal(result.status, 'unavailable'); assert.equal(result.ratios, null);
 }
 for (const [outside, inside] of [[outer.slice(0, 3), inner], [[outer[0], outer[2], outer[1], outer[3]], inner], [outer, rectangle(10, 58, 316, 432)], [outer, rectangle(50, 58, 316, 432)], [outer, [{x: NaN, y: 50}, ...inner.slice(1)]]]) {
  const result = measureFromQuads(outside, inside); assert.equal(result.status, 'unavailable'); assert.equal(result.ratios, null);
 }
});
