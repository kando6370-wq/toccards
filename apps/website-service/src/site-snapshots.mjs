export const snapshotKey='website:market-snapshot:v1';
export const snapshotSchema=1;
export const refreshJobKey='website:refresh-job:v2';
const retryKey='website:snapshot-retry:v2';
const intervalMs=60*60*1000;
export async function readWebsiteSnapshot(cache){
 if(!cache)return null;
 const value=await cache.get(snapshotKey,{type:'json',cacheTtl:60});
 return value?.schemaVersion===snapshotSchema&&Array.isArray(value.boards?.gainers?.items)&&Array.isArray(value.boards?.highest?.items)?value:null;
}
export async function readRefreshStatus(cache){
 if(!cache)return null;
 const [job,retry]=await Promise.all([cache.get(refreshJobKey,{type:'json',cacheTtl:60}),cache.get(retryKey,{type:'json',cacheTtl:60})]);
 return {phase:job?.phase??'waiting',cardsScanned:job?.cardsScanned??0,pricesScanned:job?.pricesScanned??0,updatedAt:job?.updatedAt??null,nextAttemptAt:retry?.nextAttemptAt??null,failedStage:retry?.stage??null,databaseCode:retry?.databaseCode??null};
}
export function compareLeader(a,b,kind){
 const metric=kind==='gainers'?'gain':'amount';
 return b[metric]-a[metric]||b.amount-a.amount||b.observed_on.localeCompare(a.observed_on)||(a.card_ref<b.card_ref?-1:a.card_ref>b.card_ref?1:0)||(BigInt(a.series_id)<BigInt(b.series_id)?-1:BigInt(a.series_id)>BigInt(b.series_id)?1:0);
}
export function createLeaderAccumulator(items,kind){
 const rows=[...items],byCard=new Map(rows.map(row=>[row.card_ref,row]));
 return {rows,add(row){
  const old=byCard.get(row.card_ref);
  if(old&&compareLeader(row,old,kind)>=0)return;
  if(!old&&rows.length===100&&compareLeader(row,rows.at(-1),kind)>=0)return;
  if(old)rows.splice(rows.indexOf(old),1);
  rows.push(row);byCard.set(row.card_ref,row);rows.sort((a,b)=>compareLeader(a,b,kind));
  if(rows.length>100){const removed=rows.pop();byCard.delete(removed.card_ref);}
 }};
}
function candidate(row){
 const amount=Number(row.amount_micros);
 if(!Number.isSafeInteger(amount)||amount<=0)throw new Error('Invalid ranking amount.');
 const gain=row.change_7d_percent===null?null:Number(row.change_7d_percent);
 if(gain!==null&&!Number.isFinite(gain))throw new Error('Invalid ranking change.');
 return {...row,amount,gain};
}
export async function refreshWebsiteSnapshot(cache,read,connectionString,now=Date.now(),workMs=38000){
 if(!cache)throw new Error('SITE_CACHE_NOT_CONFIGURED');
 const previous=await readWebsiteSnapshot(cache);
 if(previous&&now-Date.parse(previous.generatedAt)<intervalMs)return {updated:false};
 const failure=await cache.get(retryKey,{type:'json',cacheTtl:60});
 if(failure?.nextAttemptAt>now)return {updated:false,retryAfter:failure.nextAttemptAt};
 let job=await cache.get(refreshJobKey,{type:'json',cacheTtl:60}),stage='context';
 const deadline=Date.now()+workMs;
 try{
  const outcome=await read(connectionString,async store=>{
   const meta=await store.context();
   if(job?.schemaVersion!==2||job.catalogVersion!==meta.catalogVersion||job.phase==='complete')job={schemaVersion:2,catalogVersion:meta.catalogVersion,anchorDate:meta.anchorDate,startedAt:new Date(now).toISOString(),phase:'counts',cardCursor:'',publicationIndex:0,seriesCursor:'0',cardsScanned:0,pricesScanned:0,counts:{total:0,byGame:{},bySet:{}},leaders:{gainers:[],highest:[]}};
   const allowedGames=new Set(meta.games.map(g=>g.id)),gainers=createLeaderAccumulator(job.leaders.gainers,'gainers'),highest=createLeaderAccumulator(job.leaders.highest,'highest');
   while(Date.now()<deadline){
    stage=job.phase;
    if(job.phase==='counts'){
     const rows=await store.directoryChunk(job.cardCursor);
     for(const row of rows){if(allowedGames.has(row.game_id)&&row.product_type_name==='Cards'&&Number(row.has_image)===2){job.counts.total++;job.counts.byGame[row.game_id]=(job.counts.byGame[row.game_id]??0)+1;if(row.set_id)job.counts.bySet[row.set_id]=(job.counts.bySet[row.set_id]??0)+1;}}
     job.cardsScanned+=rows.length;
     if(rows.length){const cursor=rows.at(-1).product_id;if(cursor<=job.cardCursor)throw new Error('Directory cursor did not advance.');job.cardCursor=cursor;}
     if(rows.length<5000)job.phase='prices';
    }else if(job.phase==='prices'){
     const publication=meta.publications[job.publicationIndex];
     if(!publication){job.phase='hydrate';continue;}
     const packet=await store.priceChunk(publication,job.seriesCursor,meta);
     for(const value of packet.items){const row=candidate(value);highest.add(row);const baseline=Number(row.baseline_7d_amount_micros),start=new Date(row.observed_on+'T00:00:00Z');start.setUTCDate(start.getUTCDate()-7);if(baseline>0&&Number.isSafeInteger(baseline)&&row.gain>0&&row.baseline_7d_on===start.toISOString().slice(0,10))gainers.add(row);}
     job.pricesScanned+=packet.scanned;
     if(packet.scanned){if(BigInt(packet.cursor)<=BigInt(job.seriesCursor))throw new Error('Price cursor did not advance.');job.seriesCursor=packet.cursor;}
     if(packet.scanned<500){job.publicationIndex++;job.seriesCursor='0';}
    }else if(job.phase==='hydrate'){
     const boards={gainers:{kind:'gainers',returnedCount:gainers.rows.length,items:await store.hydrateRanking(gainers.rows,meta)},highest:{kind:'highest',returnedCount:highest.rows.length,items:await store.hydrateRanking(highest.rows,meta)}};
     const snapshot={schemaVersion:snapshotSchema,generatedAt:new Date(now).toISOString(),scanStartedAt:job.startedAt,catalogVersion:meta.catalogVersion,anchorDate:meta.anchorDate,directorySnapshot:false,counts:job.counts,boards};
     job.phase='complete';return {snapshot};
    }
   }
   job.leaders={gainers:gainers.rows,highest:highest.rows};return {snapshot:null};
  },{statementTimeoutMs:1500,operationBudgetMs:45000});
  job.updatedAt=new Date(now).toISOString();
  await cache.put(refreshJobKey,JSON.stringify(job));
  if(outcome.snapshot){await cache.put(snapshotKey,JSON.stringify(outcome.snapshot));return {updated:true,gainers:outcome.snapshot.boards.gainers.items.length,highest:outcome.snapshot.boards.highest.items.length};}
  return {updated:false,phase:job.phase,cardsScanned:job.cardsScanned,pricesScanned:job.pricesScanned};
 }catch(error){
  const code=error&&typeof error==='object'?Reflect.get(error,'code'):null;
  console.error(JSON.stringify({event:'website_snapshot_stage_failed',stage,databaseCode:typeof code==='string'?code:null}));
  await cache.put(retryKey,JSON.stringify({nextAttemptAt:now+5*60*1000,stage,databaseCode:typeof code==='string'&&/^[0-9A-Z]{5}$/.test(code)?code:null}),{expirationTtl:5*60});
  throw error;
 }
}
