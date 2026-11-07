import { createHash } from 'node:crypto';
import { cards as reviewCards, sets as reviewSets } from '@kando/website-content';

export class CatalogInputError extends Error { constructor(message) { super(message); this.name = 'QueryError'; } }
const knownGames = { pokemon:'pokemon', 'pokémon':'pokemon', 'one piece':'one-piece', yugioh:'yugioh', 'yu-gi-oh!':'yugioh', 'magic: the gathering':'mtg', magic:'mtg', 'disney lorcana':'lorcana', lorcana:'lorcana', basketball:'basketball' };
const slugFor = row => knownGames[row.name.trim().toLowerCase()] ?? `game-${row.id}`;
const day = value => value instanceof Date ? value.toISOString().slice(0, 10) : String(value).slice(0, 10);
const shift = (date, n) => { const d = new Date(date+'T00:00:00Z'); d.setUTCDate(d.getUTCDate()+n); return d.toISOString().slice(0, 10); };
const text = (value, max = 128) => { const s = String(value ?? '').trim(); if (s.length > max || /[\u0000-\u001f]/.test(s)) throw new CatalogInputError('Invalid query value.'); return s; };
const number = (value, fallback, max) => { const n = Number(value ?? fallback); if (!Number.isSafeInteger(n) || n < 1 || n > max) throw new CatalogInputError('Invalid page or page size.'); return n; };
export function usd(value) { if (value === null || value === undefined) return null; const n = Number(value); if (!Number.isSafeInteger(n) || n < 0) throw new Error('Unsafe price amount.'); return n/1_000_000; }
const published = `WITH ranked_current AS (
 SELECT b.source_id, p.batch_id, b.scope_code, ROW_NUMBER() OVER (PARTITION BY b.source_id ORDER BY b.business_date DESC,b.batch_id DESC) AS rank
 FROM current_price_pointer p JOIN price_ingest_batch b ON b.batch_id=p.batch_id AND b.scope_code=p.scope_code
 WHERE p.scope_code LIKE 'current:%' AND b.status='published'
), published AS (SELECT source_id,batch_id,scope_code FROM ranked_current WHERE rank=1)`;
const priceColumns = `s.series_id::text AS series_id, src.source_code, src.display_name AS source_label, s.source_record_id, s.metric_code,
 s.condition_code,s.condition_name,s.language_code,s.language_name,s.finish_code,s.finish_name,s.grader_code,s.grade_min_x10,s.grade_max_x10,
 snap.observed_on::text AS observed_on,snap.amount_micros::text AS amount_micros,snap.change_7d_percent::text AS change_7d_percent,
 snap.baseline_1d_on::text AS baseline_1d_on,snap.baseline_1d_amount_micros::text AS baseline_1d_amount_micros,
 snap.baseline_7d_on::text AS baseline_7d_on,snap.baseline_7d_amount_micros::text AS baseline_7d_amount_micros,
 pub.batch_id::text AS batch_id,pub.scope_code`;
const priceFrom = `FROM price_series s JOIN price_source src ON src.source_id=s.source_id AND src.is_active IS TRUE
 JOIN published pub ON pub.source_id=s.source_id JOIN price_current_snapshot snap ON snap.batch_id=pub.batch_id AND snap.series_id=s.series_id`;
const preferred = `(CASE WHEN s.condition_code='NM' THEN 0 ELSE 100 END)+(CASE WHEN s.language_code='EN' THEN 0 ELSE 10 END)+(CASE WHEN s.finish_code='N' THEN 0 ELSE 1 END),snap.change_30d_percent DESC NULLS LAST,snap.observed_on DESC,src.source_code,s.source_record_id,s.metric_code,s.series_id`;
const activePrice = `s.is_active AND s.currency_code='USD'`;
const catalogColumns = `c.product_id,c.game_id,c.game,c.set_id,c.set_name,c.set_code,c.number,c.name,c.rarity,c.product_type_name,c.updated_at`;
function priceContext(p) {
 if (!p?.series_id) return null;
 return { seriesId:p.series_id, source:p.source_code, sourceLabel:p.source_label, metric:p.metric_code, currency:'USD', language:p.language_name??p.language_code, finish:p.finish_name??p.finish_code, grader:p.grader_code, gradeMin:p.grade_min_x10===null?null:Number(p.grade_min_x10)/10, gradeMax:p.grade_max_x10===null?null:Number(p.grade_max_x10)/10, condition:p.condition_name??p.condition_code, amountMicros:p.amount_micros, amount:usd(p.amount_micros), priceAsOf:p.observed_on, status:'available', catalogVersion:`published-${p.batch_id}` };
}
function setId(row) { const existing=reviewCards.find(c=>c.set_name===row.set_name&&c.set_code===row.set_code&&c.game.toLowerCase()===String(row.game).toLowerCase()); return existing?.publicSetId??'db-'+row.set_id; }
function cardRecord(row, games) {
 const game=games.find(g=>String(g.id)===String(row.game_id));const ref=priceContext(row);
 return { publicCardId:String(row.product_id),card_ref:String(row.product_id),name:row.name??String(row.product_id),game:row.game,gameSlug:game?.slug??`game-${row.game_id}`,sourceSetId:row.set_id,publicSetId:row.set_id?setId(row):null,set_name:row.set_name??'Set not listed',set_code:row.set_code??'',card_number:row.number??'',rarity:row.rarity,finish:ref?.finish??null,language:ref?.language??null,object_type:Number(row.game_id)>=50000?'sports':'tcg',image_url:`https://image.tcgcard.fun/cards/${encodeURIComponent(row.product_id)}.jpg`,price_usd:ref?.amount??null,price_as_of:ref?.priceAsOf??null,price_change_7d_percent:row.change_7d_percent===null||row.change_7d_percent===undefined?null:Number(row.change_7d_percent),reference:ref };
}
export function createPostgresStore(query) {
 const getGames = async () => (await query(`SELECT game_id::text AS id,name FROM games WHERE load=1 AND btrim(coalesce(name,''))<>'' ORDER BY search_sort,game_id`,[])).map(r=>({...r,slug:slugFor(r),cardCount:null}));
 async function context(){
  const games=await getGames();const pointers=await query(`${published} SELECT pub.source_id::text AS source_id,pub.scope_code,pub.batch_id::text AS batch_id,b.business_date::text AS business_date FROM published pub JOIN price_ingest_batch b ON b.batch_id=pub.batch_id JOIN price_source source ON source.source_id=pub.source_id AND source.is_active ORDER BY pub.source_id`,[]);
  return {games,publications:pointers,anchorDate:pointers.map(p=>p.business_date).filter(Boolean).sort().at(-1)??new Date().toISOString().slice(0,10),catalogVersion:'published-'+createHash('sha256').update(JSON.stringify(pointers)).digest('hex').slice(0,16),snapshotCapturedAt:new Date().toISOString(),datasetMode:'published-read-only'};
 }
 function pageResult(rows,page,pageSize) { const more=rows.length>pageSize;return {items:rows.slice(0,pageSize),total:null,totalKind:'not-computed',returnedCount:Math.min(rows.length,pageSize),page,pageSize,hasMore:more,nextPage:more?page+1:null}; }
 async function resolveSet(id) {
  const old=reviewSets.find(s=>s.id===id);
  const rows=old?await query(`SELECT set_id,game,name,set_code FROM sets WHERE name=$1 AND coalesce(set_code,'')=$2 LIMIT 2`,[old.name,old.code]):await query(`SELECT set_id,game,name,set_code FROM sets WHERE set_id=$1 LIMIT 1`,[text(id).replace(/^db-/, '')]);
  if(rows.length>1)throw new CatalogInputError('Ambiguous set identity.');return rows[0]??null;
 }
 async function listCards(params,ctx) {
  const q=text(params.get('q')),game=text(params.get('game')),set=text(params.get('set')),language=text(params.get('language')),finish=text(params.get('finish')),price=text(params.get('price')),sort=params.get('sort')??'featured',after=text(params.get('after')),before=text(params.get('before'));
  if(after&&before)throw new CatalogInputError('Use only one page cursor.');
  if((after||before)&&sort!=='featured')throw new CatalogInputError('Cursor paging requires featured order.');
  if(sort!=='featured'&&(!set||set==='all'))throw new CatalogInputError('Choose a set before sorting by name, price or date.');
  const page=number(params.get('page'),1,1000000),pageSize=number(params.get('pageSize'),24,48);
  if(page>500&&!after&&!before)throw new CatalogInputError('Use the next and previous links for later pages.');
  if(!['featured','name','recent','price-asc','price-desc'].includes(sort)||!['','all','available','missing','under20','20to100','over100'].includes(price))throw new CatalogInputError('Unsupported filter or sort.');
  const candidateFilters=[];const values=[],where=[`EXISTS (SELECT 1 FROM games g WHERE g.game_id=c.game_id AND g.load=1)`,"c.product_type_name='Cards'",'c.has_image=2'];const add=v=>{values.push(v);return '$'+values.length};
  if(after)where.push(`c.product_id>${add(after)}`);if(before)where.push(`c.product_id<${add(before)}`);
  if(q){const pattern=q.toLowerCase().replace(/[\\%_]/g,'\\$&');where.push(`lower(coalesce(c.name,'')||' '||coalesce(c.number,'')||' '||coalesce(c.set_name,'')||' '||coalesce(c.set_code,'')||' '||coalesce(c.rarity,'')||' '||coalesce(c.game,'')) LIKE ${add('%'+pattern+'%')}`);}
  if(game&&game!=='all'){const g=ctx.games.find(g=>g.slug===game||g.id===game);if(!g)throw new CatalogInputError('Unknown game.');where.push(`c.game_id=${add(Number(g.id))}`);}
  if(set&&set!=='all'){const s=await resolveSet(set);if(!s)throw new CatalogInputError('Unknown set.');where.push(`c.set_id=${add(s.set_id)}`);if(!game||game==='all'){const owner=ctx.games.find(g=>g.name.toLowerCase()===s.game.toLowerCase());if(!owner)throw new CatalogInputError('Unknown game.');where.push(`c.game_id=${add(Number(owner.id))}`);}}
  if(language&&language!=='all'){const key=add(language);where.push(`coalesce(p.language_name,p.language_code,'Not listed')=${key}`);candidateFilters.push(`coalesce(s.language_name,s.language_code,'Not listed')=${key}`);}
  if(finish&&finish!=='all'){const key=add(finish);where.push(`coalesce(p.finish_name,p.finish_code,'Not listed')=${key}`);candidateFilters.push(`coalesce(s.finish_name,s.finish_code,'Not listed')=${key}`);}
  if(price==='available')where.push('p.amount_micros IS NOT NULL');if(price==='missing')where.push('p.amount_micros IS NULL');
  if(price==='under20')where.push('p.amount_micros::bigint<20000000');if(price==='20to100')where.push('p.amount_micros::bigint>=20000000 AND p.amount_micros::bigint<100000000');if(price==='over100')where.push('p.amount_micros::bigint>=100000000');
  const orders={featured:'c.product_id',name:'c.name,c.product_id',recent:'p.observed_on DESC NULLS LAST,c.product_id','price-asc':'p.amount_micros::bigint ASC NULLS LAST,c.product_id','price-desc':'p.amount_micros::bigint DESC NULLS LAST,c.product_id'};
  const limit=add(pageSize+1),offset=add(after||before?0:(page-1)*pageSize);
  const rows=await query(`${published} SELECT ${catalogColumns},p.* FROM cards_all c LEFT JOIN LATERAL (SELECT ${priceColumns} ${priceFrom} WHERE ${activePrice} AND s.card_ref=c.product_id AND upper(btrim(s.grader_code))='RAW' ${candidateFilters.map(f=>'AND '+f).join(' ')} ORDER BY ${preferred} LIMIT 1) p ON true WHERE ${where.join(' AND ')} ORDER BY ${before?'c.product_id DESC':orders[sort]} LIMIT ${limit} OFFSET ${offset}`,values);
  const selected=rows.slice(0,pageSize).map(r=>cardRecord(r,ctx.games));if(before)selected.reverse();
  const more=rows.length>pageSize,hasMore=before?true:more,hasPrevious=before?more:Boolean(after)||page>1;
  let total=null;const simple=!q&&(!language||language==='all')&&(!finish||finish==='all')&&(!price||price==='all');
  if(simple&&ctx.counts){if(set&&set!=='all'){const resolved=await resolveSet(set);total=ctx.counts.bySet[resolved.set_id]??null;}else if(game&&game!=='all'){const g=ctx.games.find(g=>g.slug===game||g.id===game);total=ctx.counts.byGame[g.id]??null;}else total=ctx.counts.total;}
  return {items:selected,returnedCount:selected.length,total,totalKind:total===null?'not-computed':'cached-scan',countedAt:ctx.countedAt??null,page,pageSize,hasMore,hasPrevious,nextPage:hasMore?page+1:null,nextCursor:sort==='featured'&&hasMore?selected.at(-1)?.publicCardId??null:null,previousCursor:sort==='featured'&&hasPrevious?selected[0]?.publicCardId??null:null};
 }
 async function getCard(id,params,ctx) {
  const rows=await query(`SELECT ${catalogColumns} FROM cards_all c WHERE c.product_id=$1 AND EXISTS (SELECT 1 FROM games g WHERE g.game_id=c.game_id AND g.load=1) LIMIT 1`,[text(id)]);if(!rows[0])return null;
  const prices=await query(`${published} SELECT ${priceColumns} ${priceFrom} WHERE ${activePrice} AND s.card_ref=$1 ORDER BY ${preferred} LIMIT 201`,[id]);if(prices.length>200)throw new Error('Price contexts exceed bounded selection.');
  const requested=params.get('series');if(requested&&!/^\d+$/.test(requested))throw new CatalogInputError('Invalid series selection.');
  const selected=requested?prices.find(p=>p.series_id===requested):prices.find(p=>p.grader_code.trim().toUpperCase()==='RAW');
  if(requested&&!selected)throw new CatalogInputError('This price series is not published for this card.');
  return {...cardRecord({...rows[0],...(selected??{})},ctx.games),references:prices.map(priceContext)};
 }
 async function trend(id,params,ctx,selectedCard=null) {
  if(params.has('days')&&params.get('days')!=='30')throw new CatalogInputError('Only 30 days are available.');
  const card=selectedCard??await getCard(id,params,ctx);if(!card)return null;
  const ref=card.reference;
  if(!ref)return {publicCardId:id,days:30,currency:'USD',status:'missing',points:[],reference:null};
  for(const [key,actual]of [['condition',ref.condition],['grader',ref.grader],['language',ref.language],['finish',ref.finish]])if(params.has(key)&&params.get(key)!==actual)throw new CatalogInputError('Price dimensions do not match the selected series.');
  const end=ref.priceAsOf,start=shift(end,-29);
  const history=await query(`SELECT h.points FROM price_history_month h JOIN price_series s ON s.series_id=h.series_id JOIN price_ingest_batch hb ON hb.batch_id=h.last_batch_id AND hb.source_id=s.source_id AND hb.status IN ('published','superseded') WHERE h.series_id=$1 AND h.month_start BETWEEN date_trunc('month',$2::date)::date AND date_trunc('month',$3::date)::date AND EXISTS(SELECT 1 FROM current_price_pointer p JOIN price_ingest_batch b ON b.batch_id=p.batch_id AND b.scope_code=p.scope_code AND b.source_id=s.source_id AND b.status='published' WHERE p.scope_code=hb.scope_code AND p.scope_code LIKE 'current:%') ORDER BY h.month_start LIMIT 3`,[ref.seriesId,start,end]);
  const points=new Map();for(const month of history){const list=typeof month.points==='string'?JSON.parse(month.points):month.points;if(!Array.isArray(list)||list.length>5000)throw new Error('Invalid or oversized monthly history.');for(const p of list){const date=p.d??p.date;const amount=p.a!==undefined?usd(p.a):typeof p.price==='string'&&/^\d+(?:\.\d+)?$/.test(p.price)?Number(p.price):p.price;const parsedDate=new Date(String(date)+'T00:00:00Z');if(!/^\d{4}-\d{2}-\d{2}$/.test(date??'')||!Number.isFinite(parsedDate.getTime())||parsedDate.toISOString().slice(0,10)!==date||!Number.isFinite(amount)||amount<0)throw new Error('Invalid price history.');if(date>=start&&date<=end)points.set(date,{date,price:amount});}}
  points.set(end,{date:end,price:ref.amount});
  return {publicCardId:id,days:30,currency:'USD',status:points.size>1?'available':'insufficient',points:[...points.values()].sort((a,b)=>a.date.localeCompare(b.date)),reference:ref,windowStart:start,windowEnd:end,condition:ref.condition,grader:ref.grader};
 }
 async function listSets(params,ctx) {
  const page=number(params.get('page'),1,500),pageSize=number(params.get('pageSize'),24,48),q=text(params.get('q')),game=text(params.get('game'));
  const g=game&&game!=='all'?ctx.games.find(g=>g.slug===game||g.id===game):null;if(game&&game!=='all'&&!g)throw new CatalogInputError('Unknown game.');
  const rows=await query(`SELECT set_id,game,name,set_code,total_cards,count(*) OVER()::text AS matched_total FROM sets s WHERE ($1='' OR lower(s.name||' '||coalesce(s.set_code,'')) LIKE $1) AND ($2='' OR lower(s.game)=lower($2)) AND EXISTS(SELECT 1 FROM games g WHERE lower(g.name)=lower(s.game) AND g.load=1) ORDER BY s.name,s.set_id LIMIT $3 OFFSET $4`,[q?'%'+q.toLowerCase().replace(/[\\%_]/g,'\\$&')+'%':'',g?.name??'',pageSize+1,(page-1)*pageSize]);
  return {...pageResult(rows.map(r=>({id:setId({...r,set_name:r.name}),sourceSetId:r.set_id,name:r.name,code:r.set_code,gameSlug:ctx.games.find(g=>g.name.toLowerCase()===r.game.toLowerCase())?.slug,language:null,catalogedCount:ctx.counts?.bySet[r.set_id]??null,sourceReportedCount:r.total_cards,complete:false})),page,pageSize),total:rows.length?Number(rows[0].matched_total):page===1?0:null,totalKind:'exact-query',hasPrevious:page>1};
 }
 const store={context,getGames,listCards,getCard,trend,listSets,pageData,directoryChunk,priceChunk,hydrateRanking,async getSet(id,params,ctx){const set=await resolveSet(id);if(!set)return null;const allowed=ctx.games.find(g=>g.name.toLowerCase()===set.game.toLowerCase());if(!allowed)return null;return {id,name:set.name,code:set.set_code,gameSlug:allowed.slug,catalogedCount:null,complete:false,...await listCards(new URLSearchParams({...Object.fromEntries(params),set:id}),ctx)};}};

 async function directoryChunk(after){return query(`SELECT product_id,game_id::text AS game_id,set_id,product_type_name,has_image FROM cards_all WHERE product_id>$1 ORDER BY product_id LIMIT 5000`,[after]);}
 async function priceChunk(publication,after,ctx){
  const [packet]=await query(`WITH chunk AS MATERIALIZED(SELECT series_id,observed_on,amount_micros,baseline_7d_on,baseline_7d_amount_micros,change_7d_percent FROM price_current_snapshot WHERE batch_id=$1::bigint AND series_id>$2::bigint ORDER BY series_id LIMIT 500),eligible AS(
   SELECT s.card_ref,s.series_id::text AS series_id,snap.amount_micros::text AS amount_micros,snap.observed_on::text AS observed_on,snap.baseline_7d_on::text AS baseline_7d_on,snap.baseline_7d_amount_micros::text AS baseline_7d_amount_micros,snap.change_7d_percent::text AS change_7d_percent
   FROM chunk snap JOIN price_series s ON s.series_id=snap.series_id AND s.source_id=$3::bigint JOIN cards_all c ON c.product_id=s.card_ref JOIN games g ON g.game_id=c.game_id AND g.load=1
   WHERE ${activePrice} AND upper(btrim(s.grader_code))='RAW' AND (s.condition_code='NM' OR s.condition_code IS NULL) AND snap.amount_micros>0 AND snap.observed_on BETWEEN $4::date-6 AND $4::date
   AND c.product_type_name='Cards' AND c.has_image=2 AND btrim(coalesce(c.number,''))<>'' AND btrim(coalesce(c.name,''))<>''
  ) SELECT (SELECT max(series_id)::text FROM chunk) AS cursor,(SELECT count(*)::integer FROM chunk) AS scanned,coalesce((SELECT jsonb_agg(eligible) FROM eligible),'[]'::jsonb) AS items`,[publication.batch_id,after,publication.source_id,ctx.anchorDate]);
  return {cursor:packet.cursor,scanned:packet.scanned,items:typeof packet.items==='string'?JSON.parse(packet.items):packet.items};
 }
 async function hydrateRanking(leaders,ctx){
  if(!leaders.length)return [];
  if(leaders.length>100)throw new Error('Ranking hydration exceeds its bounded selection.');
  const ids=leaders.map(c=>c.series_id);
  const rows=await query(`${published} SELECT ${catalogColumns},${priceColumns},snap.baseline_7d_on::text AS comparison_date,snap.baseline_7d_amount_micros::text AS comparison_micros ${priceFrom} JOIN cards_all c ON c.product_id=s.card_ref WHERE ${activePrice} AND s.series_id IN(${ids.map((_,i)=>'$'+(i+1)+'::bigint').join(',')})`,ids);
  const byId=new Map(rows.map(r=>[r.series_id,r]));
  return leaders.map((leader,i)=>{const row=byId.get(leader.series_id);if(!row)throw new Error('Ranking identity changed during refresh.');return {...cardRecord(row,ctx.games),rank:i+1,baseline_7d_price:usd(row.comparison_micros),baseline_7d_on:row.comparison_date,price_change_7d_percent:row.change_7d_percent===null?null:Number(row.change_7d_percent)};});
 }

 async function pageData(params,ctx){
  const path=params.get('path')??'/';const filter=new URLSearchParams(params);filter.delete('path');
  const base={games:ctx.games,sets:[],cards:[],result:null,card:null,trend:null,set:null,catalogVersion:ctx.catalogVersion,capturedAt:ctx.snapshotCapturedAt.slice(0,10)};
  if(path==='/saved')return base;
  if(path==='/sets'){const result=await listSets(filter,ctx);return {...base,sets:result.items,result};}
  const allSets=await listSets(new URLSearchParams({pageSize:'48'}),ctx);base.sets=allSets.items;
  if(path.startsWith('/cards/')){
   const id=decodeURIComponent(path.slice(7));if(!id)throw new CatalogInputError('Invalid card path.');
   const card=await getCard(id,filter,ctx);if(!card)return {...base,notFound:true};
   if(card.publicSetId&&!base.sets.some(s=>s.id===card.publicSetId)){const parent=await resolveSet(card.publicSetId);if(parent)base.sets.unshift({id:card.publicSetId,name:parent.name,code:parent.set_code,gameSlug:card.gameSlug,catalogedCount:null,complete:false});}
   const related=await listCards(new URLSearchParams({game:card.gameSlug,pageSize:'6'}),ctx);
   return {...base,card,cards:[card,...related.items.filter(c=>c.publicCardId!==id)],trend:await trend(id,filter,ctx,card)};
  }
  if(path.startsWith('/games/')){if(!ctx.games.some(g=>g.slug===path.slice(7)))return {...base,notFound:true};filter.set('game',path.slice(7));}
  if(path.startsWith('/sets/')){const id=decodeURIComponent(path.slice(6)),set=await store.getSet(id,filter,ctx);if(!set)return {...base,notFound:true};return {...base,sets:[set,...base.sets.filter(s=>s.id!==set.id)],set,cards:set.items,result:set};}
  if(!['/','/cards','/prices','/games'].includes(path)&&!path.startsWith('/games/'))throw new CatalogInputError('Unsupported page path.');
  if(path==='/')filter.set('pageSize','4');if(path==='/prices')filter.set('pageSize','48');
  const result=await listCards(filter,ctx);return {...base,cards:result.items,result};
 };
 return store;

}
