import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import certified from '../content/certified-grading-examples.json' with {type:'json'};
import guide from '../content/grading-price-guide-examples.json' with {type:'json'};
import {renderCertifiedExamples,renderGradePriceExamples} from '../src/certified-examples-template.mjs';
import {resolvePage} from '../src/render.mjs';

test('professional examples retain three different certified pairs and all six unmodified source images',async()=>{
 assert.deepEqual(certified.examples.map(x=>x.grade),[8,9,10]);assert.equal(certified.printing.year,2021);assert.equal(new Set(certified.examples.map(x=>x.certNumber)).size,3);
 const hashes=new Set();
 for(const example of certified.examples){
  assert.equal(example.aiAssessment,null);assert.equal(example.officialGraderNotes,null);assert.equal(example.notesPublished,false);assert.equal(example.photoType,'post_encapsulation_scan');
  assert.equal(new URL(example.sourceUrl).pathname,`/cert/${example.certNumber}/psa`);
  for(const face of ['front','back']){
   const meta=example.imageMetadata[face],path=example[face+'Image'];assert.match(path,new RegExp('psa-'+example.certNumber+'-'+face+'\\.jpg$'));assert.equal(meta.sourcePage,example.sourceUrl);assert.equal(meta.transformation,'none');
   const bytes=await readFile(new URL('../public'+path,import.meta.url));assert.equal(bytes.length,meta.bytes);const hash=createHash('sha256').update(bytes).digest('hex');assert.equal(hash,meta.sha256);hashes.add(hash);
  }
 }
 assert.equal(hashes.size,6);
});
test('official grade references and guide estimates stay distinct from AI results, catalog identity and recorded sales',()=>{
 const examples=renderCertifiedExamples(certified),prices=renderGradePriceExamples(guide);
 assert.match(examples,/after encapsulation/);assert.match(examples,/not CardScanFox predictions/);assert.match(examples,/has not published individual grader notes/);
 assert.equal(guide.metric,'guide_estimate');assert.equal(guide.sourceUpdatedAt,null);assert.equal(guide.catalogMapping,null);assert.ok(guide.examples.every(x=>x.year===1999&&x.grader==='PSA'&&x.variation==='Shadowless'));
 assert.match(prices,/guide estimates rather than individual sale records/);assert.match(prices,/separate from the 2021/);assert.doesNotMatch(prices,/2026 catalog card.*\$|current market sale/);
 assert.throws(()=>renderGradePriceExamples({...guide,metric:'sold'}));assert.throws(()=>renderGradePriceExamples({...guide,examples:guide.examples.map((x,i)=>i?x:{...x,grader:'CGC'})}));assert.throws(()=>renderCertifiedExamples({...certified,examples:certified.examples.map((x,i)=>i?x:{...x,sourceUrl:'https://example.com/fake-cert'})}));assert.throws(()=>renderCertifiedExamples({...certified,examples:certified.examples.map((x,i)=>i?x:{...x,aiAssessment:{grade:8}})}));
});
test('the grading owner server-renders real professional references, complete same-company guide prices and the same-page data lookup',()=>{
 const html=resolvePage(new URL('https://tcgcard.fun/ai-card-grading')).html;
 for(const example of certified.examples)assert.ok(html.includes(example.sourceUrl));
 for(const item of guide.examples)assert.ok(html.includes(item.name));
 assert.match(html,/data-grading-price-lookup/);assert.match(html,/data-photo-centering/);assert.match(html,/card-centering\.css/);assert.match(html,/Beckett Standard listed \$34\.95/);
});
