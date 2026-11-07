import assert from 'node:assert/strict';
import test from 'node:test';
import {snapshotKey,refreshJobKey,createLeaderAccumulator,refreshWebsiteSnapshot,readWebsiteSnapshot} from '../src/site-snapshots.mjs';
function cache(){const map=new Map();return {map,get:async key=>map.has(key)?JSON.parse(map.get(key)):null,put:async(key,value)=>{map.set(key,value)}};}
const now=Date.parse('2026-11-07T12:00:00Z');
const board=kind=>({kind,items:[{publicCardId:'100',rank:1}],eligibleCount:1});
const metadata={catalogVersion:'published-test',anchorDate:'2026-11-07',games:[{id:'1',slug:'pokemon',name:'Pokemon'}],publications:[{batch_id:'10',source_id:'1'}]};
const sampleStore={context:async()=>metadata,directoryChunk:async after=>['100','101','102'].filter(id=>id>after).map(product_id=>({product_id,game_id:'1',set_id:'A',product_type_name:'Cards',has_image:2})),priceChunk:async()=>({cursor:'1',scanned:1,items:[{card_ref:'100',series_id:'1',amount_micros:'1000000',observed_on:'2026-11-07',baseline_7d_on:'2026-10-31',baseline_7d_amount_micros:'500000',change_7d_percent:'100'}]}),hydrateRanking:async rows=>rows.map((r,i)=>({publicCardId:r.card_ref,rank:i+1}))};
test('only a complete periodic refresh replaces the previous public rankings and counts',async()=>{
 const kv=cache();let budget;
 const read=async(_url,operation,options)=>{budget=options;return operation(sampleStore)};
 const first=await refreshWebsiteSnapshot(kv,read,'postgres://test-only',now);assert.equal(first.updated,true);assert.equal(budget.statementTimeoutMs,1500);assert.equal(budget.operationBudgetMs,45000);
 const stored=await readWebsiteSnapshot(kv);assert.equal(stored.counts.total,3);assert.equal(stored.boards.gainers.items.length,1);assert.equal(stored.generatedAt,'2026-11-07T12:00:00.000Z');
 let called=0;const skip=await refreshWebsiteSnapshot(kv,async()=>{called++;throw Error('must not read')},'postgres://test-only',now+1000);assert.equal(skip.updated,false);assert.equal(called,0);
 const previous=kv.map.get(snapshotKey);await assert.rejects(()=>refreshWebsiteSnapshot(kv,async()=>{throw Error('database budget')},'postgres://test-only',now+3600001),/database budget/);assert.equal(kv.map.get(snapshotKey),previous);
 const retry=await refreshWebsiteSnapshot(kv,async()=>{throw Error('must not retry')},'postgres://test-only',now+3601000);assert.equal(retry.updated,false);assert.ok(retry.retryAfter>now+3601000);
});
test('partial, malformed and absent snapshot objects are not published as rankings',async()=>{
 const kv=cache();assert.equal(await readWebsiteSnapshot(kv),null);kv.map.set(snapshotKey,JSON.stringify({schemaVersion:1,boards:{gainers:{items:[]}}}));assert.equal(await readWebsiteSnapshot(kv),null);
});


test('a checkpoint can resume its existing cursor and a publication change restarts the traversal',async()=>{
 const kv=cache(),read=async(_url,operation)=>operation(sampleStore);
 const pending=await refreshWebsiteSnapshot(kv,read,'postgres://test-only',now,0);assert.equal(pending.phase,'counts');assert.equal(await readWebsiteSnapshot(kv),null);
 const state=JSON.parse(kv.map.get(refreshJobKey));state.cardCursor='101';state.cardsScanned=2;state.counts={total:2,byGame:{1:2},bySet:{A:2}};kv.map.set(refreshJobKey,JSON.stringify(state));
 await refreshWebsiteSnapshot(kv,read,'postgres://test-only',now+60000);assert.equal((await readWebsiteSnapshot(kv)).counts.total,3);
 kv.map.delete(snapshotKey);state.catalogVersion='outdated-publication';state.cardCursor='zzz';state.counts.total=999;kv.map.set(refreshJobKey,JSON.stringify(state));await refreshWebsiteSnapshot(kv,read,'postgres://test-only',now+120000);assert.equal((await readWebsiteSnapshot(kv)).counts.total,3);
});
test('streaming Top 100 keeps the strongest series per card even when its series arrive far apart',()=>{
 const high=createLeaderAccumulator([],'highest'),gains=createLeaderAccumulator([],'gainers');
 for(let i=1;i<=300;i++){const row={card_ref:String(i).padStart(3,'0'),series_id:String(i),amount:i,gain:301-i,observed_on:'2026-11-07'};high.add(row);gains.add(row);}
 high.add({card_ref:'001',series_id:'1001',amount:1000,gain:0,observed_on:'2026-11-07'});high.add({card_ref:'001',series_id:'1002',amount:1,gain:0,observed_on:'2026-11-07'});
 high.add({card_ref:'150',series_id:'1150',amount:1100,gain:0,observed_on:'2026-11-07'});high.add({card_ref:'151',series_id:'1151',amount:1100,gain:0,observed_on:'2026-11-07'});
 assert.deepEqual(high.rows.slice(0,3).map(c=>c.card_ref),['150','151','001']);assert.equal(high.rows.at(-1).card_ref,'204');assert.equal(high.rows.length,100);assert.equal(new Set(high.rows.map(c=>c.card_ref)).size,100);
 gains.add({card_ref:'300',series_id:'1300',amount:1,gain:10000,observed_on:'2026-11-07'});gains.add({card_ref:'050',series_id:'1050',amount:1,gain:9999,observed_on:'2026-11-07'});
 assert.deepEqual(gains.rows.slice(0,2).map(c=>c.card_ref),['300','050']);assert.equal(gains.rows.at(-1).card_ref,'099');assert.equal(gains.rows.length,100);
});
