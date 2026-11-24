import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import policy from '../content/index-policy.json' with {type:'json'};
import manifest from '../content/sitemaps/catalog-manifest.json' with {type:'json'};
import {mayIndex,publishHtml,publicSitemap} from '../src/publication.mjs';
import {redirectTarget} from '../src/redirects.mjs';
import {resolvePage} from '../src/render.mjs';
// Public membership from the protected 2026-10-12..2026-11-11 window. No raw GSC metrics.
const historicalPositivePaths=[
 "/",
 "/app",
 "/basketball-card-scanner",
 "/blog/",
 "/blog/ascended-heroes-card-list",
 "/blog/chaos-rising-card-list",
 "/blog/dungeon-crawler-carl-trading-cards",
 "/blog/gengar-card-values",
 "/blog/minior-pokemon-card-guide",
 "/blog/moonbreon-card-value",
 "/blog/phantasmal-flames-card-list",
 "/blog/pokemon-card-values",
 "/blog/pokemon-tcg-30th-celebration-card-prices",
 "/blog/pokemon-tcg-set-card-lists",
 "/blog/raw-vs-graded-card-values",
 "/blog/scanning-cards-from-watsontcg",
 "/blog/what-is-my-trading-card-worth",
 "/card-ai-vs-collx",
 "/card-ai-vs-ludex",
 "/card-collection-tracker",
 "/card-identifier",
 "/card-price-checker",
 "/card-scanner-comparison-2026",
 "/cards",
 "/cards/100031",
 "/cards/100041",
 "/cards/100043",
 "/cards/100099",
 "/cards/100182",
 "/cards/100221",
 "/cards/100223",
 "/cards/100251",
 "/cards/100272",
 "/cards/100280",
 "/cards/100288",
 "/cards/100299",
 "/cards/100311",
 "/cards/100331",
 "/cards/100344",
 "/cards/100357",
 "/cards/101050",
 "/cards/122890",
 "/cards/151711",
 "/cards/151712",
 "/cards/288229",
 "/cards/540143",
 "/cards/540153",
 "/cards/632366",
 "/cards/632376",
 "/cards/632377",
 "/cards/690216",
 "/cards/696678",
 "/cards/696681",
 "/cards/696833",
 "/cards/712934",
 "/cards/712935",
 "/cards/712936",
 "/cards/712943",
 "/cards/712945",
 "/cards/712946",
 "/cards/712949",
 "/cards/712951",
 "/cards/712953",
 "/cards/717605",
 "/cards/90139",
 "/cards/t100003",
 "/cards/t100006",
 "/cards/t100010",
 "/cards/t100011",
 "/cards/t100012",
 "/cards/t100042",
 "/cards/t10014681",
 "/cards/t10046373",
 "/cards/t10067927",
 "/cards/t10067934",
 "/cards/t10067948",
 "/cards/t100952",
 "/cards/t100958",
 "/cards/t10134140",
 "/cards/t11377384",
 "/cards/t11377385",
 "/cards/t11377401",
 "/cards/t11469315",
 "/cards/t11469352",
 "/cards/t11469353",
 "/cards/t11488341",
 "/cards/t13497894",
 "/cards/t13497919",
 "/cards/t135098",
 "/cards/t135116",
 "/cards/t1906859",
 "/cards/t2627013",
 "/cards/t2627022",
 "/cards/t2627025",
 "/cards/t2771934",
 "/cards/t3411906",
 "/cards/t4294026",
 "/cards/t4294030",
 "/cards/t4338701",
 "/cards/t4338702",
 "/cards/t4338717",
 "/cards/t4338745",
 "/cards/t6729887",
 "/cards/t7999626",
 "/cards/t7999650",
 "/cards/t7999719",
 "/chrome-extension",
 "/digimon-card-scanner",
 "/digital-card-binder",
 "/dragon-ball-super-card-scanner",
 "/flesh-and-blood-card-scanner",
 "/football-card-scanner",
 "/games/game-100000",
 "/games/game-71",
 "/games/pokemon",
 "/games/yugioh",
 "/graded-card-tracker",
 "/lorcana-card-scanner",
 "/mtg-card-scanner",
 "/one-piece-card-scanner",
 "/pokemon-card-scanner",
 "/prices",
 "/prices/most-valuable",
 "/privacy",
 "/sets/db-1397",
 "/sets/db-1512",
 "/sets/db-1550",
 "/sets/db-2156",
 "/sets/db-23405",
 "/sets/db-24241",
 "/sets/db-87",
 "/sets/db-t1192",
 "/sets/db-t273",
 "/sets/db-t347",
 "/sets/db-t466",
 "/sets/db-t568",
 "/sets/set-cdfc299a9ad0",
 "/soccer-card-scanner",
 "/star-wars-unlimited-card-scanner",
 "/terms"
];
const newCardPaths=['/cards/100219','/cards/t100959'];
const newSetPaths=['/sets/db-t322','/sets/db-t399','/sets/db-t582'];
const allowed=new Set(policy.rollout.allowedPaths);
const eligibleCard={seo:{kind:'card',eligible:true},dataAvailable:true};
const url=path=>new URL(path,'https://tcgcard.fun');
test('all historical positive URLs retain direct indexing scope or their approved owner redirect',()=>{
 assert.equal(historicalPositivePaths.length,140);
 const cards=historicalPositivePaths.filter(path=>path.startsWith('/cards/'));assert.equal(cards.length,82);
 for(const path of historicalPositivePaths){const target=redirectTarget(path);assert.ok(allowed.has(path)||target&&allowed.has(url(target).pathname),path);}
 const currentCards=[...allowed].filter(path=>path.startsWith('/cards/')).sort();
 assert.deepEqual(currentCards,[...cards,...newCardPaths].sort());
 assert.equal(currentCards.length,84);
 for(const path of newCardPaths)assert.equal(mayIndex(url(path),200,eligibleCard),true,path);
});
test('reference provenance is preserved while sixty unverified card exceptions pause without a zero-demand claim',()=>{
 assert.equal(manifest.guideCardIds.length,39);assert.equal(manifest.homeFeaturedCardIds.length,6);assert.equal(manifest.releaseCardIds.length,20);
 const referenceIds=new Set([...manifest.guideCardIds,...manifest.homeFeaturedCardIds,...manifest.releaseCardIds]);assert.equal(referenceIds.size,61);
 assert.equal(manifest.pausedByUnverifiedDemandCardIds.length,60);
 assert.equal(new Set(manifest.pausedByUnverifiedDemandCardIds).size,60);
 for(const id of manifest.pausedByUnverifiedDemandCardIds){assert.ok(referenceIds.has(id));assert.equal(allowed.has('/cards/'+id),false);assert.equal(mayIndex(url('/cards/'+id),200,eligibleCard),false);}
 assert.equal(allowed.has('/cards/717605'),true);
 assert.equal(manifest.pausedByUnverifiedDemandCardIds.includes('717605'),false);
 assert.equal(manifest.historicalDiscoverySnapshot.pausedDiscoveryCount,1047);
 assert.equal(manifest.pausedDiscoveryCount,undefined);
 assert.match(manifest.refinementEvidence.note,/not a measurement of zero search demand/);
});
test('temporary pausing retains a real card body and canonical and never substitutes a 404',()=>{
 const page=resolvePage(url('/cards/714372'));assert.equal(page.status,200);assert.match(page.html,/Charizard/);
 const html=publishHtml(page.html,url('/cards/714372'),page.status,page);
 assert.match(html,/<meta name="robots" content="noindex,follow">/);
 assert.match(html,/rel="canonical" href="https:\/\/tcgcard.fun\/cards\/714372"/);
 assert.equal(mayIndex(url('/cards/717605'),503,eligibleCard),false);
});
test('new positive sets are explicit owners and the seven-card discovery artifact matches its integrity metadata',async()=>{
 for(const path of newSetPaths){assert.ok(allowed.has(path),path);assert.ok(policy.newIndexPaths.includes(path),path);assert.equal(mayIndex(url(path),200,{dataAvailable:true}),true);assert.equal(mayIndex(url(path),404,{dataAvailable:false}),false);}
 assert.deepEqual(policy.verifiedDynamicSetPaths,newSetPaths);
 assert.deepEqual(manifest.newPositiveCardIds,['100219','t100959']);
 assert.equal(manifest.discoveryCount,7);assert.equal(manifest.shards.length,1);
 const shard=manifest.shards[0],body=await readFile(new URL('../content'+shard.path,import.meta.url));
 assert.equal(body.length,shard.bytes);assert.equal(createHash('sha256').update(body).digest('hex'),shard.sha256);
 const locations=[...body.toString('utf8').matchAll(/<loc>([^<]+)<\/loc>/g)].map(match=>match[1]);assert.equal(locations.length,7);assert.equal(new Set(locations).size,7);
 for(const location of locations){const path=new URL(location).pathname;assert.ok(allowed.has(path));assert.equal(mayIndex(new URL(location),200,eligibleCard),true);assert.equal(manifest.pausedByUnverifiedDemandCardIds.includes(path.slice(7)),false);}
 for(const path of newCardPaths)assert.ok(locations.includes(url(path).href));
 const siteLocations=[...publicSitemap().matchAll(/<loc>([^<]+)<\/loc>/g)].map(match=>match[1]);
 const baselineSiteCount=88;
 const addedGuides=[
  '/blog/delta-reign-etb',
  '/blog/aura-seeker-card-list',
  '/cyberpunk-tcg-card-list',
  '/sports-card-advent-calendar',
  '/blog/flowing-fists-card-list',
  '/blog/mickey-mantle-rookie-card-value',
  '/blog/one-piece-tcg-ban-list',
  '/blog/takumi-akabane-pokemon-cards',
  '/blog/pokemon-tcg-pocket-dual-fusion-card-list',
  '/blog/mega-rayquaza-ex-premium-tournament-collection',
  '/blog/mcdonalds-pokemon-collab-cards',
  '/blog/pokemon-valentines-box',
  '/blog/mega-x-mega-parade-card-list',
  '/blog/takumi-akabane-pokemon-card-list',
 ].map(path=>url(path).href);
 for(const guide of addedGuides)assert.ok(siteLocations.includes(guide),guide);
 assert.equal(siteLocations.filter(location=>!addedGuides.includes(location)).length,baselineSiteCount);
 assert.equal(siteLocations.length,baselineSiteCount+addedGuides.length);
 assert.equal(new Set([...siteLocations,...locations]).size,siteLocations.length+locations.length);
});
test('the fresh report stays separate from the preserved historical window and does not claim a release outcome',()=>{
 assert.equal(policy.rollout.performanceWindow.reportRows,145);assert.equal(policy.rollout.performanceWindow.latestDataDate,'2026-11-13');assert.equal(policy.rollout.performanceWindow.protectedPositiveCardUrls,84);
 assert.ok(policy.rollout.performanceWindowHistory.some(window=>window.start==='2026-10-12'&&window.end==='2026-11-11'&&window.protectedPositiveUrls===140));
 assert.match(policy.rollout.performanceWindow.note,/predates the new grading release/);
});


test('verified dynamic sets remain discoverable while unavailable sets are not advertised',()=>{
 const xml=publicSitemap();
 for(const path of policy.verifiedDynamicSetPaths){assert.match(path,/^\/sets\/db-t/);assert.ok(xml.includes('https://tcgcard.fun'+path));assert.ok(mayIndex(new URL('https://tcgcard.fun'+path),200,{dataAvailable:true}));}
 for(const path of policy.unavailableDiscoveryPaths.paths){assert.ok(!xml.includes('https://tcgcard.fun'+path));assert.equal(mayIndex(new URL('https://tcgcard.fun'+path),404),false);}
});
