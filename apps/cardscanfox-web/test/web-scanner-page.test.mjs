import assert from 'node:assert/strict';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {createRenderer} from '../src/render.mjs';
import {resolveServicePage} from '../src/live-render.mjs';
import {mayIndex,publicSitemap} from '../src/publication.mjs';
import {validatePhoto,cardImageTensor} from '../public/assets/web-scanner.js';
import {startLocalServer,localAssetBinding} from '@kando/website-content/node-server';
const url=path=>new URL(path,'https://tcgcard.fun');

test('both scanner owners render working inputs, same-page text forms and scoped metadata before JavaScript',()=>{
 const renderer=createRenderer({liveSite:true});
 for(const mode of ['pokemon','sports']){const path='/'+mode+'-card-scanner',page=renderer.resolvePage(url(path));assert.equal(page.status,200);assert.match(page.html,new RegExp('<title>[^<]*'+(mode==='pokemon'?'Pokémon':'Sports')+' Card Scanner'));assert.match(page.html,/data-scan-file type="file"/);assert.match(page.html,/data-camera-file[^>]*capture="environment"/);assert.ok(page.html.includes('action="'+path+'"'));assert.match(page.html,/src="\/assets\/web-scanner.js"/);assert.doesNotMatch(page.html,/<script[^>]*src="[^\"]*(?:onnx|ort\.wasm)/);}
 assert.equal(mayIndex(url('/sports-card-scanner')),true);assert.match(publicSitemap(),/\/sports-card-scanner/);const grading=renderer.resolvePage(url('/ai-card-grading'));assert.equal(grading.status,200);assert.match(grading.html,/data-pregrade-form/);assert.match(grading.html,/\/site-api\/v1\/pregrade|\/assets\/web-pregrade.js/);
});

test('same-page text lookup reads published data and never substitutes snapshot prices on failure',async()=>{
 let requested;
 const card={publicCardId:'matching-1',name:'Charizard',gameSlug:'pokemon',set_name:'Live Set',set_code:'LIVE',card_number:'199/165',image_url:'https://image.tcgcard.fun/cards/matching-1.jpg',price_usd:12.34,price_as_of:'2026-11-15'};
 const binding={fetch:async request=>{requested=new URL(request.url);return Response.json({success:true,data:{games:[{slug:'pokemon'}],cards:[card],result:{items:[card]}},meta:{datasetMode:'published-read-only'}});}};
 const result=await resolveServicePage(url('/pokemon-card-scanner?q=Charizard'),binding);assert.equal(requested.searchParams.get('path'),'/games/pokemon');assert.equal(requested.searchParams.get('q'),'Charizard');assert.match(result.html,/\$12\.34/);assert.match(result.html,/data-text-results/);
 const failed=await resolveServicePage(url('/pokemon-card-scanner?q=Charizard'),{fetch:async()=>{throw Error('offline');}});assert.match(failed.html,/Text lookup is temporarily unavailable/);assert.doesNotMatch(failed.html,/\$145\.78/);
});

test('file limits reject unsupported input and RGB preprocessing matches the existing model contract',()=>{
 for(const file of [{type:'text/plain',size:100},{type:'image/png',size:0},{type:'image/jpeg',size:21*1024*1024}])assert.throws(()=>validatePhoto(file));
 assert.doesNotThrow(()=>validatePhoto({type:'image/webp',size:100}));
 const pixels=new Uint8ClampedArray(384*384*4);pixels[0]=0;pixels[1]=127.5;pixels[2]=255;
 let shape,values;const runtime={Tensor:class {constructor(type,data,dims){assert.equal(type,'float32');values=data;shape=dims;}}};
 const canvas={getContext:()=>({drawImage(){},getImageData:()=>({data:pixels})})};cardImageTensor({},runtime,canvas);
 assert.deepEqual(shape,[1,3,384,384]);assert.equal(values[0],-1);assert.equal(values[384*384*2],1);assert.ok(Math.abs(values[384*384])<0.005);
});

test('the shared loopback server preserves POST bodies and serves model modules with correct MIME',async()=>{
 const server=startLocalServer({fetch:async request=>Response.json({method:request.method,body:await request.text()})},{},{port:0,label:'scanner transport test'});
 try{if(!server.listening)await new Promise(resolve=>server.once('listening',resolve));const response=await fetch('http://127.0.0.1:'+server.address().port+'/recognize',{method:'POST',body:'{"vector":[1]}'});assert.deepEqual(await response.json(),{method:'POST',body:'{"vector":[1]}'});}
 finally{server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
 const assets=localAssetBinding(fileURLToPath(new URL('../public/',import.meta.url)));
 for(const [path,type]of [['ort-wasm-simd-threaded.mjs','text/javascript'],['ort-wasm-simd-threaded.wasm','application/wasm']]){const response=await assets.fetch(new Request('http://127.0.0.1/assets/scanner/'+path));assert.equal(response.status,200);assert.match(response.headers.get('Content-Type'),new RegExp(type));}
});


test('sports text search selects the sport before pagination and does not falsely empty mixed catalog results',async()=>{
 let requested;
 const basketball={id:'50000',slug:'basketball',name:'Basketball'};
 const card={publicCardId:'sports-1',name:'Jordan',gameSlug:'basketball',object_type:'sports',set_name:'Live Sports',card_number:'001',image_url:'https://image.tcgcard.fun/cards/sports-1.jpg',price_usd:5,price_as_of:'2026-11-15'};
 const binding={fetch:async request=>{requested=new URL(request.url);return Response.json({success:true,data:{games:[basketball],cards:[card],result:{items:[card],hasMore:true,page:1,pageSize:6,nextPage:2,total:null}},meta:{datasetMode:'published-read-only'}});}};
 const result=await resolveServicePage(url('/sports-card-scanner?q=001&game=basketball'),binding);assert.equal(requested.searchParams.get('game'),'basketball');assert.equal(requested.searchParams.get('path'),'/cards');assert.match(result.html,/Jordan/);assert.match(result.html,/value="basketball" selected/);assert.match(result.html,/page=2/);assert.match(result.html,/game=basketball/);
 const noSport=createRenderer({liveSite:true,games:[basketball]}).resolvePage(url('/sports-card-scanner?q=001'));assert.match(noSport.html,/Choose a sport to search its published cards/);assert.doesNotMatch(noSport.html,/No matching published records/);
});


test('an unavailable sports catalog keeps a valid dynamic sport query in a temporary error state',async()=>{
 const result=await resolveServicePage(url('/sports-card-scanner?q=001&game=game-50001'),{fetch:async()=>{throw Error('catalog offline');}});
 assert.equal(result.status,200);assert.equal(result.dataAvailable,false);assert.match(result.html,/Text lookup is temporarily unavailable/);assert.doesNotMatch(result.html,/No matching published records/);
});


test('snapshot text lookup keeps page state so Next advances beyond the first six matches',()=>{
 const renderer=createRenderer(),first=renderer.resolvePage(url('/pokemon-card-scanner?q=a&page=1')).html,second=renderer.resolvePage(url('/pokemon-card-scanner?q=a&page=2')).html;
 const ids=html=>[...html.matchAll(/data-save="([^"]+)"/g)].map(m=>m[1]);
 assert.ok(ids(first).length>0);assert.ok(ids(second).length>0);assert.ok(ids(first).every(id=>!ids(second).includes(id)));assert.match(second,/rel="prev"/);
});
