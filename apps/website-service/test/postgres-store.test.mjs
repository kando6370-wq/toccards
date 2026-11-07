import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {PGlite} from '@electric-sql/pglite';
import {createPostgresStore,usd} from '../src/postgres-store.mjs';
const db=new PGlite();await db.exec(await readFile(new URL('./fixtures/catalog.sql',import.meta.url),'utf8'));
const queries=[];const store=createPostgresStore(async(sql,params)=>{queries.push(sql);return (await db.query(sql,params)).rows;});const ctx=await store.context();test.after(()=>db.close());
test('all-card browsing preserves string IDs, zero and missing prices with honest totals',async()=>{const r=await store.listCards(new URLSearchParams({pageSize:'2'}),ctx);assert.equal(r.total,null);assert.equal(r.returnedCount,2);assert.equal(r.hasMore,true);assert.equal(r.nextCursor,'002');assert.equal(r.items[0].card_ref,'001');assert.equal(r.items[0].price_usd,123.45);assert.equal(r.items[1].price_usd,0);const tail=await store.listCards(new URLSearchParams({after:r.nextCursor}),ctx);assert.deepEqual(tail.items.map(c=>c.card_ref),['003']);assert.equal(tail.items[0].price_usd,null)});
test('only active sources, active series and pointed published batches are exposed',async()=>{const c=await store.getCard('001',new URLSearchParams(),ctx);assert.deepEqual(c.references.map(r=>r.seriesId).sort(),['100','101','102']);assert.equal(c.reference.sourceLabel,'TCGplayer');assert.equal(c.reference.metric,'market');assert.equal(c.reference.priceAsOf,'2026-11-06')});
test('language and finish filters select the matching price before choosing its default',async()=>{const r=await store.listCards(new URLSearchParams({language:'Japanese',finish:'Holofoil'}),ctx);assert.equal(r.items.length,1);assert.equal(r.items[0].price_usd,20);assert.equal(r.items[0].reference.seriesId,'101');assert.equal(r.items[0].language,'Japanese')});
test('a graded selection stays separate and another card cannot request its series',async()=>{const graded=await store.getCard('001',new URLSearchParams({series:'102'}),ctx);assert.equal(graded.price_usd,999);assert.equal(graded.reference.grader,'PSA');assert.equal(graded.reference.gradeMin,10);await assert.rejects(()=>store.getCard('002',new URLSearchParams({series:'102'}),ctx),/not published for this card/)});
test('30-day history uses one series and excludes older or future observations',async()=>{const r=await store.trend('001',new URLSearchParams({series:'100'}),ctx);assert.equal(r.days,30);assert.equal(r.windowStart,'2026-10-08');assert.equal(r.windowEnd,'2026-11-06');assert.deepEqual(r.points.map(p=>p.date),['2026-10-08','2026-10-20','2026-11-05','2026-11-06']);assert.equal(r.points.at(-1).price,123.45);const jp=await store.trend('001',new URLSearchParams({series:'101'}),ctx);assert.equal(jp.points[0].price,19);await assert.rejects(()=>store.trend('001',new URLSearchParams({days:'90'}),ctx),/Only 30/);await assert.rejects(()=>store.trend('001',new URLSearchParams({series:'100',language:'Japanese'}),ctx),/dimensions/)});
test('unknown or disabled records are absent; missing history is not zero',async()=>{assert.equal(await store.getCard('999',new URLSearchParams(),ctx),null);assert.equal(await store.getCard('unknown',new URLSearchParams(),ctx),null);const r=await store.trend('003',new URLSearchParams(),ctx);assert.equal(r.status,'missing');assert.deepEqual(r.points,[])});
test('search values remain parameters and invalid pagination is rejected',async()=>{assert.deepEqual((await store.listCards(new URLSearchParams({q:"' OR 1=1 --"}),ctx)).items,[]);await assert.rejects(()=>store.listCards(new URLSearchParams({pageSize:'49'}),ctx),/Invalid page/);await assert.rejects(()=>store.listCards(new URLSearchParams({after:'002',sort:'price-desc'}),ctx),/Cursor/);assert.ok(queries.every(sql=>/^\s*(SELECT|WITH)\b/i.test(sql)))});
test('set source count never becomes verified catalog completeness and page aggregate uses the same context',async()=>{const r=await store.listSets(new URLSearchParams(),ctx);assert.equal(r.items[0].sourceReportedCount,999);assert.equal(r.items[0].catalogedCount,null);assert.equal(r.items[0].complete,false);const page=await store.pageData(new URLSearchParams({path:'/cards/001',series:'101'}),ctx);assert.equal(page.card.reference.seriesId,'101');assert.equal(page.trend.reference.seriesId,'101');assert.equal(page.catalogVersion,ctx.catalogVersion)});
test('unsafe numeric prices fail instead of losing precision',()=>{assert.equal(usd('0'),0);assert.throws(()=>usd('9007199254740992'),/Unsafe/)});

test('legacy decimal-string history is supported and malformed dates fail visibly',async()=>{await db.exec('BEGIN');try{await db.query("UPDATE price_history_month SET points=$1::jsonb WHERE series_id=100 AND month_start='2026-11-01'",[JSON.stringify([{date:'2026-11-04',price:'119.99'}])]);const trend=await store.trend('001',new URLSearchParams(),ctx);assert.equal(trend.points.find(p=>p.date==='2026-11-04').price,119.99);await db.query("UPDATE price_history_month SET points=$1::jsonb WHERE series_id=100 AND month_start='2026-11-01'",[JSON.stringify([{date:'2026-11-31',price:'119.99'}])]);await assert.rejects(()=>store.trend('001',new URLSearchParams(),ctx),/Invalid price history/)}finally{await db.exec('ROLLBACK')}});


test('published price ranges compare numeric micros and keep a real zero distinct from missing data',async()=>{
 const below=await store.listCards(new URLSearchParams({price:'under20'}),ctx);assert.deepEqual(below.items.map(c=>c.card_ref),['002']);
 const middle=await store.listCards(new URLSearchParams({price:'20to100',language:'Japanese'}),ctx);assert.deepEqual(middle.items.map(c=>c.card_ref),['001']);assert.equal(middle.items[0].price_usd,20);
 const above=await store.listCards(new URLSearchParams({price:'over100'}),ctx);assert.deepEqual(above.items.map(c=>c.card_ref),['001']);assert.equal(above.items[0].price_usd,123.45);
});

test('single-card prices use the existing active-card partial index at catalog scale',async()=>{
 await db.exec('BEGIN');
 try{
  await db.exec(`CREATE UNIQUE INDEX series_pk ON price_series(series_id);CREATE UNIQUE INDEX snapshot_pk ON price_current_snapshot(batch_id,series_id);
   CREATE INDEX active_card_prices ON price_series(card_ref,grader_code,grade_min_x10,grade_max_x10,condition_code,language_code,finish_code) INCLUDE(series_id,source_id,metric_code,currency_code) WHERE is_active;
   INSERT INTO price_series(series_id,source_id,source_record_id,metric_code,card_ref,currency_code,grader_code,is_active) SELECT 1000+i,1,'extra-'||i,'market','extra-'||i,'USD','RAW',true FROM generate_series(1,20000) i;
   INSERT INTO price_current_snapshot(batch_id,series_id,observed_on,amount_micros) SELECT 10,1000+i,'2026-11-07',1000000 FROM generate_series(1,20000) i;ANALYZE;`);
  let captured;const actual=createPostgresStore(async(sql,values)=>{if(sql.includes('FROM price_series s'))captured={sql,values};return (await db.query(sql,values)).rows});
  const meta=await actual.context();await actual.getCard('001',new URLSearchParams(),meta);
  const plan=(await db.query('EXPLAIN (FORMAT JSON,COSTS OFF) '+captured.sql,captured.values)).rows[0]['QUERY PLAN'][0].Plan;
  const indexes=[];function walk(p){if(p['Index Name'])indexes.push(p['Index Name']);for(const child of p.Plans??[])walk(child)}walk(plan);
  assert.ok(indexes.includes('active_card_prices'),JSON.stringify(plan));
 }finally{await db.exec('ROLLBACK')}
});


test('global sorting cannot scan the full production catalog; a selected set keeps exact prices and missing-last order',async()=>{
 for(const sort of ['name','recent','price-asc','price-desc'])await assert.rejects(()=>store.listCards(new URLSearchParams({sort}),ctx),/Choose a set/);
 const result=await store.listCards(new URLSearchParams({set:'db-A',sort:'price-asc'}),ctx);assert.deepEqual(result.items.map(c=>c.card_ref),['002','001','003']);assert.equal(result.items[0].price_usd,0);assert.equal(result.items.at(-1).price_usd,null);
});
