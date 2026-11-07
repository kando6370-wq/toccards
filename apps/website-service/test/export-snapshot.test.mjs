import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {join} from 'node:path';import {tmpdir} from 'node:os';
import test from 'node:test';
const run=promisify(execFile),directory=await mkdtemp(join(tmpdir(),'cardscanfox-export-'));let changeVersion=false;
const server=createServer((req,res)=>{const url=new URL(req.url,'http://localhost');const second=url.searchParams.has('after');const items=Array.from({length:second?2:48},(_,i)=>({publicCardId:String(i+(second?48:0)).padStart(3,'0')}));res.setHeader('Content-Type','application/json');res.end(JSON.stringify({success:true,data:{items,hasMore:!second,nextCursor:second?null:'047'},meta:{datasetMode:'published-read-only',catalogVersion:changeVersion&&second?'changed':'v1',snapshotCapturedAt:'2026-11-07T00:00:00Z'}}));});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));test.after(async()=>{await new Promise(resolve=>server.close(resolve));await rm(directory,{recursive:true,force:true});});
const exportFile=join(directory,'snapshot.json');const script=new URL('../scripts/export-snapshot.mjs',import.meta.url).pathname;
const execute=budget=>run(process.execPath,[script,'--output='+exportFile,'--max-pages='+budget],{env:{SITE_DATA_EXPORT_URL:'http://127.0.0.1:'+server.address().port+'/site-api/v1/'}});
test('export follows true cursors and records traversal versus consistency honestly',async()=>{await execute(2);const result=JSON.parse(await readFile(exportFile,'utf8'));assert.equal(result.cardCount,50);assert.equal(new Set(result.cards.map(c=>c.publicCardId)).size,50);assert.equal(result.completeTraversal,true);assert.equal(result.consistentSnapshot,false);assert.equal(result.publicationApproved,false)});
test('export budget exhaustion and changing publications preserve the existing file',async()=>{await writeFile(exportFile,'keep existing');await assert.rejects(()=>execute(1),/Page budget exhausted/);assert.equal(await readFile(exportFile,'utf8'),'keep existing');changeVersion=true;try{await assert.rejects(()=>execute(2),/Published data changed/);assert.equal(await readFile(exportFile,'utf8'),'keep existing');}finally{changeVersion=false}});


test('NDJSON export streams complete records and a verified completion marker',async()=>{const output=join(directory,'catalog.ndjson');await run(process.execPath,[script,'--output='+output,'--max-pages=2','--format=ndjson'],{env:{SITE_DATA_EXPORT_URL:'http://127.0.0.1:'+server.address().port+'/site-api/v1/'}});const lines=(await readFile(output,'utf8')).trim().split('\n').map(JSON.parse);assert.equal(lines[0].recordType,'catalog');assert.equal(lines[0].mode,'published-export');assert.equal(lines.filter(r=>r.recordType==='card').length,50);assert.deepEqual(lines.at(-1),{recordType:'complete',catalogVersion:'v1',cardCount:50,completeTraversal:true})});
