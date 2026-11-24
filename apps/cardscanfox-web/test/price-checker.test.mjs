import assert from 'node:assert/strict';
import test from 'node:test';
import {parse} from 'parse5';
import {createRenderer} from '../src/render.mjs';
import {resolveServicePage} from '../src/live-render.mjs';
import {mayIndex,publishHtml} from '../src/publication.mjs';

const card={publicCardId:'price-only-card',name:'Mew ex',set_name:'Test expansion',set_code:'TEST',publicSetId:'db-selected',card_number:'152/128',gameSlug:'pokemon',language:'English',finish:'Holofoil',image_url:'https://image.tcgcard.fun/cards/test.jpg',price_usd:12.34,price_as_of:'2026-11-16',reference:{seriesId:'published-series',sourceLabel:'Published market source',metric:'market',grader:'RAW',condition:'Near Mint'}};
const result={items:[card],page:1,pageSize:24,total:null,returnedCount:1,hasMore:false};
const data={games:[{id:'1',slug:'pokemon',name:'Pokémon'}],sets:[{id:'db-other',name:'Another set'}],cards:[card],result};
const response=(value=data,mode='published-read-only')=>Response.json({success:true,data:value,meta:{datasetMode:mode,catalogVersion:'test-publication'}});
const url=(query='')=>new URL('https://tcgcard.fun/card-price-checker'+query);
const visit=(n,f)=>{f(n);for(const c of n.childNodes??[])visit(c,f);};
const attr=(n,k)=>n.attrs?.find(a=>a.name===k)?.value;

test('the initial price checker is usable without a full-catalog query or review prices',async()=>{
 let calls=0;
 const binding={fetch:async()=>{calls++;throw new Error('No initial catalog read is expected.');}};
 for(const query of ['','?q=%20%20&set=all']){
  const page=await resolveServicePage(url(query),binding);
  assert.equal(page.status,200);assert.match(page.html,/<h1>Pokémon card value checker<\/h1>/);
  assert.match(page.html,/<title>Pokémon Card Value Checker &amp; Trading Card Price Checker \| CardScanFox<\/title>/);
  assert.match(page.html,/<form method="get" action="\/card-price-checker" role="search"/);
  assert.match(page.html,/name="q" type="search"/);assert.doesNotMatch(page.html,/price-checker-results-title/);
  assert.doesNotMatch(page.html,/Featured in review|145\.78/);
 }
 assert.equal(calls,0);
});
test('price checker answers the free value lookup intent before the legacy guide',()=>{
 const page=createRenderer({liveSite:true}).resolvePage(url());
 assert.match(page.html,/Use the free CardScanFox web lookup to find a matching Pokémon card record/);
 assert.match(page.html,/Can I check a Pokémon card value for free\?/);
 assert.match(page.html,/without downloading the app/);
 assert.match(page.html,/A reference price is not an appraisal or a guaranteed sale price/);
});

test('search stays on the checker and uses a bounded published query with selected filters',async()=>{
 const requests=[];
 const page=await resolveServicePage(url('?q=Mew&set=db-selected&game=pokemon&language=English&finish=Holofoil&price=available&sort=featured&page=2&after=previous-card&pageSize=48'),{fetch:async request=>{requests.push(new URL(request.url));return response({...data,result:{...result,page:2}});}});
 assert.equal(page.status,200);assert.equal(requests.length,1);
 const upstream=requests[0];assert.equal(upstream.pathname,'/site-api/v1/page-data');
 assert.equal(upstream.searchParams.get('path'),'/cards');assert.equal(upstream.searchParams.get('pageSize'),'24');
 for(const [key,value]of Object.entries({q:'Mew',set:'db-selected',game:'pokemon',language:'English',finish:'Holofoil',price:'available',sort:'featured',page:'2',after:'previous-card'}))assert.equal(upstream.searchParams.get(key),value,key);
 assert.match(page.html,/Mew ex/);assert.match(page.html,/152\/128/);assert.match(page.html,/Holofoil/);
 assert.match(page.html,/\$12\.34/);assert.match(page.html,/Published market source · market · Raw · Near Mint/);
 assert.match(page.html,/16 Nov 2026/);assert.match(page.html,/href="\/cards\/price-only-card\?series=published-series"/);
 assert.match(page.html,/<option value="db-selected" selected>Test expansion<\/option>/);
 assert.match(page.html,/name="language">[\s\S]*?<option value="English" selected>/);
 assert.doesNotMatch(page.html,/Featured in review/);
});

test('zero remains a real published amount while missing prices and condition remain explicit',async()=>{
 const zero={...card,publicCardId:'zero-card',name:'Zero amount record',price_usd:0,reference:{...card.reference,condition:null}};
 const absent={...card,publicCardId:'absent-card',name:'Missing amount record',price_usd:null,price_as_of:null,reference:null};
 const items=[zero,absent],page=await resolveServicePage(url('?q=record'),{fetch:async()=>response({...data,cards:items,result:{...result,items,returnedCount:2}})});
 const rows=[];visit(parse(page.html),n=>{if(n.tagName==='tr')rows.push(n);});
 const text=n=>n.nodeName==='#text'?n.value:(n.childNodes??[]).map(text).join(' ');
 const zeroRow=rows.map(text).find(s=>s.includes('Zero amount record'));
 const absentRow=rows.map(text).find(s=>s.includes('Missing amount record'));
 assert.match(zeroRow,/\$0\.00/);assert.match(zeroRow,/Condition not listed/);assert.doesNotMatch(zeroRow,/Near Mint/);
 assert.match(absentRow,/Price unavailable/);assert.match(absentRow,/No published price date/);assert.doesNotMatch(absentRow,/\$0\.00/);
});

test('query paging retains the search and exact filters with cursor direction',async()=>{
 const page=await resolveServicePage(url('?q=Mew&set=db-selected&language=English&sort=featured&page=2&after=old'),{fetch:async()=>response({...data,result:{...result,page:2,hasMore:true,hasPrevious:true,nextCursor:'last-card',previousCursor:'first-card'}})});
 const links=[];visit(parse(page.html),n=>{if(n.tagName==='a'&&['next','prev'].includes(attr(n,'rel')))links.push({rel:attr(n,'rel'),url:new URL(attr(n,'href'),'https://tcgcard.fun')});});
 assert.equal(links.length,2);
 for(const link of links){assert.equal(link.url.pathname,'/card-price-checker');for(const [key,value]of Object.entries({q:'Mew',set:'db-selected',language:'English',sort:'featured',pageSize:'24'}))assert.equal(link.url.searchParams.get(key),value);}
 const next=links.find(x=>x.rel==='next').url,previous=links.find(x=>x.rel==='prev').url;
 assert.equal(next.searchParams.get('after'),'last-card');assert.equal(next.searchParams.get('before'),null);assert.equal(next.searchParams.get('page'),'3');
 assert.equal(previous.searchParams.get('before'),'first-card');assert.equal(previous.searchParams.get('after'),null);assert.equal(previous.searchParams.get('page'),'1');
});

test('a selected set can be searched without a name, and unavailable set labels stay selected',async()=>{
 let calls=0;
 const page=await resolveServicePage(url('?set=db-selected&sort=price-desc'),{fetch:async request=>{calls++;assert.equal(new URL(request.url).searchParams.get('sort'),'price-desc');return response({...data,cards:[],result:{...result,items:[],returnedCount:0}});}});
 assert.equal(calls,1);assert.match(page.html,/No matching published records/);
 assert.match(page.html,/<option value="db-selected" selected>Selected set \(db-selected\)<\/option>/);
 assert.match(page.html,/<option value="price-desc" selected>/);
});

test('failed price lookups retain the same-page search and all filters without fake results',async()=>{
 const query='?q=Charizard&game=pokemon&set=db-selected&language=Japanese&finish=Reverse%20Holofoil&price=over100&sort=price-desc';
 const cases=[
  {name:'invalid query',fetch:async()=>new Response('',{status:400}),status:400,error:'invalid',retryAfter:null},
  {name:'rate limited',fetch:async()=>new Response('',{status:429,headers:{'Retry-After':'60'}}),status:503,error:'busy',retryAfter:'60'},
  {name:'unavailable',fetch:async()=>new Response('',{status:503,headers:{'Retry-After':'120'}}),status:503,error:'unavailable',retryAfter:'120'},
  {name:'unpublished response',fetch:async()=>response(data,'review-snapshot'),status:503,error:'unavailable',retryAfter:null},
  {name:'invalid response',fetch:async()=>response({...data,result:null}),status:503,error:'unavailable',retryAfter:null},
  {name:'network failure',fetch:async()=>{throw new Error('private connection detail');},status:503,error:'unavailable',retryAfter:null},
  {name:'malformed JSON',fetch:async()=>new Response('not JSON'),status:503,error:'unavailable',retryAfter:null},
 ];
 for(const entry of cases){
  const page=await resolveServicePage(url(query),{fetch:entry.fetch});
  assert.equal(page.status,entry.status,entry.name);assert.equal(page.dataAvailable,false,entry.name);assert.equal(page.retryAfter,entry.retryAfter,entry.name);
  const doc=parse(page.html),forms=[];visit(doc,n=>{if(n.tagName==='form'&&attr(n,'action')==='/card-price-checker')forms.push(n);});assert.equal(forms.length,1,entry.name);
  const controls=new Map();visit(forms[0],n=>{if(n.tagName==='input'&&attr(n,'name'))controls.set(attr(n,'name'),attr(n,'value'));if(n.tagName==='select'){const selected=n.childNodes.find(option=>option.tagName==='option'&&option.attrs.some(a=>a.name==='selected'));controls.set(attr(n,'name'),selected?attr(selected,'value'):attr(n.childNodes.find(option=>option.tagName==='option'),'value'));}});
  for(const [key,value]of Object.entries({q:'Charizard',game:'pokemon',set:'db-selected',language:'Japanese',finish:'Reverse Holofoil',price:'over100',sort:'price-desc'}))assert.equal(controls.get(key),value,entry.name+' '+key);
  assert.match(page.html,new RegExp('data-price-checker-error="'+entry.error+'"'),entry.name);assert.match(page.html,/Retry lookup/,entry.name);
  const retry=[];visit(doc,n=>{if(n.tagName==='div'&&attr(n,'data-price-checker-error'))visit(n,child=>{if(child.tagName==='a')retry.push(attr(child,'href'));});});assert.equal(retry[0],'/card-price-checker'+query,entry.name);
  assert.doesNotMatch(page.html,/price-checker-results-title|price-only-card|\$145\.78|private connection detail/,entry.name);
  assert.equal(mayIndex(url(query),page.status,page),false,entry.name);assert.match(publishHtml(page.html,url(query),page.status,page),/<meta name="robots" content="noindex,follow">/,entry.name);
 }
});

test('error rendering never calls the snapshot lookup and preserves invalid filter values for correction',()=>{
 const renderer=createRenderer({liveSite:true,priceCheckerError:'invalid',games:[],sets:[],cards:[],queryCards:()=>{throw new Error('An error page must not query snapshot prices.');}});
 const page=renderer.resolvePage(url('?q=Mew&game=custom-game&price=unknown-price&sort=unknown-sort'));
 assert.match(page.html,/<option value="custom-game" selected>Selected game \(custom-game\)<\/option>/);
 assert.match(page.html,/<option value="unknown-price" selected>Selected value \(unknown-price\)<\/option>/);
 assert.match(page.html,/<option value="unknown-sort" selected>Selected value \(unknown-sort\)<\/option>/);
 assert.doesNotMatch(page.html,/price-checker-results-title/);
});

test('the main checker has a stable canonical and query results stay outside indexing',()=>{
 const renderer=createRenderer({liveSite:true,queryCards:()=>result,cards:[card],games:data.games,sets:data.sets});
 const page=renderer.resolvePage(url('?q=Mew'));const published=publishHtml(page.html,url('?q=Mew'),200,page);
 assert.match(published,/<meta name="robots" content="noindex,follow">/);assert.equal(mayIndex(url('?q=Mew'),200,page),false);
 assert.match(published,/<link rel="canonical" href="https:\/\/tcgcard.fun\/card-price-checker">/);
 const main=renderer.resolvePage(url());assert.equal(mayIndex(url(),200,main),true);
 assert.match(main.html,/How to read a card price: printing, condition and dates/);
 assert.match(main.html,/<h2>Check the card before checking its value\.<\/h2>/);
});

test('card labels, selected filters and user searches remain escaped in the rendered tool',async()=>{
 const unsafe={...card,name:'<script>alert(1)</script>',reference:{...card.reference,sourceLabel:'<img onerror=bad>'}};
 const page=await resolveServicePage(url('?q=%22%3E%3Cimg%20onerror%3Dbad%3E'),{fetch:async()=>response({...data,cards:[unsafe],result:{...result,items:[unsafe]}})});
 assert.match(page.html,/&lt;script&gt;alert\(1\)&lt;\/script&gt;/);assert.match(page.html,/&lt;img onerror=bad&gt;/);
 assert.doesNotMatch(page.html,/<script>alert\(1\)/);assert.doesNotMatch(page.html,/<img onerror=bad>/);
});
