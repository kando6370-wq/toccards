import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
export async function copyCatalogSitemaps(source,destination){
 const manifest=source?JSON.parse(await readFile(join(source,'catalog-manifest.json'),'utf8')):{schemaVersion:1,origin:'https://tcgcard.fun',discoveryCount:0,shards:[]};
 if(manifest.schemaVersion!==1||manifest.origin!=='https://tcgcard.fun'||!Array.isArray(manifest.shards)||manifest.shards.length>1000)throw new Error('Invalid catalog sitemap manifest.');
 let total=0;const seen=new Set();const verified=[];
 for(const shard of manifest.shards){
  if(!/^\/sitemaps\/cards-\d{5}\.xml$/.test(shard.path)||seen.has(shard.path)||!Number.isSafeInteger(shard.urlCount)||shard.urlCount<1||shard.urlCount>50000)throw new Error('Invalid sitemap shard.');seen.add(shard.path);
  const body=await readFile(join(source,shard.path.split('/').at(-1)));
  if(body.length!==shard.bytes||body.length>50*1024*1024||createHash('sha256').update(body).digest('hex')!==shard.sha256)throw new Error('Sitemap artifact does not match its manifest.');
  const xml=body.toString('utf8');if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw new Error('Unexpected XML declaration.');const urls=[...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map(m=>m[1].replace(/&(amp|lt|gt|quot|apos);/g,(_,key)=>({amp:'&',lt:'<',gt:'>',quot:'"',apos:"'"}[key])));
  if(urls.length!==shard.urlCount||urls.some(url=>{try{const parsed=new URL(url);return parsed.origin!=='https://tcgcard.fun'||!/^\/cards\/[^/]+$/.test(parsed.pathname)||/[?#]/.test(url)||parsed.href!==url;}catch{return true;}}))throw new Error('Sitemap contains unexpected URLs.');
  verified.push({shard,body});total+=shard.urlCount;
 }
 if(total!==manifest.discoveryCount)throw new Error('Sitemap counts do not match.');
 await mkdir(destination,{recursive:true});for(const {shard,body}of verified)await writeFile(join(destination,shard.path.split('/').at(-1)),body);
 const compact={schemaVersion:1,origin:manifest.origin,discoveryCount:total,shards:manifest.shards};
 await writeFile(join(destination,'catalog-manifest.json'),JSON.stringify(compact)+'\n');return compact;
}
