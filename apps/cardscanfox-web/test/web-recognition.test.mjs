import assert from 'node:assert/strict';
import test from 'node:test';
import {handleWebRecognition} from '../src/web-recognition.mjs';
const path='https://tcgcard.fun/site-api/v1/recognize';
const vector=()=>Array.from({length:512},(_,i)=>i===0?1:0);
const request=(body={vector:vector(),card_type:0},headers={},options={})=>new Request(path,{method:'POST',headers:{'Origin':'https://tcgcard.fun','Content-Type':'application/json','CF-Connecting-IP':'192.0.2.10',...headers},body:JSON.stringify(body),...options});
const card=(id='717605',extra={})=>({publicCardId:id,card_ref:id,name:'Mew ex',game:'Pokemon',gameSlug:'pokemon',set_name:'30th Celebration',set_code:'30C',card_number:'152/128',language:'English',finish:'Holofoil',object_type:'tcg',image_url:'https://image.tcgcard.fun/cards/'+id+'.jpg',price_usd:54.54,price_as_of:'2026-11-15',reference:{sourceLabel:'Published market',source:'tcgplayer',metric:'market',currency:'USD',amount:54.54,priceAsOf:'2026-11-15',condition:'Near Mint',grader:'RAW'},...extra});
const publicResponse=value=>Response.json({success:true,data:value,meta:{datasetMode:'published-read-only'}});
function environment({candidates=[{product_id:'717605',confidence:92}],detail=id=>publicResponse(card(id)),recognize}={}){
 const calls={limits:[],vectors:[],cards:[]};
 return {calls,env:{
  WEB_SCANNER_RATE_LIMITER:{async limit(value){calls.limits.push(value);return {success:true};}},
  WEB_VECTOR_RECOGNITION:{async fetch(req){calls.vectors.push(req);return recognize?recognize(req):Response.json({candidates});}},
  SITE_DATA:{async fetch(req){calls.cards.push(req);return detail(decodeURIComponent(new URL(req.url).pathname.split('/').at(-1)));}},
 }};
}

test('recognition returns real catalog identity and price, never fields invented by the matching model',async()=>{
 const {env,calls}=environment({candidates:[{product_id:'717605',confidence:92,name:'Wrong model name',price_usd:999}]});
 const response=await handleWebRecognition(request({vector:vector(),card_type:0,game:'pokemon',url:'https://private.example/'}),env),body=await response.json();
 assert.equal(response.status,200);assert.equal(response.headers.get('Cache-Control'),'no-store');assert.match(response.headers.get('X-Robots-Tag'),/noindex/);assert.equal(body.data.status,'matched');
 assert.equal(body.data.candidates[0].name,'Mew ex');assert.equal(body.data.candidates[0].price_usd,54.54);assert.equal(body.data.candidates[0].price_as_of,'2026-11-15');assert.equal(body.data.candidates[0].reference.sourceLabel,'Published market');
 assert.equal(calls.limits[0].key,'web-scan:192.0.2.10');assert.equal(calls.vectors[0].url,'https://recognize-vec.internal/recognize');assert.equal(calls.vectors[0].redirect,'manual');assert.equal(calls.vectors[0].headers.get('Authorization'),null);assert.deepEqual(await calls.vectors[0].json(),{vector:vector(),card_type:0});
 assert.equal(calls.cards[0].url,'https://site-data.internal/site-api/v1/cards/717605');assert.equal(calls.cards[0].method,'GET');assert.equal(body.data.candidates[0].detail_url,'/cards/717605');
});

test('only same-origin JSON POST requests enter matching; unrelated paths and queries are rejected',async()=>{
 const {env,calls}=environment();
 for(const method of ['GET','HEAD','PUT','OPTIONS']){const r=await handleWebRecognition(new Request(path,{method}),env);assert.equal(r.status,405);assert.equal(r.headers.get('Allow'),'POST');if(method==='HEAD')assert.equal(await r.text(),'');}
 for(const Origin of ['', 'null','https://example.com'])assert.equal((await handleWebRecognition(request(undefined,{Origin}),env)).status,403);
 assert.equal((await handleWebRecognition(request(undefined,{'Sec-Fetch-Site':'cross-site'}),env)).status,403);
 assert.equal((await handleWebRecognition(request(undefined,{'Content-Type':'image/png'}),env)).status,415);
 assert.equal((await handleWebRecognition(new Request(path+'?target=https://example.com',{method:'POST',headers:{Origin:'https://tcgcard.fun','Content-Type':'application/json'}}),env)).status,422);
 assert.equal((await handleWebRecognition(new Request('https://tcgcard.fun/not-recognition',{method:'POST'}),env)).status,404);assert.equal(calls.vectors.length,0);
});

test('missing bindings or trusted client IP close only this new endpoint with a retry response',async()=>{
 const {env,calls}=environment();
 for(const key of ['WEB_VECTOR_RECOGNITION','WEB_SCANNER_RATE_LIMITER','SITE_DATA']){const response=await handleWebRecognition(request(),{...env,[key]:undefined});assert.equal(response.status,503);assert.equal(response.headers.get('Retry-After'),'60');}
 for(const ip of ['', 'not-an-ip','192.0.2.1,192.0.2.2']){const response=await handleWebRecognition(request(undefined,{'CF-Connecting-IP':ip,'X-Forwarded-For':'192.0.2.99'}),env);assert.equal(response.status,503);}
 assert.equal(calls.vectors.length,0);
});

test('rate limiting and failed limiter calls never call the matching service',async()=>{
 const {env,calls}=environment();
 env.WEB_SCANNER_RATE_LIMITER.limit=async()=>({success:false});let response=await handleWebRecognition(request(),env);assert.equal(response.status,429);assert.equal(response.headers.get('Retry-After'),'60');
 env.WEB_SCANNER_RATE_LIMITER.limit=async()=>{throw new Error('private limiter state');};response=await handleWebRecognition(request(),env);assert.equal(response.status,503);assert.doesNotMatch(await response.text(),/private limiter state/);assert.equal(calls.vectors.length,0);
});

test('the endpoint validates the real 512-value vector and numeric TCG or Sports enum',async()=>{
 const {env,calls}=environment();
 for(const body of [{},{vector:[],card_type:0},{vector:Array(512).fill(0),card_type:0},{vector:Array(512).fill(1e308),card_type:0},{vector:Array(512).fill(null),card_type:0},{vector:vector(),card_type:'tcg'},{vector:vector(),card_type:2},{vector:vector(),card_type:1,game:'pokemon'},{vector:vector(),card_type:0,game:'mtg'}])assert.equal((await handleWebRecognition(request(body),env)).status,422);
 assert.equal(calls.vectors.length,0);
});

test('malformed, declared oversized and chunked oversized bodies cannot reach vector matching',async()=>{
 const {env,calls}=environment();
 assert.equal((await handleWebRecognition(request(undefined,{}, {body:'not JSON'}),env)).status,422);
 assert.equal((await handleWebRecognition(request(undefined,{'Content-Length':'40000'}),env)).status,413);
 const stream=new ReadableStream({start(controller){controller.enqueue(new Uint8Array(20_000));controller.enqueue(new Uint8Array(20_000));controller.close();}});
 assert.equal((await handleWebRecognition(request(undefined,{}, {body:stream,duplex:'half'}),env)).status,413);assert.equal(calls.vectors.length,0);
});

test('an interrupted request stream terminates with a timeout response instead of hanging',async()=>{
 const {env,calls}=environment(),controller=new AbortController();
 env.WEB_SCANNER_RATE_LIMITER.limit=async()=>{setTimeout(()=>controller.abort(),5);return {success:true};};
 const stream=new ReadableStream({start(){}});
 const response=await handleWebRecognition(request(undefined,{}, {body:stream,duplex:'half',signal:controller.signal}),env);
 assert.equal(response.status,408);assert.equal(calls.vectors.length,0);
});

test('matching candidates are deduplicated and bounded without reordering by price or confidence',async()=>{
 const ids=['1','1','2','3','4','5','6'];const {env,calls}=environment({candidates:ids.map((id,i)=>({product_id:id,confidence:i}))});
 const response=await handleWebRecognition(request(),env),body=await response.json();assert.deepEqual(body.data.candidates.map(c=>c.product_id),['1','2','3','4','5']);assert.equal(calls.cards.length,5);assert.equal(body.data.candidates[0].confidence,0);
});

test('Pokemon and sports requests filter published identities rather than trusting the model category',async()=>{
 let fixture=environment({detail:()=>publicResponse(card('717605',{gameSlug:'mtg',game:'Magic'}))});let body=await(await handleWebRecognition(request({vector:vector(),card_type:0,game:'pokemon'}),fixture.env)).json();assert.equal(body.data.status,'no-match');
 fixture=environment();body=await(await handleWebRecognition(request({vector:vector(),card_type:1}),fixture.env)).json();assert.equal(body.data.status,'no-match');
 fixture=environment({detail:()=>publicResponse(card('717605',{object_type:'sports',gameSlug:'basketball',game:'Basketball'}))});body=await(await handleWebRecognition(request({vector:vector(),card_type:1}),fixture.env)).json();assert.equal(body.data.status,'matched');assert.equal(body.data.candidates[0].object_type,'sports');
});

test('real no-match and missing catalog details remain explicit no-match results',async()=>{
 let fixture=environment({candidates:[]});let body=await(await handleWebRecognition(request(),fixture.env)).json();assert.equal(body.data.status,'no-match');assert.equal(fixture.calls.cards.length,0);
 fixture=environment({detail:()=>new Response('Not found',{status:404})});body=await(await handleWebRecognition(request(),fixture.env)).json();assert.equal(body.data.status,'no-match');assert.deepEqual(body.data.candidates,[]);
});

test('missing published prices stay null while an actual zero is preserved',async()=>{
 for(const price of [null,0]){const {env}=environment({detail:()=>publicResponse(card('717605',{price_usd:price,price_as_of:price===null?null:'2026-11-15',reference:price===null?null:{sourceLabel:'Published source',amount:0,priceAsOf:'2026-11-15'}}))});const body=await(await handleWebRecognition(request(),env)).json();assert.equal(body.data.candidates[0].price_usd,price);}
});

test('failed, redirected, malformed or oversized matching results fail without exposing private diagnostics',async()=>{
 for(const recognize of [()=>new Response('private upstream',{status:500}),()=>new Response(null,{status:302,headers:{Location:'https://private.example/'}}),()=>new Response('not json'),()=>Response.json({candidates:[{product_id:'https://private.example/',confidence:92}]}),()=>Response.json({candidates:[{product_id:'717605',confidence:101}]}),()=>new Response('x'.repeat(40_000),{headers:{'Content-Type':'application/json'}})]){const {env,calls}=environment({recognize});const response=await handleWebRecognition(request(),env);assert.equal(response.status,502);assert.doesNotMatch(await response.text(),/private upstream|private\.example/);assert.equal(calls.cards.length,0);}
});

test('a catalog fault or review dataset fails the request rather than returning fake prices or partial success',async()=>{
 for(const detail of [()=>new Response('private catalog',{status:500}),()=>new Response('busy',{status:429}),()=>Response.json({success:true,data:card(),meta:{datasetMode:'review-snapshot'}}),()=>publicResponse(card('other-id')),()=>publicResponse(card('717605',{price_usd:-1}))]){const {env}=environment({detail});const response=await handleWebRecognition(request(),env);assert.equal(response.status,503);assert.equal(response.headers.get('Retry-After'),'60');assert.doesNotMatch(await response.text(),/private catalog/);}
});
