export const snapshotKey='website:market-snapshot:v1';
export const snapshotSchema=1;
const intervalMs=60*60*1000;
export async function readWebsiteSnapshot(cache){
 if(!cache)return null;
 const value=await cache.get(snapshotKey,{type:'json',cacheTtl:60});
 return value?.schemaVersion===snapshotSchema&&Array.isArray(value.boards?.gainers?.items)&&Array.isArray(value.boards?.highest?.items)?value:null;
}
export async function refreshWebsiteSnapshot(cache,read,connectionString,now=Date.now()){
 if(!cache)throw new Error('SITE_CACHE_NOT_CONFIGURED');
 const previous=await readWebsiteSnapshot(cache);
 if(previous&&now-Date.parse(previous.generatedAt)<intervalMs)return {updated:false};
 const failure=await cache.get('website:snapshot-retry:v1',{type:'json',cacheTtl:60});
 if(failure?.nextAttemptAt>now)return {updated:false,retryAfter:failure.nextAttemptAt};
 let stage='context';
 try{
  const snapshot=await read(connectionString,async store=>{
   const meta=await store.context();
   stage='counts';const counts=await store.directoryCounts(meta);
   stage='gainers';const gainers=await store.rankings('gainers',meta);
   stage='highest';const highest=await store.rankings('highest',meta);
   return {schemaVersion:snapshotSchema,generatedAt:new Date(now).toISOString(),catalogVersion:meta.catalogVersion,anchorDate:meta.anchorDate,counts,boards:{gainers,highest}};
  },{statementTimeoutMs:30000,operationBudgetMs:110000});
  await cache.put(snapshotKey,JSON.stringify(snapshot));
  return {updated:true,gainers:snapshot.boards.gainers.items.length,highest:snapshot.boards.highest.items.length};
 }catch(error){
  console.error(JSON.stringify({event:'website_snapshot_stage_failed',stage}));
  await cache.put('website:snapshot-retry:v1',JSON.stringify({nextAttemptAt:now+15*60*1000}),{expirationTtl:15*60});
  throw error;
 }
}
