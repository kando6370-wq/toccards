import {writeFile,open,rename,mkdir,rm} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
const args=Object.fromEntries(process.argv.slice(2).map(arg=>{const [key,...value]=arg.split('=');return[key.replace(/^--/,''),value.join('=')];}));
if(!args.output||!args['max-pages'])throw new Error('Supply --output=/path/to/new-snapshot.json and an explicit --max-pages=budget.');
const format=args.format??'json';if(format==='ndjson'&&!/\.ndjson$|\.jsonl$/i.test(args.output))throw new Error('Use .ndjson or .jsonl for a streaming export.');if(!['json','ndjson'].includes(format))throw new Error('Export format must be json or ndjson.');
const endpoint=new URL(process.env.SITE_DATA_EXPORT_URL??'http://127.0.0.1:8891/site-api/v1/');
if((endpoint.protocol!=='https:'&&!['127.0.0.1','localhost'].includes(endpoint.hostname))||endpoint.username||endpoint.password||endpoint.search||endpoint.hash)throw new Error('Use an approved new-service URL without credentials or query.');
const budget=Number(args['max-pages']);if(!Number.isSafeInteger(budget)||budget<1||budget>30000)throw new Error('Invalid page budget.');
const output=resolve(args.output),temp=output+'.partial-'+process.pid;
const items=[],seen=new Set();let cursor=null,version=null,complete=false,meta,handle=null;
async function get(path){const response=await fetch(new URL(path,endpoint.href.endsWith('/')?endpoint.href:endpoint.href+'/'),{headers:process.env.SITE_DATA_EXPORT_TOKEN?{Authorization:'Bearer '+process.env.SITE_DATA_EXPORT_TOKEN}:{},redirect:'error',signal:AbortSignal.timeout(10000)});if(!response.ok)throw new Error('Catalog export failed with HTTP '+response.status);const body=await response.json();if(!body.success||body.meta?.datasetMode!=='published-read-only')throw new Error('Export requires the new published read-only service.');return body;}
try{
 await mkdir(dirname(output),{recursive:true});if(format==='ndjson')handle=await open(temp,'wx',0o600);
 for(let page=0;page<budget;page++){
  const query=new URLSearchParams({pageSize:'48',sort:'featured'});if(cursor)query.set('after',cursor);
  const body=await get('cards?'+query);meta=body.meta;if(version&&version!==meta.catalogVersion)throw new Error('Published data changed during export; retry as a separate job.');version=meta.catalogVersion;
  if(handle&&page===0)await handle.writeFile(JSON.stringify({recordType:'catalog',schemaVersion:2,catalogVersion:version,capturedAt:meta.snapshotCapturedAt,mode:'published-export',consistentSnapshot:false,versionScope:'price-publication-pointers'})+'\n');
  const batch=[];
  for(const item of body.data.items){if(seen.has(item.publicCardId))throw new Error('Duplicate card in export.');seen.add(item.publicCardId);if(handle)batch.push(JSON.stringify({recordType:'card',card:item}));else items.push(item);}
  if(handle&&batch.length)await handle.writeFile(batch.join('\n')+'\n');
  if(!body.data.hasMore){complete=true;break;}if(!body.data.nextCursor||body.data.nextCursor===cursor)throw new Error('Missing or repeated export cursor.');cursor=body.data.nextCursor;
  await new Promise(resolve=>setTimeout(resolve,250));
 }
 if(!complete)throw new Error('Page budget exhausted. No snapshot was replaced.');
 if(handle){await handle.writeFile(JSON.stringify({recordType:'complete',catalogVersion:version,cardCount:seen.size,completeTraversal:true})+'\n');await handle.sync();await handle.close();handle=null;}
 else{const snapshot={schemaVersion:1,catalogVersion:version,capturedAt:meta.snapshotCapturedAt,mode:'published-export',publicationApproved:false,completeTraversal:true,consistentSnapshot:false,versionScope:'price-publication-pointers',cardCount:items.length,cards:items};await writeFile(temp,JSON.stringify(snapshot,null,2)+'\n',{flag:'wx',mode:0o600});}
 await rename(temp,output);console.log(JSON.stringify({complete:true,cardCount:seen.size,catalogVersion:version,format,output}));
}catch(error){if(handle)await handle.close();await rm(temp,{force:true});throw error;}
