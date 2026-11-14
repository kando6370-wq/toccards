import assert from 'node:assert/strict';
import test from 'node:test';
import {parse} from 'parse5';
import {createRenderer, legacyPages} from '../src/render.mjs';
import answerFaqs from '../content/answer-faqs.json' with {type:'json'};

const walk=(node,fn)=>{fn(node);for(const child of node.childNodes??[])walk(child,fn);};
const text=node=>['script','style','noscript'].includes(node.tagName)?'':node.nodeName==='#text'?node.value:(node.childNodes??[]).map(text).join('');
const normalize=value=>value.replace(/\s+/g,' ').trim();
const renderer=createRenderer({liveSite:true});
const render=path=>renderer.resolvePage(new URL(path,'https://tcgcard.fun'));
const content=html=>normalize(text(parse(html)));

test('free allowance and image queue answers stay consistent across discovery, product, download and help pages',()=>{
 assert.ok(Array.isArray(answerFaqs['/help']),'Public answers must explain the free allowance and image queue.');
 const [free,queue]=answerFaqs['/help'];
 assert.match(free.answer,/10 successful scans/);
 assert.match(free.answer,/no daily or monthly reset/);
 assert.match(free.answer,/Failed scans and no-match results do not consume/);
 assert.match(queue.answer,/up to 10 separate/);
 assert.match(queue.answer,/remaining free scans are separate limits/);
 assert.match(queue.answer,/does not scan an entire binder page/);
 for(const path of ['/','/app','/download','/help']){
  const result=render(path);assert.equal(result.status,200,path);
  const body=content(result.html);
  for(const faq of [free,queue])assert.ok(body.includes(faq.answer),path+' '+faq.question);
 }
 const help=content(render('/help').html);
 assert.match(help,/account deletion page/);
 assert.match(help,/Do not save a candidate that does not match your card/);
 assert.match(content(render('/download').html),/Android.*Coming soon/);
});

test('all affected tool and comparison FAQs match visible answers',()=>{
 const paths=['/','/app','/help','/download',...legacyPages.filter(page=>['feature','comparison'].includes(page.type)).map(page=>page.path)];
 for(const path of paths){
  const html=render(path).html,body=content(html),questions=[];
  walk(parse(html),node=>{
   if(node.tagName!=='script'||!node.attrs?.some(attr=>attr.name==='type'&&attr.value==='application/ld+json'))return;
   const value=JSON.parse(node.childNodes.map(child=>child.value??'').join(''));
   if(value['@type']==='FAQPage')questions.push(...value.mainEntity);
  });
  assert.ok(questions.length,path);
  for(const question of questions){
   assert.ok(body.includes(normalize(question.name)),path+' question: '+question.name);
   assert.ok(body.includes(normalize(question.acceptedAnswer.text)),path+' answer: '+question.name);
  }
 }
});

test('screenshots and holdings descriptions do not promise sold listings or live values for every owned card',()=>{
 for(const path of ['/',...legacyPages.filter(page=>['feature','comparison'].includes(page.type)).map(page=>page.path)]){
  const body=content(render(path).html);
  assert.doesNotMatch(body,/sold-listing availability|collection tracker with a live total|tracks the total value of everything you own/i,path);
 }
 for(const path of ['/football-card-scanner','/dragon-ball-super-card-scanner']){
  const body=content(render(path).html);
  assert.match(body,/Coverage is not confirmed for this category/,path);
 }
});
