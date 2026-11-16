import assert from 'node:assert/strict';
import test from 'node:test';
import {deflateSync} from 'node:zlib';
import {readFileSync} from 'node:fs';
import {handleWebPregrade} from '../src/web-pregrade.mjs';

const endpoint = 'https://tcgcard.fun/site-api/v1/pregrade';
const criteria = ['centering','corners','edges','surface','print'];

function crc32(bytes) {
 let crc = 0xffffffff;
 for (const byte of bytes) {
  crc ^= byte;
  for (let bit = 0; bit < 8; bit++) crc = crc >>> 1 ^ (crc & 1 ? 0xedb88320 : 0);
 }
 return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
 const name = Buffer.from(type), length = Buffer.alloc(4), crc = Buffer.alloc(4);
 length.writeUInt32BE(data.length);crc.writeUInt32BE(crc32(Buffer.concat([name,data])));
 return Buffer.concat([length,name,data,crc]);
}
function photo(color, width = 640, height = 896) {
 const header = Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8] = 8;header[9] = 2;
 const pixels = Buffer.alloc(height * (width * 3 + 1),color);
 for (let row = 0; row < height; row++) pixels[row * (width * 3 + 1)] = 0;
 const png = Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(pixels)),chunk('IEND',Buffer.alloc(0))]);
 return {dataUrl:'data:image/png;base64,'+png.toString('base64'),width,height};
}
const photos = {front:photo(40),back:photo(200)};
const request = (body = photos, headers = {}, options = {}) => new Request(endpoint,{
 method:'POST',headers:{Origin:'https://tcgcard.fun','Content-Type':'application/json','CF-Connecting-IP':'192.0.2.10',...headers},body:JSON.stringify(body),...options,
});
const side = () => ({quality:'good',issues:[], ...Object.fromEntries(criteria.map(name => [name,{severity:'none_visible',observation:'No visible defect in the supplied photo.'}]))});
const assessment = () => ({pair:{oppositeSides:true,sameCardPlausible:true,issues:[]},front:side(),back:side()});
function environment({output,run,personal = true,global = true} = {}) {
 const calls = {personal:[],global:[],models:[]};
 const env = {
  WEB_PREGRADING_RATE_LIMITER:{async limit(value){calls.personal.push(value);return {success:personal};}},
  WEB_PREGRADING_GLOBAL_LIMITER:{async limit(value){calls.global.push(value);return {success:global};}},
  WEB_PREGRADING_AI:{async run(...args){calls.models.push(args);return run ? run(...args) : {response:JSON.stringify(output ?? assessment())};}},
 };
 return {env,calls};
}

test('a valid pair is assessed once, on the website only, and returns a broad photo range without price claims',async()=>{
 const {env,calls} = environment(), response = await handleWebPregrade(request(),env), body = await response.json();
 assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');assert.match(response.headers.get('X-Robots-Tag'),/noindex/);
 assert.equal(body.success,true);assert.equal(body.data.status,'estimated');assert.deepEqual(body.data.range,{low:8,high:10});assert.match(body.data.summary,/not a calibrated professional grade/);
 assert.equal(body.meta.method,'photo-pregrade-v1');assert.equal(body.meta.model,'@cf/meta/llama-4-scout-17b-16e-instruct');assert.ok(Number.isFinite(Date.parse(body.meta.assessedAt)));
 assert.deepEqual(calls.personal,[{key:'web-pregrade:192.0.2.10'}]);assert.deepEqual(calls.global,[{key:'web-pregrade-all'}]);assert.equal(calls.models.length,1);
 const [model,input,options] = calls.models[0];assert.equal(model,body.meta.model);assert.equal(input.max_tokens,1800);assert.equal(input.temperature,0);assert.equal(input.response_format.type,'json_schema');
 const urls = input.messages[1].content.filter(item => item.type === 'image_url').map(item => item.image_url.url);assert.deepEqual(urls,[photos.front.dataUrl,photos.back.dataUrl]);assert.ok(options.signal instanceof AbortSignal);
 assert.doesNotMatch(JSON.stringify(body),/data:image|price_usd|authenticity|confidence/);
});

test('the worst visible criterion controls the range; clean corners cannot erase severe damage',async()=>{
 for (const [severity,range] of [['minor',{low:6,high:9}],['moderate',{low:3,high:7}],['major',{low:1,high:4}]]) {
  const value = assessment();value.back.edges = {severity,observation:'Visible edge wear in the supplied back photo.'};
  const {env} = environment({output:value}), body = await (await handleWebPregrade(request(),env)).json();
  assert.equal(body.data.status,'estimated');assert.deepEqual(body.data.range,range);assert.equal(body.data.back.edges.severity,severity);
 }
});

test('blur, glare, hidden details or uncertain centering return photo guidance without any grade',async()=>{
 for (const alter of [value => {value.front.quality = 'limited';value.front.issues = ['Use even light to remove glare.'];},value => {value.back.surface.severity = 'unassessable';value.back.surface.observation = 'Surface detail is blurred.';},value => {value.front.centering.severity = 'unassessable';value.front.centering.observation = 'The borderless design has no reliable reference.';}]) {
  const value = assessment();alter(value);const {env} = environment({output:value}), body = await (await handleWebPregrade(request(),env)).json();
  assert.equal(body.data.status,'needs_better_photos');assert.equal(body.data.range,null);
 }
});

test('non-cards, same-side pairs and mismatched cards cannot receive a grade',async()=>{
 for (const alter of [value => {value.pair.oppositeSides = false;},value => {value.pair.sameCardPlausible = false;},value => {value.front.quality = 'unusable';value.front.issues = ['Show a physical card with all four corners.'];}]) {
  const value = assessment();alter(value);const {env} = environment({output:value}), body = await (await handleWebPregrade(request(),env)).json();
  assert.equal(body.data.status,'needs_better_photos');assert.equal(body.data.range,null);
 }
});

test('Workers AI JSON mode may return a parsed object without changing result validation',async()=>{
 const {env} = environment({run:() => ({response:assessment()})}), response = await handleWebPregrade(request(),env);
 assert.equal(response.status,200);assert.equal((await response.json()).data.status,'estimated');
});

test('real checked-in JPEG headers are accepted while a false dimension or truncated image is refused',async()=>{
 const frontBytes = readFileSync(new URL('../public/assets/cards/714372.jpg',import.meta.url));
 const backBytes = readFileSync(new URL('../public/assets/cards/687201.jpg',import.meta.url));
 // These image files exercise JPEG parsing only. The model response remains a stub, not a real grade.
 const pair = {front:{dataUrl:'data:image/jpeg;base64,'+frontBytes.toString('base64'),width:746,height:1040},back:{dataUrl:'data:image/jpeg;base64,'+backBytes.toString('base64'),width:686,height:1000}};
 const {env,calls} = environment();assert.equal((await handleWebPregrade(request(pair),env)).status,200);assert.equal(calls.models.length,1);
 assert.equal((await handleWebPregrade(request({...pair,front:{...pair.front,width:747}}),env)).status,422);
 const truncated = {...pair.front,dataUrl:'data:image/jpeg;base64,'+frontBytes.subarray(0,frontBytes.length-2).toString('base64')};
 assert.equal((await handleWebPregrade(request({...pair,front:truncated}),env)).status,422);assert.equal(calls.models.length,1);
});

test('only same-origin JSON POST on the exact path can enter the model',async()=>{
 const {env,calls} = environment();
 for (const method of ['GET','HEAD','OPTIONS','PUT']) {const response = await handleWebPregrade(new Request(endpoint,{method}),env);assert.equal(response.status,405);assert.equal(response.headers.get('Allow'),'POST');if (method === 'HEAD') assert.equal(await response.text(),'');}
 for (const Origin of ['', 'null','https://elsewhere.example']) assert.equal((await handleWebPregrade(request(undefined,{Origin}),env)).status,403);
 assert.equal((await handleWebPregrade(request(undefined,{'Sec-Fetch-Site':'cross-site'}),env)).status,403);
 assert.equal((await handleWebPregrade(request(undefined,{'Content-Type':'multipart/form-data'}),env)).status,415);
 assert.equal((await handleWebPregrade(new Request(endpoint+'?url=https://private.example',{method:'POST',headers:{Origin:'https://tcgcard.fun','Content-Type':'application/json'}}),env)).status,422);
 assert.equal((await handleWebPregrade(new Request('https://tcgcard.fun/not-pregrading'),env)).status,404);assert.equal(calls.models.length,0);
});

test('missing bindings or a missing trusted IP close only the pregrading endpoint',async()=>{
 const {env,calls} = environment();
 for (const key of ['WEB_PREGRADING_AI','WEB_PREGRADING_RATE_LIMITER','WEB_PREGRADING_GLOBAL_LIMITER']) {const response = await handleWebPregrade(request(),{...env,[key]:undefined});assert.equal(response.status,503);assert.equal(response.headers.get('Retry-After'),'60');}
 for (const ip of ['', 'not-an-ip','192.0.2.1,192.0.2.2']) assert.equal((await handleWebPregrade(request(undefined,{'CF-Connecting-IP':ip,'X-Forwarded-For':'192.0.2.99'}),env)).status,503);
 assert.equal(calls.models.length,0);
});

test('per-person and per-location burst limits fail before any paid model call',async()=>{
 let fixture = environment({personal:false}), response = await handleWebPregrade(request(),fixture.env);assert.equal(response.status,429);assert.equal((await response.json()).error.code,'RATE_LIMITED');assert.equal(fixture.calls.global.length,0);assert.equal(fixture.calls.models.length,0);
 fixture = environment({global:false});response = await handleWebPregrade(request(),fixture.env);assert.equal(response.status,429);assert.equal((await response.json()).error.code,'PREGRADING_BUSY');assert.equal(fixture.calls.models.length,0);
 fixture = environment();fixture.env.WEB_PREGRADING_RATE_LIMITER.limit = async()=>{throw new Error('private limiter failure');};response = await handleWebPregrade(request(),fixture.env);assert.equal(response.status,503);assert.doesNotMatch(await response.text(),/private limiter failure/);assert.equal(fixture.calls.models.length,0);
});

test('image bytes, actual dimensions, format and the exact two-photo shape are validated before AI',async()=>{
 const {env,calls} = environment();
 const invalid = [null,{}, {...photos,url:'https://private.example'}, {front:photos.front}, {...photos,front:{...photos.front,width:800}}, {...photos,front:{...photos.front,height:300}}, {...photos,front:{...photos.front,width:3000}}, {...photos,front:{...photos.front,dataUrl:'https://private.example/photo.jpg'}}, {...photos,front:{...photos.front,dataUrl:photos.front.dataUrl.replace('image/png','image/jpeg')}}, {...photos,front:{...photos.front,dataUrl:'data:image/png;base64,'+btoa('not a PNG')}}, {...photos,front:{...photos.front,extra:'untrusted'}}, {...photos,front:{...photos.front,dataUrl:photos.front.dataUrl+'!'}}];
 for (const body of invalid) assert.equal((await handleWebPregrade(request(body),env)).status,422);
 assert.equal(calls.models.length,0);assert.equal(calls.global.length,0);
});

test('the exact same image cannot be submitted for both sides',async()=>{
 const {env,calls} = environment(), response = await handleWebPregrade(request({front:photos.front,back:photos.front}),env);
 assert.equal(response.status,422);assert.equal((await response.json()).error.code,'DUPLICATE_PHOTOS');assert.equal(calls.models.length,0);
});

test('malformed JSON and declared or streaming oversized uploads never reach the model',async()=>{
 const {env,calls} = environment();
 assert.equal((await handleWebPregrade(request(undefined,{}, {body:'not JSON'}),env)).status,422);
 assert.equal((await handleWebPregrade(request(undefined,{'Content-Length':'4200001'}),env)).status,413);
 const stream = new ReadableStream({start(controller){controller.enqueue(new Uint8Array(2_100_001));controller.enqueue(new Uint8Array(2_100_001));controller.close();}});
 assert.equal((await handleWebPregrade(request(undefined,{}, {body:stream,duplex:'half'}),env)).status,413);assert.equal(calls.models.length,0);
});

test('an interrupted upload terminates rather than retaining an open image stream',async()=>{
 const {env,calls} = environment(), controller = new AbortController();
 env.WEB_PREGRADING_RATE_LIMITER.limit = async()=>{setTimeout(()=>controller.abort(),5);return {success:true};};
 const response = await handleWebPregrade(request(undefined,{}, {body:new ReadableStream({start(){}}),duplex:'half',signal:controller.signal}),env);
 assert.equal(response.status,408);assert.equal(calls.models.length,0);
});

test('invented centering ratios, partial fields and malformed model outputs fail explicitly',async()=>{
 const invalid = [{response:'not JSON'},{response:'x'.repeat(14_001)},{response:{}},{response:JSON.stringify({...assessment(),grade:10})}];
 for (const alter of [value => {value.front.centering.observation = 'The border is 55/45.';},value => {value.back.surface.severity = 'excellent';},value => {delete value.front.corners;},value => {value.front.edges.observation = '';},value => {value.pair.sameCardPlausible = 'yes';}]) {const value = assessment();alter(value);invalid.push({response:JSON.stringify(value)});}
 for (const output of invalid) {const {env} = environment({run:()=>output}), response = await handleWebPregrade(request(),env);assert.equal(response.status,502);assert.equal((await response.json()).error.code,'PREGRADING_INVALID_RESPONSE');}
});

test('model faults and cancellation do not retry or expose private diagnostics',async()=>{
 let fixture = environment({run:()=>{throw new Error('private model account detail');}}), response = await handleWebPregrade(request(),fixture.env);assert.equal(response.status,502);assert.doesNotMatch(await response.text(),/private model account detail/);assert.equal(fixture.calls.models.length,1);
 const controller = new AbortController();
 fixture = environment({run:()=>{setTimeout(()=>controller.abort(),5);return new Promise(()=>{});}});response = await handleWebPregrade(request(undefined,{}, {signal:controller.signal}),fixture.env);assert.equal(response.status,504);assert.equal(fixture.calls.models.length,1);
});
