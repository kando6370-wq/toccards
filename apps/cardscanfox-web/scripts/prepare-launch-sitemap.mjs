import {execFileSync} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {cardIndexEligibility,cardIdentityKey,cardMetadata} from '@kando/website-content/seo';
import homeFeatured from '@kando/website-content/home-featured' with {type:'json'};
import releaseSitemap from '../content/sitemaps/catalog-manifest.json' with {type:'json'};
import {splitSitemapEntries} from './catalog-sitemaps.mjs';
const endpoint='https://cardscanfox-git-preview.pages.dev/site-api/v1/';
const get=path=>{const body=JSON.parse(execFileSync('curl',['-fsS','--max-time','25',endpoint+path],{encoding:'utf8',maxBuffer:2000000}));if(!body.success||body.meta?.datasetMode!=='published-read-only')throw Error('A published read-only response is required');return body;};
const cards=new Map();for(const id of new Set([...homeFeatured.cardIds,...(releaseSitemap.releaseCardIds??[]),'98097','98112','98141','101520'])){const c=get('cards/'+id).data;if(c)cards.set(c.publicCardId,c);}
for(const kind of ['gainers','highest'])for(const c of get('rankings/'+kind).data.items)cards.set(c.publicCardId,c);
let after=null;for(let page=0;page<18;page++){const q=new URLSearchParams({pageSize:'48',game:'pokemon'});if(after)q.set('after',after);const d=get('cards?'+q).data;for(const c of d.items)cards.set(c.publicCardId,c);if(!d.hasMore)break;if(!d.nextCursor||d.nextCursor===after)throw Error('Cursor did not advance');after=d.nextCursor;}
const groups=new Map(),titles=new Map();for(const c of cards.values()){const key=cardIdentityKey(c),title=cardMetadata(c).title;groups.set(key,(groups.get(key)??0)+1);titles.set(title,(titles.get(title)??0)+1);}
const eligible=[...cards.values()].filter(c=>cardIndexEligibility(c,'published-read-only').eligible&&groups.get(cardIdentityKey(c))===1&&titles.get(cardMetadata(c).title)===1);
const chunks=splitSitemapEntries(eligible.map(c=>({path:'/cards/'+encodeURIComponent(c.publicCardId)})));const output=new URL('../content/sitemaps/',import.meta.url);await mkdir(output,{recursive:true});const shards=[];
for(let i=0;i<chunks.length;i++){const name='cards-'+String(i+1).padStart(5,'0')+'.xml',body=chunks[i].xml;await writeFile(new URL(name,output),body);shards.push({path:'/sitemaps/'+name,urlCount:chunks[i].urlCount,bytes:Buffer.byteLength(body),sha256:createHash('sha256').update(body).digest('hex')});}
await writeFile(new URL('catalog-manifest.json',output),JSON.stringify({schemaVersion:1,origin:'https://tcgcard.fun',scope:'Initial discovery batch: public ranking cards and 18 Pokemon catalog pages; not a full catalog export',capturedAt:new Date().toISOString(),candidateCount:cards.size,discoveryCount:eligible.length,releaseCardIds:releaseSitemap.releaseCardIds??[],shards},null,2)+'\n');console.log(JSON.stringify({candidates:cards.size,published:eligible.length,shards:shards.length}));
