import assert from 'node:assert/strict';
import test from 'node:test';
import {snapshotKey,refreshWebsiteSnapshot,readWebsiteSnapshot} from '../src/site-snapshots.mjs';
function cache(){const map=new Map();return {map,get:async key=>map.has(key)?JSON.parse(map.get(key)):null,put:async(key,value)=>{map.set(key,value)}};}
const now=Date.parse('2026-11-07T12:00:00Z');
const board=kind=>({kind,items:[{publicCardId:'100',rank:1}],eligibleCount:1});
const metadata={catalogVersion:'published-test',anchorDate:'2026-11-07'};
test('only a complete periodic refresh replaces the previous public rankings and counts',async()=>{
 const kv=cache();let budget;
 const read=async(_url,operation,options)=>{budget=options;return operation({context:async()=>metadata,directoryCounts:async()=>({total:3,byGame:{1:3},bySet:{A:3}}),rankings:async kind=>board(kind)})};
 const first=await refreshWebsiteSnapshot(kv,read,'postgres://test-only',now);assert.equal(first.updated,true);assert.equal(budget.statementTimeoutMs,30000);assert.equal(budget.operationBudgetMs,110000);
 const stored=await readWebsiteSnapshot(kv);assert.equal(stored.counts.total,3);assert.equal(stored.boards.gainers.items.length,1);assert.equal(stored.generatedAt,'2026-11-07T12:00:00.000Z');
 let called=0;const skip=await refreshWebsiteSnapshot(kv,async()=>{called++;throw Error('must not read')},'postgres://test-only',now+1000);assert.equal(skip.updated,false);assert.equal(called,0);
 const previous=kv.map.get(snapshotKey);await assert.rejects(()=>refreshWebsiteSnapshot(kv,async()=>{throw Error('database budget')},'postgres://test-only',now+3600001),/database budget/);assert.equal(kv.map.get(snapshotKey),previous);
 const retry=await refreshWebsiteSnapshot(kv,async()=>{throw Error('must not retry')},'postgres://test-only',now+3601000);assert.equal(retry.updated,false);assert.ok(retry.retryAfter>now+3601000);
});
test('partial, malformed and absent snapshot objects are not published as rankings',async()=>{
 const kv=cache();assert.equal(await readWebsiteSnapshot(kv),null);kv.map.set(snapshotKey,JSON.stringify({schemaVersion:1,boards:{gainers:{items:[]}}}));assert.equal(await readWebsiteSnapshot(kv),null);
});
