import snapshot from '../data/catalog.json' with { type: 'json' };
export const catalog = Object.freeze(snapshot);
export const cards = Object.freeze(snapshot.cards);
export const catalogVersion = snapshot.catalogVersion;
export const publicOrigin = 'https://tcgcard.fun';
export const appStoreUrl = 'https://apps.apple.com/us/app/card-ai-tcg-card-scanner/id6793017224';
export const gameLabels = Object.freeze({pokemon:'Pokémon',yugioh:'Yu-Gi-Oh!', 'one-piece':'One Piece',lorcana:'Lorcana',mtg:'Magic: The Gathering',basketball:'Basketball'});
export const hasPrice = card => typeof card.price_usd === 'number' && Number.isFinite(card.price_usd);
export const money = amount => amount === null || amount === undefined ? 'Price unavailable' : new Intl.NumberFormat('en-US',{style:'currency',currency:'USD'}).format(amount);
export const games = Object.freeze([...new Set(cards.map(c=>c.gameSlug))].map(slug=>({slug,name:gameLabels[slug]??slug,cardCount:cards.filter(c=>c.gameSlug===slug).length})));
export const sets = Object.freeze([...new Set(cards.map(c=>c.publicSetId))].map(id=>{const c=cards.find(c=>c.publicSetId===id);return {id,name:c.set_name,code:c.set_code,gameSlug:c.gameSlug,language:c.language,catalogedCount:cards.filter(c=>c.publicSetId===id).length,complete:false};}));
export function getCard(id){return cards.find(c=>c.publicCardId===id)??null;}
export function getSet(id){return sets.find(s=>s.id===id)??null;}
export class QueryError extends Error { constructor(message){super(message);this.name='QueryError';} }
export function queryCards(params=new URLSearchParams()){
 const q=(params.get('q')??'').trim();if(q.length>128)throw new QueryError('Search is limited to 128 characters.');
 const page=Number(params.get('page')??1),pageSize=Number(params.get('pageSize')??24);
 if(!Number.isSafeInteger(page)||page<1||page>10000||!Number.isSafeInteger(pageSize)||pageSize<1||pageSize>48)throw new QueryError('Invalid page or page size.');
 const allowedSort=['featured','name','price-asc','price-desc','recent'];const sort=params.get('sort')??'featured';if(!allowedSort.includes(sort))throw new QueryError('Unsupported sort.');
 const game=params.get('game')??'',set=params.get('set')??'',language=params.get('language')??'',finish=params.get('finish')??'',price=params.get('price')??'';
 if(game&&game!=='all'&&!games.some(g=>g.slug===game))throw new QueryError('Unknown game.');
 if(set&&set!=='all'&&!getSet(set))throw new QueryError('Unknown set.');
 if(language&&!['all','English','Japanese','Chinese','Not listed'].includes(language))throw new QueryError('Unknown language.');
 if(price&&!['all','available','missing','under20','20to100','over100'].includes(price))throw new QueryError('Unknown price filter.');
 if(finish&&finish!=='all'&&!cards.some(c=>(c.finish??'Not listed')===finish))throw new QueryError('Unknown finish.');
 let items=cards.filter(c=>(!q||`${c.name} ${c.set_name} ${c.card_number} ${c.set_code}`.toLowerCase().includes(q.toLowerCase()))&&(!game||game==='all'||c.gameSlug===game)&&(!set||set==='all'||c.publicSetId===set)&&(!language||language==='all'||(c.language??'Not listed')===language)&&(!finish||finish==='all'||(c.finish??'Not listed')===finish));
 if(price==='available')items=items.filter(hasPrice);if(price==='missing')items=items.filter(c=>!hasPrice(c));if(price==='under20')items=items.filter(c=>hasPrice(c)&&c.price_usd<20);if(price==='20to100')items=items.filter(c=>hasPrice(c)&&c.price_usd>=20&&c.price_usd<100);if(price==='over100')items=items.filter(c=>hasPrice(c)&&c.price_usd>=100);
 if(sort==='name')items.sort((a,b)=>a.name.localeCompare(b.name)||a.publicCardId.localeCompare(b.publicCardId));
 if(sort==='recent')items.sort((a,b)=>(b.price_as_of??'').localeCompare(a.price_as_of??'')||a.publicCardId.localeCompare(b.publicCardId));
 if(sort.startsWith('price-'))items.sort((a,b)=>{if(!hasPrice(a))return hasPrice(b)?1:a.publicCardId.localeCompare(b.publicCardId);if(!hasPrice(b))return -1;return (sort==='price-asc'?a.price_usd-b.price_usd:b.price_usd-a.price_usd)||a.publicCardId.localeCompare(b.publicCardId);});
 const total=items.length,start=(page-1)*pageSize,selected=items.slice(start,start+pageSize);
 return {items:selected,returnedCount:selected.length,total,totalKind:'exact-snapshot',page,pageSize,hasMore:start+pageSize<total,nextPage:start+pageSize<total?page+1:null,catalogVersion};
}
export function getTrend(id,params=new URLSearchParams()){
 if(params.has('days')&&params.get('days')!=='30')throw new QueryError('Only a 30-day summary is available.');
 const card=getCard(id);if(!card)return null;
 const condition=params.get('condition')??'Near Mint',grader=params.get('grader')??'Raw';
 const available=id===snapshot.trend.card_ref&&condition==='Near Mint'&&grader==='Raw';
 return {publicCardId:id,days:30,currency:'USD',condition,grader,status:available?'available':'missing',priceAsOf:card.price_as_of??null,points:available?snapshot.trend.series:[],catalogVersion};
}
export function publicEnvelope(data,requestId){return {success:true,data,meta:{requestId,catalogVersion,snapshotCapturedAt:snapshot.capturedAt,datasetMode:snapshot.mode}};}
