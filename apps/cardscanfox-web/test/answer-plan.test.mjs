import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {parse} from 'parse5';
import {createRenderer,legacyPages} from '../src/render.mjs';
import {cardMetadata} from '@kando/website-content/seo';
const walk=(n,f)=>{f(n);for(const c of n.childNodes??[])walk(c,f)};
const attr=(n,k)=>n.attrs?.find(a=>a.name===k)?.value;
const text=n=>n.nodeName==='#text'?n.value:(n.childNodes??[]).map(text).join('');
const normalized=s=>s.replace(/\s+/g,' ').trim();
function faqPairs(html){const doc=parse(html),visible=[],structured=[];walk(doc,n=>{if(n.tagName==='details'&&(attr(n,'class')??'').split(/\s+/).includes('faq-item')){const summary=n.childNodes.find(c=>c.tagName==='summary');visible.push({q:normalized(text(summary)),a:normalized(n.childNodes.filter(c=>c!==summary).map(text).join(''))});}if(n.tagName==='script'&&attr(n,'type')==='application/ld+json'){const d=JSON.parse(text(n));if(d['@type']==='FAQPage')structured.push(...d.mainEntity.map(q=>({q:q.name,a:q.acceptedAnswer.text})));}});return {visible,structured};}
test('website answers separate text lookup, iPhone scanning, Android availability and local bookmarks',()=>{
 const renderer=createRenderer({liveSite:true});const home=renderer.resolvePage(new URL('https://tcgcard.fun/')).html;
 assert.match(home,/Look up TCG and sports cards by name/);assert.match(home,/no photo upload scanner/);assert.match(home,/Android is coming soon/);assert.match(home,/Chrome recognizer/);assert.doesNotMatch(home,/Card AI supports Pokemon[^<]*Dragon Ball Super|Card AI covers basketball, football and soccer/);
 const tracker=renderer.resolvePage(new URL('https://tcgcard.fun/card-collection-tracker')).html;assert.match(tracker,/Website Saved references are browser bookmarks/);
 const price=renderer.resolvePage(new URL('https://tcgcard.fun/card-price-checker')).html;assert.match(price,/website’s text lookup/);assert.doesNotMatch(price,/To check your own card, use the Card AI app/);
 const identifier=renderer.resolvePage(new URL('https://tcgcard.fun/card-identifier')).html;assert.doesNotMatch(identifier,/same identifier covers[^<]*Dragon Ball Super/);
});
test('category coverage corrections do not promise unsupported languages, releases or whole-box scanning',()=>{
 const renderer=createRenderer();for(const path of ['/dragon-ball-super-card-scanner','/football-card-scanner']){const h=renderer.resolvePage(new URL(path,'https://tcgcard.fun')).html;assert.match(h,/Coverage is not confirmed for this category/);assert.match(h,/do not save another printing|does not confirm football coverage/);assert.doesNotMatch(h,/Yes\. You can look up dragon ball super|Bulk scanning lets you work through a stack/);}
});
test('numbered card lists keep all official rows and historical price snapshot dates',()=>{
 for(const [path,count]of [['/blog/ascended-heroes-card-list',295],['/blog/chaos-rising-card-list',122],['/blog/phantasmal-flames-card-list',130]]){const p=legacyPages.find(p=>p.path===path);assert.equal((p.bodyHtml.match(/data-card-row/g)??[]).length,count);assert.match(p.bodyHtml,/2026-11-05/);assert.match(p.bodyHtml,/current catalog record/);}
});
test('visible legacy and authored questions are the source of every emitted FAQ answer',()=>{
 const renderer=createRenderer({liveSite:true});for(const path of ['/','/prices','/card-identifier','/card-price-checker','/card-collection-tracker','/dragon-ball-super-card-scanner','/football-card-scanner','/blog/dungeon-crawler-carl-trading-cards']){const html=renderer.resolvePage(new URL(path,'https://tcgcard.fun')).html;const {visible,structured}=faqPairs(html);assert.ok(structured.length,path);for(const q of structured)assert.ok(visible.some(v=>v.q===q.q&&v.a===q.a),path+' '+q.q);}
});
const mew={publicCardId:'717605',card_ref:'717605',name:'Mew ex - 152/128',game:'Pokemon',gameSlug:'pokemon',set_name:'ME: 30th Celebration',set_code:'30C',publicSetId:'set-cdfc299a9ad0',card_number:'152/128',language:'English',finish:'Holofoil',image_url:'https://image.tcgcard.fun/cards/717605.jpg',price_usd:null,reference:null,references:[]};
test('Mew 152/128 is distinguished from 151 and Bubble Mew without inventing a price',async()=>{
 const renderer=createRenderer({catalog:{mode:'published-read-only',catalogVersion:'test',sourceUrl:'https://catalog.example'},cards:[mew],getCard:()=>mew,getTrend:()=>({points:[]}),getSet:()=>null});const h=renderer.resolvePage(new URL('https://tcgcard.fun/cards/717605')).html;
 for(const number of ['152/128','151/165','232/091'])assert.ok(h.includes(number));assert.match(h,/Price unavailable/);assert.doesNotMatch(h,/<title>[^<]*Price &amp;/);assert.match(cardMetadata(mew).title,/30th Celebration/);
 const {visible,structured}=faqPairs(h);assert.equal(structured.length,2);for(const q of structured)assert.ok(visible.some(v=>v.q===q.q&&v.a===q.a));
 const article=await readFile(new URL('../content/articles/mew-ex-card-values.md',import.meta.url),'utf8');assert.match(article,/152\/128.*717605/);assert.match(article,/30th Celebration/);
});
test('Manga set is a soccer record, and catalog count does not claim official checklist completion',()=>{
 const set={id:'db-t1192',name:'2026 Panini Prizm FIFA Manga',code:'MANGA',gameSlug:'soccer'};const renderer=createRenderer({sets:[set],getSet:()=>set,queryCards:()=>({items:[],page:1,pageSize:24,total:0,hasMore:false})});const h=renderer.resolvePage(new URL('https://tcgcard.fun/sets/db-t1192')).html;assert.match(h,/FIFA is soccer/);assert.match(h,/not proof of a complete issuer checklist/);const {structured}=faqPairs(h);assert.equal(structured.length,1);
});
