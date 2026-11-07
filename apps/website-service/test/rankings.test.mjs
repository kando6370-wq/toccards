import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import {PGlite} from '@electric-sql/pglite';
import {createPostgresStore} from '../src/postgres-store.mjs';
import {refreshWebsiteSnapshot,snapshotKey} from '../src/site-snapshots.mjs';
const db=new PGlite();await db.exec(await readFile(new URL('./fixtures/catalog.sql',import.meta.url),'utf8'));
await db.exec(`UPDATE price_current_snapshot SET baseline_7d_on='2026-10-30',baseline_7d_amount_micros=100000000,change_7d_percent=23.45 WHERE series_id=100;
 INSERT INTO cards_all(product_id,game_id,game,set_id,set_name,set_code,number,name,product_type_name,has_image) VALUES
 ('004',1,'Pokemon','A','Test Set','TEST','004/010','High Card','Cards',2),('005',1,'Pokemon','A','Test Set','TEST','005/010','Rising Card','Cards',2),('006',1,'Pokemon','A','Test Set','TEST','006/010','Sealed box','Booster Boxes',2),('007',1,'Pokemon','A','Test Set','TEST','','No number','Cards',2),('008',1,'Pokemon','A','Test Set','TEST','008/010','Old price','Cards',2),('009',1,'Pokemon','A','Test Set','TEST','009/010','Zero baseline','Cards',2),('010',1,'Pokemon','A','Test Set','TEST','010/010','Wrong comparison date','Cards',2),('011',1,'Pokemon','A','Test Set','TEST','011/010','No image','Cards',1);
 INSERT INTO price_series(series_id,source_id,source_record_id,metric_code,card_ref,currency_code,condition_code,condition_name,language_code,language_name,finish_code,finish_name,grader_code,is_active) VALUES
 (400,1,'high','market','004','USD','NM','Near Mint','EN','English','N','Normal','RAW',true),
 (500,1,'gain-en','market','005','USD','NM','Near Mint','EN','English','N','Normal','RAW',true),
 (501,1,'gain-jp','market','005','USD','NM','Near Mint','JP','Japanese','H','Holofoil','RAW',true),
 (600,1,'sealed','market','006','USD','NM','Near Mint','EN','English','N','Normal','RAW',true),
 (700,1,'no-number','market','007','USD','NM','Near Mint','EN','English','N','Normal','RAW',true),
 (800,1,'stale','market','008','USD','NM','Near Mint','EN','English','N','Normal','RAW',true),
 (900,1,'baseline-zero','market','009','USD','NM','Near Mint','EN','English','N','Normal','RAW',true),
 (1000,1,'wrong-date','market','010','USD','NM','Near Mint','EN','English','N','Normal','RAW',true),
 (1100,1,'no-image','market','011','USD','NM','Near Mint','EN','English','N','Normal','RAW',true);
 INSERT INTO price_current_snapshot(batch_id,series_id,observed_on,amount_micros,baseline_7d_on,baseline_7d_amount_micros,change_7d_percent) VALUES
 (10,400,'2026-11-06',500000000,'2026-10-30',100000000,400),
 (10,500,'2026-11-06',200000000,'2026-10-30',1000000,19900),
 (10,501,'2026-11-06',201000000,'2026-10-30',1000000,20000),
 (10,600,'2026-11-06',999999000000,'2026-10-30',1,999999),
 (10,700,'2026-11-06',999999000000,'2026-10-30',1,999999),
 (10,800,'2026-10-01',999999000000,'2026-09-24',1,999999),
 (10,900,'2026-11-06',500000000000,'2026-10-30',0,NULL),
 (10,1000,'2026-11-06',1000000000,'2026-10-29',1,999999),
 (10,1100,'2026-11-06',999999000000,'2026-10-30',1,999999);`);
const store=createPostgresStore(async(sql,params)=>(await db.query(sql,params)).rows);const meta=await store.context();test.after(()=>db.close());
const values=new Map(),cache={get:async key=>values.has(key)?JSON.parse(values.get(key)):null,put:async(key,value)=>values.set(key,value)};
await refreshWebsiteSnapshot(cache,async(_url,operation)=>operation(store),'postgres://test-only',Date.parse('2026-11-07T12:00:00Z'));
const built=JSON.parse(values.get(snapshotKey));
test('weekly gainers compare the same raw price series exactly seven days apart and keep one printing record',async()=>{
 const result=built.boards.gainers;assert.deepEqual(result.items.map(c=>c.publicCardId),['005','004','001']);assert.equal(result.items[0].reference.seriesId,'501');assert.equal(result.items[0].language,'Japanese');assert.equal(result.items[0].baseline_7d_price,1);assert.equal(result.items[0].price_usd,201);assert.equal(result.items[0].price_change_7d_percent,20000);
});
test('highest-price ranking excludes slabs, sealed products, stale prices, missing identities and missing images',async()=>{
 const result=built.boards.highest;assert.deepEqual(result.items.map(c=>c.publicCardId),['009','010','004','005','001']);assert.equal(result.items[0].price_usd,500000);assert.ok(result.items.every(c=>c.reference.grader==='RAW'));assert.equal(new Set(result.items.map(c=>c.publicCardId)).size,result.items.length);
});
test('counts and cursor pagination describe the displayed single-card universe, in both directions',async()=>{
 const counts=built.counts;assert.equal(counts.total,9);const context={...meta,counts,countedAt:'2026-11-07T00:00:00Z'};
 const first=await store.listCards(new URLSearchParams({pageSize:'2'}),context);assert.equal(first.total,9);assert.equal(first.hasPrevious,false);assert.equal(first.nextCursor,'002');
 const second=await store.listCards(new URLSearchParams({pageSize:'2',page:'2',after:first.nextCursor}),context);assert.deepEqual(second.items.map(c=>c.publicCardId),['003','004']);assert.equal(second.page,2);assert.equal(second.previousCursor,'003');
 const previous=await store.listCards(new URLSearchParams({pageSize:'2',page:'1',before:second.previousCursor}),context);assert.deepEqual(previous.items.map(c=>c.publicCardId),['001','002']);assert.equal(previous.hasPrevious,false);assert.equal(previous.hasMore,true);
 await assert.rejects(()=>store.listCards(new URLSearchParams({after:'002',before:'003'}),context),/only one/);
 const filtered=await store.listCards(new URLSearchParams({q:'Alpha'}),context);assert.equal(filtered.total,null);
});
