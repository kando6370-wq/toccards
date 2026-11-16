const MAX_PIXELS = 4_000_000;
const MAX_DETECTION_SIDE = 960;
const SCAN_COUNT = 31;

const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const cross = (a, b, c) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
const roundPixel = value => Math.round(value * 10) / 10;
const median = values => {
 const sorted = [...values].sort((a, b) => a - b);
 const middle = sorted.length >> 1;
 return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};
const colorDistance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]) / Math.sqrt(3);
const copyQuad = quad => quad.map(point => ({x: point.x, y: point.y}));
const unavailable = (reason, outerQuad = null) => ({status: 'unavailable', reason, outerQuad, innerQuad: null, borders: null, ratios: null, dimensions: null, uncertainty: null});

function validQuad(quad) {
 return Array.isArray(quad) && quad.length === 4 && quad.every(point => point && Number.isFinite(point.x) && Number.isFinite(point.y) && point.x >= 0 && point.y >= 0 && point.x <= 100_000 && point.y <= 100_000) &&
  quad.every((point, index) => cross(point, quad[(index + 1) % 4], quad[(index + 2) % 4]) > 0.01);
}

// Map the unit square to a TL, TR, BR, BL quadrilateral. This is a projective
// transform, so a tilted photograph does not become a raw-image border ratio.
function squareTransform(quad) {
 const [a, b, c, d] = quad;
 const dx1 = b.x - c.x, dx2 = d.x - c.x, dx3 = a.x - b.x + c.x - d.x;
 const dy1 = b.y - c.y, dy2 = d.y - c.y, dy3 = a.y - b.y + c.y - d.y;
 let g = 0, h = 0;
 if (Math.abs(dx3) + Math.abs(dy3) > 1e-9) {
  const divisor = dx1 * dy2 - dx2 * dy1;
  if (Math.abs(divisor) < 1e-9) return null;
  g = (dx3 * dy2 - dx2 * dy3) / divisor;
  h = (dx1 * dy3 - dx3 * dy1) / divisor;
 }
 return [b.x - a.x + g * b.x, d.x - a.x + h * d.x, a.x,
  b.y - a.y + g * b.y, d.y - a.y + h * d.y, a.y, g, h, 1];
}

function inverse(matrix) {
 const [a, b, c, d, e, f, g, h, i] = matrix;
 const values = [e * i - f * h, c * h - b * i, b * f - c * e,
  f * g - d * i, a * i - c * g, c * d - a * f,
  d * h - e * g, b * g - a * h, a * e - b * d];
 const determinant = a * values[0] + b * values[3] + c * values[6];
 return Math.abs(determinant) > 1e-9 ? values.map(value => value / determinant) : null;
}

function project(matrix, x, y) {
 const divisor = matrix[6] * x + matrix[7] * y + matrix[8];
 return Math.abs(divisor) > 1e-9 ? {x: (matrix[0] * x + matrix[1] * y + matrix[2]) / divisor, y: (matrix[3] * x + matrix[4] * y + matrix[5]) / divisor} : null;
}

/** Measure user-confirmed outlines; coordinates stay in the original image. */
export function measureFromQuads(outerQuad, innerQuad) {
 if (!validQuad(outerQuad) || !validQuad(innerQuad)) return unavailable('Use four ordered corners for each outline: top left, top right, bottom right, bottom left.');
 const transform = squareTransform(outerQuad), undo = transform && inverse(transform);
 if (!undo) return unavailable('The card outline cannot be corrected. Adjust its four corners.');
 const normalized = innerQuad.map(point => project(undo, point.x, point.y));
 if (normalized.some(point => !point || point.x <= 0 || point.x >= 1 || point.y <= 0 || point.y >= 1)) return unavailable('Keep the printed frame strictly inside the outer card outline.', copyQuad(outerQuad));
 const [a, b, c, d] = normalized;
 // A frame with strongly sloping sides is not one stable rectangular reference.
 if (Math.abs(a.x - d.x) > 0.045 || Math.abs(b.x - c.x) > 0.045 || Math.abs(a.y - b.y) > 0.045 || Math.abs(c.y - d.y) > 0.045) return unavailable('The printed frame is not a stable rectangle. Adjust the outlines or use another photo.', copyQuad(outerQuad));
 const width = (distance(outerQuad[0], outerQuad[1]) + distance(outerQuad[3], outerQuad[2])) / 2;
 const height = (distance(outerQuad[0], outerQuad[3]) + distance(outerQuad[1], outerQuad[2])) / 2;
 if (Math.min(width, height) < 40) return unavailable('The card is too small to measure.', copyQuad(outerQuad));
 const margins = {left: (a.x + d.x) / 2, right: 1 - (b.x + c.x) / 2, top: (a.y + b.y) / 2, bottom: 1 - (c.y + d.y) / 2};
 if (Object.values(margins).some(value => value <= 0 || value >= 0.25)) return unavailable('The selected inner outline does not look like a printed card frame.', copyQuad(outerQuad));
 const left = Math.round(margins.left / (margins.left + margins.right) * 100);
 const top = Math.round(margins.top / (margins.top + margins.bottom) * 100);
 return {status: 'measured', reason: 'Measured from the outer card and printed-frame outlines.', outerQuad: copyQuad(outerQuad), innerQuad: copyQuad(innerQuad),
  borders: {left: roundPixel(margins.left * width), right: roundPixel(margins.right * width), top: roundPixel(margins.top * height), bottom: roundPixel(margins.bottom * height)},
  ratios: {left, right: 100 - left, top, bottom: 100 - top}, dimensions: {width: roundPixel(width), height: roundPixel(height)}, uncertainty: null};
}

function resizePixels(data, width, height) {
 const scale = Math.min(1, MAX_DETECTION_SIDE / Math.max(width, height));
 const w = Math.round(width * scale), h = Math.round(height * scale), pixels = new Uint8Array(w * h * 3);
 for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
  const source = (Math.min(height - 1, Math.floor((y + 0.5) / scale)) * width + Math.min(width - 1, Math.floor((x + 0.5) / scale))) * 4, target = (y * w + x) * 3;
  const alpha = data[source + 3] / 255;
  for (let channel = 0; channel < 3; channel++) pixels[target + channel] = Math.round(data[source + channel] * alpha + 255 * (1 - alpha));
 }
 return {pixels, width: w, height: h, scaleX: width / w, scaleY: height / h};
}

function pixel(image, x, y) {
 const offset = (Math.max(0, Math.min(image.height - 1, Math.round(y))) * image.width + Math.max(0, Math.min(image.width - 1, Math.round(x)))) * 3;
 return [image.pixels[offset], image.pixels[offset + 1], image.pixels[offset + 2]];
}

function background(image) {
 const samples = [], step = Math.max(1, Math.floor(Math.min(image.width, image.height) / 90));
 for (let x = 0; x < image.width; x += step) samples.push(pixel(image, x, 0), pixel(image, x, image.height - 1));
 for (let y = 0; y < image.height; y += step) samples.push(pixel(image, 0, y), pixel(image, image.width - 1, y));
 const color = [0, 1, 2].map(channel => median(samples.map(sample => sample[channel])));
 const spread = samples.map(sample => colorDistance(sample, color)).sort((a, b) => a - b);
 if (spread[Math.floor(spread.length * 0.8)] > 35) return null;
 return {color, threshold: Math.max(22, median(spread) * 3 + 10)};
}

function cardBoundary(image, backdrop) {
 const {width, height, pixels} = image, count = width * height;
 const mask = new Uint8Array(count), queue = new Uint32Array(count);
 const thresholdSquared = backdrop.threshold * backdrop.threshold * 3;
 for (let index = 0; index < count; index++) {
  const offset = index * 3;
  const r = pixels[offset] - backdrop.color[0], g = pixels[offset + 1] - backdrop.color[1], b = pixels[offset + 2] - backdrop.color[2];
  mask[index] = r * r + g * g + b * b > thresholdSquared ? 1 : 0;
 }
 let best = null;
 for (let start = 0; start < count; start++) {
  if (mask[start] !== 1) continue;
  let head = 0, tail = 1; queue[0] = start; mask[start] = 2;
  while (head < tail) {
   const index = queue[head++], x = index % width;
   if (x && mask[index - 1] === 1) { mask[index - 1] = 2; queue[tail++] = index - 1; }
   if (x < width - 1 && mask[index + 1] === 1) { mask[index + 1] = 2; queue[tail++] = index + 1; }
   if (index >= width && mask[index - width] === 1) { mask[index - width] = 2; queue[tail++] = index - width; }
   if (index + width < count && mask[index + width] === 1) { mask[index + width] = 2; queue[tail++] = index + width; }
  }
  if (tail < count * 0.15 || best && tail <= best.area) continue;
  const rowMin = new Int32Array(height).fill(width), rowMax = new Int32Array(height).fill(-1);
  const colMin = new Int32Array(width).fill(height), colMax = new Int32Array(width).fill(-1);
  let touchesEdge = false;
  for (let index = 0; index < tail; index++) {
   const point = queue[index], x = point % width, y = Math.floor(point / width);
   rowMin[y] = Math.min(rowMin[y], x); rowMax[y] = Math.max(rowMax[y], x);
   colMin[x] = Math.min(colMin[x], y); colMax[x] = Math.max(colMax[x], y);
   if (x <= 1 || y <= 1 || x >= width - 2 || y >= height - 2) touchesEdge = true;
  }
  const points = [];
  for (let y = 0; y < height; y++) if (rowMax[y] >= 0) points.push({x: rowMin[y] + 0.5, y: y + 0.5}, {x: rowMax[y] + 0.5, y: y + 0.5});
  for (let x = 0; x < width; x++) if (colMax[x] >= 0) points.push({x: x + 0.5, y: colMin[x] + 0.5}, {x: x + 0.5, y: colMax[x] + 0.5});
  best = {area: tail, points, touchesEdge};
 }
 return best;
}

function fitLine(points) {
 if (points.length < 8) return null;
 const mean = points.reduce((sum, point) => ({x: sum.x + point.x / points.length, y: sum.y + point.y / points.length}), {x: 0, y: 0});
 let xx = 0, yy = 0, xy = 0;
 for (const point of points) { const x = point.x - mean.x, y = point.y - mean.y; xx += x * x; yy += y * y; xy += x * y; }
 const angle = 0.5 * Math.atan2(2 * xy, xx - yy), a = -Math.sin(angle), b = Math.cos(angle);
 const residuals = points.map(point => Math.abs(a * (point.x - mean.x) + b * (point.y - mean.y)));
 if (median(residuals) > 2.5) return null;
 return {a, b, c: -(a * mean.x + b * mean.y)};
}

function intersection(a, b) {
 const determinant = a.a * b.b - b.a * a.b;
 if (Math.abs(determinant) < 1e-6) return null;
 return {x: (a.b * b.c - b.b * a.c) / determinant, y: (a.c * b.a - b.c * a.a) / determinant};
}

function outerOutline(boundary, width, height) {
 const extreme = score => boundary.points.reduce((best, point) => score(point) < score(best) ? point : best);
 const rough = [extreme(point => point.x + point.y), extreme(point => -point.x + point.y), extreme(point => -point.x - point.y), extreme(point => point.x - point.y)];
 if (!validQuad(rough)) return null;
 const band = Math.max(4, Math.min(width, height) * 0.018), lines = [];
 for (let index = 0; index < 4; index++) {
  const start = rough[index], end = rough[(index + 1) % 4], dx = end.x - start.x, dy = end.y - start.y, length = distance(start, end);
  const points = boundary.points.filter(point => {
   const projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (length * length);
   return projection >= 0.12 && projection <= 0.88 && Math.abs(cross(start, end, point)) / length <= band;
  });
  const line = fitLine(points); if (!line) return null; lines.push(line);
 }
 const quad = lines.map((line, index) => intersection(lines[(index + 3) % 4], line));
 if (!validQuad(quad) || quad.some(point => point.x < 2 || point.y < 2 || point.x > width - 2 || point.y > height - 2)) return null;
 const widths = [distance(quad[0], quad[1]), distance(quad[3], quad[2])], heights = [distance(quad[0], quad[3]), distance(quad[1], quad[2])];
 const aspect = (widths[0] + widths[1]) / (heights[0] + heights[1]);
 if (aspect < 0.58 || aspect > 0.86 || Math.max(...widths) / Math.min(...widths) > 1.4 || Math.max(...heights) / Math.min(...heights) > 1.4) return null;
 if (Math.abs(quad[1].y - quad[0].y) / widths[0] > 0.4 || Math.abs(quad[2].y - quad[3].y) / widths[1] > 0.4) return null;
 return quad;
}

function rectify(image, quad) {
 const transform = squareTransform(quad);
 if (!transform) return null;
 const width = Math.max(1, Math.round((distance(quad[0], quad[1]) + distance(quad[3], quad[2])) / 2));
 const height = Math.max(1, Math.round((distance(quad[0], quad[3]) + distance(quad[1], quad[2])) / 2));
 const pixels = new Uint8Array(width * height * 3);
 for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
  const u = x / (width - 1), v = y / (height - 1), divisor = transform[6] * u + transform[7] * v + transform[8];
  if (Math.abs(divisor) < 1e-9) return null;
  const sourceX = Math.max(0, Math.min(image.width - 1, Math.round((transform[0] * u + transform[1] * v + transform[2]) / divisor)));
  const sourceY = Math.max(0, Math.min(image.height - 1, Math.round((transform[3] * u + transform[4] * v + transform[5]) / divisor)));
  const source = (sourceY * image.width + sourceX) * 3, target = (y * width + x) * 3;
  pixels[target] = image.pixels[source]; pixels[target + 1] = image.pixels[source + 1]; pixels[target + 2] = image.pixels[source + 2];
 }
 return {pixels, width, height, transform};
}

function sidePixel(image, side, along, depth) {
 if (side === 'left') return pixel(image, depth, along);
 if (side === 'right') return pixel(image, image.width - 1 - depth, along);
 if (side === 'top') return pixel(image, along, depth);
 return pixel(image, along, image.height - 1 - depth);
}

function printedEdge(image, side) {
 const vertical = side === 'left' || side === 'right', normalSize = vertical ? image.width : image.height, alongSize = vertical ? image.height : image.width;
 const start = Math.max(4, Math.ceil(normalSize * 0.012)), end = Math.floor(normalSize * 0.18);
 const candidates = [], seedColors = [];
 for (let scan = 0; scan < SCAN_COUNT; scan++) {
  const along = (0.12 + 0.76 * scan / (SCAN_COUNT - 1)) * (alongSize - 1), peaks = [];
  seedColors.push(sidePixel(image, side, along, Math.max(2, Math.floor(start / 2))));
  const gradients = [];
  for (let depth = start; depth <= end; depth++) gradients.push({depth, strength: colorDistance(sidePixel(image, side, along, depth - 2), sidePixel(image, side, along, depth + 2))});
  for (let index = 1; index < gradients.length - 1; index++) {
   const peak = gradients[index];
   if (peak.strength >= 18 && peak.strength >= gradients[index - 1].strength && peak.strength >= gradients[index + 1].strength) peaks.push(peak);
  }
  peaks.sort((a, b) => b.strength - a.strength);
  const selected = [];
  for (const peak of peaks) { if (selected.every(other => Math.abs(other.depth - peak.depth) > 4)) selected.push(peak); if (selected.length === 3) break; }
  for (const peak of selected) candidates.push({...peak, scan, along});
 }
 const seed = [0, 1, 2].map(channel => median(seedColors.map(color => color[channel])));
 if (median(seedColors.map(color => colorDistance(color, seed))) > 32) return null;
 let best = null;
 for (const candidate of candidates) {
  const members = candidates.filter(other => Math.abs(other.depth - candidate.depth) <= 2.5);
  const unique = new Map(); for (const member of members) if (!unique.has(member.scan) || unique.get(member.scan).strength < member.strength) unique.set(member.scan, member);
  const group = [...unique.values()];
  if (group.length < Math.ceil(SCAN_COUNT * 0.75)) continue;
  const depth = median(group.map(member => member.depth));
  // Outside the candidate edge must still be one plain printed border. A
  // high-contrast artwork line alone does not qualify as a centering frame.
  let consistent = 0;
  for (const member of group) {
   const colors = [0.3, 0.6, 0.85].map(fraction => sidePixel(image, side, member.along, depth * fraction));
   if (colors.every(color => colorDistance(color, seed) < 42)) consistent++;
  }
  if (consistent < Math.ceil(group.length * 0.85)) continue;
  const score = group.length * 100 + median(group.map(member => member.strength));
  if (!best || score > best.score) best = {depth, seed, score, deviation: median(group.map(member => Math.abs(member.depth - depth)))};
 }
 return best;
}

/** Conservative automatic measurement for a complete, visibly framed card. */
export function detectCardCentering({data, width, height} = {}) {
 if (!Number.isInteger(width) || !Number.isInteger(height) || Math.min(width, height) < 120 || width * height > MAX_PIXELS || !data || data.length !== width * height * 4 || !(data instanceof Uint8Array || data instanceof Uint8ClampedArray)) return unavailable('Use a supported, clear card image with valid pixel dimensions.');
 const image = resizePixels(data, width, height), backdrop = background(image);
 if (!backdrop) return unavailable('Use a plain background so all four outer card edges can be found.');
 const boundary = cardBoundary(image, backdrop);
 if (!boundary) return unavailable('The outer card edges could not be found. Keep the whole card large in the photo.');
 if (boundary.touchesEdge) return unavailable('A card edge meets the photo boundary. Retake with a small visible background around every side.');
 const quad = outerOutline(boundary, image.width, image.height);
 if (!quad) return unavailable('The outer card outline is unclear or too tilted. Use a straight-on portrait photo.');
 const originalQuad = quad.map(point => ({x: point.x * image.scaleX, y: point.y * image.scaleY}));
 const corrected = rectify(image, quad);
 if (!corrected) return unavailable('The card perspective could not be corrected.', originalQuad);
 const sides = Object.fromEntries(['left', 'right', 'top', 'bottom'].map(side => [side, printedEdge(corrected, side)]));
 if (Object.values(sides).some(side => !side)) return unavailable('A continuous printed frame could not be found on all four sides. Full-art or unclear borders cannot be measured automatically.', originalQuad);
 const seeds = Object.values(sides).map(side => side.seed);
 if (seeds.some(color => seeds.some(other => colorDistance(color, other) > 65))) return unavailable('The four detected edges do not share one clear printed border. Check the outlines manually.', originalQuad);
 const left = sides.left.depth / (corrected.width - 1), right = 1 - sides.right.depth / (corrected.width - 1);
 const top = sides.top.depth / (corrected.height - 1), bottom = 1 - sides.bottom.depth / (corrected.height - 1);
 const innerQuad = [[left, top], [right, top], [right, bottom], [left, bottom]].map(([x, y]) => {
  const point = project(corrected.transform, x, y); return {x: point.x * image.scaleX, y: point.y * image.scaleY};
 });
 const result = measureFromQuads(originalQuad, innerQuad);
 if (result.status !== 'measured') return result;
 const horizontalError = Math.max(1, sides.left.deviation + sides.right.deviation + 1);
 const verticalError = Math.max(1, sides.top.deviation + sides.bottom.deviation + 1);
 const leftRight = Math.ceil(horizontalError / (sides.left.depth + sides.right.depth) * 100);
 const topBottom = Math.ceil(verticalError / (sides.top.depth + sides.bottom.depth) * 100);
 if (leftRight > 8 || topBottom > 8) return unavailable('The border is too thin or inconsistent for a useful ratio. Use a sharper photo or adjust the outlines.', originalQuad);
 return {...result, reason: 'Automatically measured from visible edges. Check the overlaid outlines before using the ratios.', uncertainty: {leftRight, topBottom, basis: 'Approximate percentage-point sensitivity to detected edge variation; not calibrated accuracy.'}};
}
