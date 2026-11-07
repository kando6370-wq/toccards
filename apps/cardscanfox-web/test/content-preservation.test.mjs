import assert from 'node:assert/strict';
import {readFile,access} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import test from 'node:test';
import {parse,parseFragment} from 'parse5';
import {legacyPages,resolvePage,allStaticPaths} from '../src/render.mjs';
const visit=(n,f)=>{f(n);for(const c of n.childNodes??[])visit(c,f)};
const find=(n,f)=>{let out;visit(n,x=>{if(!out&&f(x))out=x});return out};
const text=n=>['script','style','noscript'].includes(n.tagName)?'':n.nodeName==='#text'?n.value:(n.childNodes??[]).map(text).join('');
const norm=s=>s.replace(/\s+/g,' ').trim();
const attr=(n,k)=>n.attrs?.find(a=>a.name===k)?.value;
const original=new URL('../content/legacy/',import.meta.url);
const baseline=JSON.parse(await readFile(new URL('source-baseline.json',original),'utf8'));

test('all 46 protected live URLs render their full original visible content, not homepage fallbacks',async()=>{
 assert.equal(legacyPages.length,46);assert.equal(new Set(legacyPages.map(p=>p.path)).size,46);
 for(const source of baseline.pages){
  const originalHtml=await readFile(new URL(source.file,original),'utf8');assert.equal(createHash('sha256').update(originalHtml).digest('hex'),source.htmlSha256,source.path);
  const oldMain=find(parse(originalHtml),n=>n.tagName==='main');const result=resolvePage(new URL(source.path,'https://tcgcard.fun'));assert.equal(result.status,200,source.path);
  const newDoc=parse(result.html),newMain=find(newDoc,n=>n.tagName==='main');assert.ok(norm(text(newMain)).includes(norm(text(oldMain))),`Missing visible content at ${source.path}`);
  const count=(node,tag)=>{let n=0;visit(node,x=>{if(x.tagName===tag)n++});return n};assert.ok(count(newMain,'tr')>=count(oldMain,'tr'),`Missing table rows at ${source.path}`);
  const record=legacyPages.find(p=>p.path===source.path);assert.ok(allStaticPaths.includes(source.path));assert.equal(record.protected,true);
  if(source.path!=='/')assert.equal(norm(text(find(newMain,n=>n.tagName==='h1'))),norm(text(find(oldMain,n=>n.tagName==='h1'))),source.path);
 }
});
test('all protected body links retain their original destinations after same-origin normalization',async()=>{
 for(const page of legacyPages){const source=baseline.pages.find(p=>p.path===page.path);const old=parse(await readFile(new URL(source.file,original),'utf8')),main=find(old,n=>n.tagName==='main');const required=[];visit(main,n=>{if(n.tagName==='a'&&attr(n,'href')&&!attr(n,'href').startsWith('javascript:'))required.push(new URL(attr(n,'href'),'https://tcgcard.fun'+page.path).href)});const imported=parseFragment(page.bodyHtml),actual=[];visit(imported,n=>{if(n.tagName==='a'&&attr(n,'href'))actual.push(new URL(attr(n,'href'),'https://tcgcard.fun'+page.path).href)});for(const target of required)assert.ok(actual.includes(target),page.path+' missing '+target);}
});
test('imported local images exist in the independent app and all visible source text is retained',async()=>{
 for(const page of legacyPages){assert.ok(page.bodyHtml.length>100);assert.doesNotMatch(page.bodyHtml,/<script\b|\son(?:click|error|load)=/i);for(const image of page.images){if(image.src?.startsWith('/'))await access(new URL('../public'+image.src,import.meta.url));}}
});
test('original card-list rows and filtering data survive migration',()=>{
 for(const path of ['/blog/ascended-heroes-card-list','/blog/chaos-rising-card-list','/blog/phantasmal-flames-card-list']){const page=legacyPages.find(p=>p.path===path);assert.match(page.bodyHtml,/class="card-list-controls"/);assert.match(page.bodyHtml,/data-card-row/);assert.match(page.bodyHtml,/data-priced="(?:true|false)"/);assert.match(page.bodyHtml,/card-list-query/);}
});
test('unknown URLs return real 404 content and are never silently rendered as the homepage',()=>{const r=resolvePage(new URL('/not-a-real-article','https://tcgcard.fun'));assert.equal(r.status,404);assert.match(r.html,/That page is not here/);assert.doesNotMatch(r.html,/id="homeView"/)});
test('new card details retain current price and only a 30-day summary with the app action',()=>{const r=resolvePage(new URL('/cards/714372','https://tcgcard.fun'));assert.match(r.html,/\$145\.78/);assert.match(r.html,/Last 30 days/);assert.match(r.html,/Turn price research into a collection/);assert.match(r.html,/Download Card AI/);assert.match(r.html,/apps\.apple\.com/);assert.doesNotMatch(r.html,/data-days=|historyDataTable|chartTooltip|90 days/)});
test('missing data stays missing rather than becoming a zero price or synthetic chart',()=>{const r=resolvePage(new URL('/cards/722598','https://tcgcard.fun'));assert.match(r.html,/Price unavailable/);assert.match(r.html,/No matching trend/);assert.doesNotMatch(r.html,/\$0\.00/)});
test('the 20 original blog articles and 3 original comparison pages keep their canonical paths',()=>{assert.equal(legacyPages.filter(p=>p.type==='article').length,20);assert.equal(legacyPages.filter(p=>p.type==='comparison').length,3);for(const p of legacyPages.filter(p=>p.type==='article'||p.type==='comparison')){const html=resolvePage(new URL(p.path,'https://tcgcard.fun')).html;assert.match(html,new RegExp('rel="canonical" href="https://tcgcard\\.fun'+p.path.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'"'));}});
