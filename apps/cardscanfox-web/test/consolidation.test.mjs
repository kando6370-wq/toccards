import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createRenderer,allStaticPaths,legacyPages} from '../src/render.mjs';
import {redirectTarget,redirectLocation} from '../src/redirects.mjs';
import {mayIndex,publicSitemap} from '../src/publication.mjs';
import {resolveServicePage} from '../src/live-render.mjs';
const origin='https://tcgcard.fun';
const merged={digimon:'digimon',lorcana:'lorcana','dragon-ball-super':'dragon-ball-super','flesh-and-blood':'flesh-and-blood'};

test('four game pages consolidate once into their exact guide while preserving query before fragment',()=>{
 for(const [slug,anchor]of Object.entries(merged))for(const suffix of ['','.html']){
  const path='/'+slug+'-card-scanner'+suffix;assert.equal(redirectTarget(path),'/card-identifier#'+anchor);
  const expected='/card-identifier?q=A%26B&game=lorcana#'+anchor;
  assert.equal(redirectLocation(path,'?q=A%26B&game=lorcana'),expected);
  const page=createRenderer().resolvePage(new URL(path+'?q=A%26B&game=lorcana',origin));assert.equal(page.status,301);assert.equal(page.location,expected);
 }
});

test('the functional existing TCG owner retains game-specific distinctions and separate sports scope',()=>{
 const renderer=createRenderer(),page=renderer.resolvePage(new URL('/card-identifier',origin));assert.equal(page.status,200);
 assert.match(page.html,/data-mode="tcg"/);assert.match(page.html,/type="file"/);assert.match(page.html,/id="web-scanner-game"/);
 for(const anchor of Object.values(merged))assert.ok(page.html.includes('id="'+anchor+'"'));
 for(const fact of ['alternate-art','Enchanted','cold foil','First Edition','Dragon Ball Super coverage is not confirmed'])assert.ok(page.html.includes(fact),fact);
 assert.doesNotMatch(page.html,/This website offers text lookup rather than a photo upload scanner/);
 assert.equal(renderer.resolvePage(new URL('/sports-card-scanner',origin)).status,200);
});

test('retired discovery paths leave the sitemap and metadata inventory, and card eligibility stays bounded',async()=>{
 const sitemap=publicSitemap(),meta=JSON.parse(await readFile(new URL('../content/seo-pages.json',import.meta.url),'utf8'));
 for(const slug of Object.keys(merged)){const path='/'+slug+'-card-scanner';assert.equal(mayIndex(new URL(path,origin)),false);assert.ok(!allStaticPaths.includes(path));assert.ok(!sitemap.includes(origin+path));assert.equal(meta[path],undefined);}
 assert.ok(sitemap.includes(origin+'/card-identifier'));
 for(const path of ['/mtg-card-scanner','/football-card-scanner','/one-piece-card-scanner','/basketball-card-scanner']){assert.equal(createRenderer().resolvePage(new URL(path,origin)).status,200);assert.ok(sitemap.includes(origin+path));}
 const cardPage={seo:{kind:'card',eligible:true},dataAvailable:true};
 assert.equal(mayIndex(new URL('/cards/717605',origin),200,cardPage),true);
 for(const id of ['223861','252957','unlisted-new-card'])assert.equal(mayIndex(new URL('/cards/'+id,origin),200,cardPage),false);
});

test('TCG text lookup scopes a dynamic game before pagination and preserves its error semantics',async()=>{
 let requested;
 const card={publicCardId:'tcg-1',name:'A Digimon card',gameSlug:'game-71',object_type:'tcg',set_name:'A set',card_number:'001',price_usd:null,image_url:'https://image.tcgcard.fun/cards/tcg-1.jpg'};
 const binding={fetch:async request=>{requested=new URL(request.url);return Response.json({success:true,data:{games:[{id:'71',name:'Digimon',slug:'game-71'}],cards:[card],result:{items:[card],page:2,pageSize:6,hasMore:false}},meta:{datasetMode:'published-read-only'}});}};
 const page=await resolveServicePage(new URL('/card-identifier?q=001&game=game-71&page=2',origin),binding);
 assert.equal(requested.searchParams.get('path'),'/cards');assert.equal(requested.searchParams.get('game'),'game-71');assert.equal(requested.searchParams.get('page'),'2');assert.match(page.html,/A Digimon card/);assert.match(page.html,/Price unavailable/);
 const failed=await resolveServicePage(new URL('/card-identifier?q=001&game=game-71',origin),{fetch:async()=>{throw Error('offline');}});assert.equal(failed.status,200);assert.match(failed.html,/Text lookup is temporarily unavailable/);
});

test('the anniversary answer page adds direct buying choices without removing dated singles or the existing UPC owner',()=>{
 const html=createRenderer().resolvePage(new URL('/blog/pokemon-tcg-30th-celebration-card-prices',origin)).html;
 for(const phrase of ['id="how-to-buy"','Buy a single','Choose booster packs','Choose a Day or Night UPC','where-to-buy/'])assert.ok(html.includes(phrase),phrase);
 assert.match(html,/href="\/blog\/pokemon-upc-30th-anniversary"/);
 const hub=createRenderer().resolvePage(new URL('/games/pokemon',origin)).html;assert.match(hub,/aria-label="Pokémon card value tasks"/);assert.match(hub,/href="\/games\/pokemon\?price=available"/);assert.match(hub,/id="pokemon-value-guide"/);
});

test('rendered active pages have no internal links to the four retired owners',()=>{
 const renderer=createRenderer();
 for(const path of allStaticPaths){const result=renderer.resolvePage(new URL(path,origin));for(const slug of Object.keys(merged))assert.ok(!result.html.includes('href="/'+slug+'-card-scanner'),path+' still links to retired '+slug);}
 assert.equal(legacyPages.length,46);
});
