import {createReadStream} from 'node:fs';
import {readFile,writeFile,mkdir,rename,rm,stat} from 'node:fs/promises';
import {createInterface} from 'node:readline';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash,randomUUID} from 'node:crypto';
import {cardIndexEligibility,cardMetadata,cardIdentityKey,cardContentSignature} from '@kando/website-content/seo';
const origin='https://tcgcard.fun';
const sha=value=>createHash('sha256').update(value).digest('hex');
const xml=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const header='<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n';
const date=value=>{if(!/^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)?$/.test(value??''))return null;const d=new Date(value);return Number.isFinite(d.getTime())&&d.toISOString().slice(0,10)===value.slice(0,10)?value:null;};
export function splitSitemapEntries(entries,{urlsPerFile=10000,maxBytes=50*1024*1024}={}){
 if(!Number.isSafeInteger(urlsPerFile)||urlsPerFile<1||urlsPerFile>50000||maxBytes>50*1024*1024||maxBytes<256)throw new Error('Invalid sitemap shard limits.');
 const shards=[];let current=[],bytes=Buffer.byteLength(header+'</urlset>\n');
 for(const entry of entries){const item=`<url><loc>${xml(origin+entry.path)}</loc>${entry.lastmod?`<lastmod>${xml(entry.lastmod)}</lastmod>`:''}</url>\n`;const size=Buffer.byteLength(item);if(size+Buffer.byteLength(header+'</urlset>\n')>maxBytes)throw new Error('A sitemap URL is too large.');if(current.length&&(current.length>=urlsPerFile||bytes+size>maxBytes)){shards.push({urlCount:current.length,xml:header+current.join('')+'</urlset>\n'});current=[];bytes=Buffer.byteLength(header+'</urlset>\n');}current.push(item);bytes+=size;}
 if(current.length)shards.push({urlCount:current.length,xml:header+current.join('')+'</urlset>\n'});return shards;
}
export async function* readCatalogExport(input){
 const size=(await stat(input)).size;if(size>1024*1024*1024)throw new Error('Catalog export exceeds the offline import limit.');
 if(/\.ndjson$|\.jsonl$/i.test(input)){
  const lines=createInterface({input:createReadStream(input),crlfDelay:Infinity});let meta=null,trailer=null,count=0;
  for await(const line of lines){if(!line.trim())continue;if(Buffer.byteLength(line)>1024*1024)throw new Error('Oversized catalog record.');const record=JSON.parse(line);if(!meta){if(record.recordType!=='catalog'||record.mode!=='published-export')throw new Error('A published catalog header is required.');meta=record;continue;}if(trailer)throw new Error('Records follow the completion marker.');if(record.recordType==='complete'){trailer=record;continue;}if(record.recordType!=='card'||!record.card)throw new Error('Invalid catalog record.');count++;yield record.card;}
  if(!meta||!trailer?.completeTraversal||trailer.cardCount!==count||trailer.catalogVersion!==meta.catalogVersion)throw new Error('Incomplete or inconsistent catalog export.');
 }else{
  if(size>128*1024*1024)throw new Error('Use streaming NDJSON for catalog exports larger than 128 MiB.');
  const data=JSON.parse(await readFile(input,'utf8'));if(data.mode!=='published-export'||data.completeTraversal!==true||!Array.isArray(data.cards)||data.cardCount!==data.cards.length)throw new Error('A complete published export is required.');
  yield*data.cards;
 }
}
export async function generateCatalogSitemaps(input,output,{maxUrls,urlsPerFile=10000,previous=null,gameSlugs=[],setIds=[]}={}){
 if(!Number.isSafeInteger(maxUrls)||maxUrls<1||maxUrls>10000000)throw new Error('Supply an explicit discovery budget of 1–10000000 URLs.');
 const samples=[];const issueSamples=[];const seen=new Set(),identityGroups=new Map(),titleGroups=new Map(),candidates=[],excluded={};let scanned=0;
 for await(const card of readCatalogExport(input)){
  scanned++;const quality=cardIndexEligibility(card,'published-export');if(quality.id&&seen.has(quality.id))throw new Error('Duplicate public card ID in export.');seen.add(quality.id);
  if(!quality.eligible){if(issueSamples.length<100)issueSamples.push({id:quality.id,reasons:quality.reasons});for(const reason of quality.reasons)excluded[reason]=(excluded[reason]??0)+1;continue;}
  const metadata=cardMetadata(card);if(samples.length<20)samples.push({id:quality.id,title:metadata.title,description:metadata.description});const identity=cardIdentityKey(card),contentHash=sha(cardContentSignature(card));
  const item={id:quality.id,gameSlug:card.gameSlug??null,setId:card.publicSetId??null,path:'/cards/'+encodeURIComponent(quality.id),title:metadata.title,identity,contentHash,lastmod:date(card.contentModifiedAt??card.content_modified_at)};
  candidates.push(item);for(const [map,key]of [[identityGroups,identity],[titleGroups,metadata.title]]){const group=map.get(key)??[];group.push(item.id);map.set(key,group);}
 }
 const ambiguousIds=new Set();let collisionGroups=0;
 for(const map of [identityGroups,titleGroups])for(const group of map.values())if(group.length>1){collisionGroups++;for(const id of group)ambiguousIds.add(id);}
 const eligible=candidates.filter(c=>!ambiguousIds.has(c.id)).sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0);
 let old=[];if(previous){const prior=JSON.parse(await readFile(join(previous,'catalog-manifest.json'),'utf8'));old=prior.selectedIds??[];}
 const eligibleIds=new Set(eligible.map(c=>c.id));const previousIds=new Set(old);const preferred=eligible.filter(c=>(gameSlugs.length===0||gameSlugs.includes(c.gameSlug))&&(setIds.length===0||setIds.includes(c.setId)));const ordered=[...eligible.filter(c=>previousIds.has(c.id)),...preferred.filter(c=>!previousIds.has(c.id))];
 if(old.filter(id=>eligibleIds.has(id)).length>maxUrls)throw new Error('Discovery budget would withdraw previously submitted eligible URLs.');
 const selected=ordered.slice(0,maxUrls).sort((a,b)=>a.id<b.id?-1:a.id>b.id?1:0);const chunks=splitSitemapEntries(selected,{urlsPerFile});
 const destination=resolve(output),temporary=destination+'.building-'+randomUUID();await mkdir(temporary,{recursive:true});
 try{
  const shards=[];
  for(let i=0;i<chunks.length;i++){const path=`/sitemaps/cards-${String(i+1).padStart(5,'0')}.xml`,body=chunks[i].xml;await writeFile(join(temporary,path.split('/').at(-1)),body);shards.push({path,urlCount:chunks[i].urlCount,bytes:Buffer.byteLength(body),sha256:sha(body)});}
  const manifest={schemaVersion:1,origin,scanned,eligibleCount:eligible.length,discoveryCount:selected.length,maxUrls,urlsPerFile,filters:{gameSlugs,setIds},collisionGroups,ambiguousRecordCount:ambiguousIds.size,excluded,issueSamples,metadataSamples:samples,selectedIds:selected.map(c=>c.id),shards};
  await writeFile(join(temporary,'catalog-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  const backup=destination+'.previous';await rm(backup,{recursive:true,force:true});let moved=false;try{await rename(destination,backup);moved=true;}catch(error){if(error.code!=='ENOENT')throw error;}try{await rename(temporary,destination);}catch(error){if(moved)await rename(backup,destination);throw error;}
  return manifest;
 }catch(error){await rm(temporary,{recursive:true,force:true});throw error;}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){const args=Object.fromEntries(process.argv.slice(2).map(arg=>{const[key,...value]=arg.split('=');return[key.replace(/^--/,''),value.join('=')];}));if(!args.input||!args.outdir||!args['max-urls'])throw new Error('Usage: catalog:sitemaps --input=/approved/export.ndjson --outdir=/candidate/sitemaps --max-urls=1000');const report=await generateCatalogSitemaps(args.input,args.outdir,{maxUrls:Number(args['max-urls']),urlsPerFile:Number(args['urls-per-file']??10000),previous:args.previous??null,gameSlugs:args.games?args.games.split(','):[],setIds:args.sets?args.sets.split(','):[]});console.log(JSON.stringify({scanned:report.scanned,eligible:report.eligibleCount,discovery:report.discoveryCount,shards:report.shards.length,ambiguous:report.ambiguousRecordCount,excluded:report.excluded}));}
