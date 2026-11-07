const clean = value => typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : '';
const unavailable = /^(?:unknown|not (?:listed|available|provided)|set not listed|n\/?a|none)$/i;
const meaningful = value => clean(value) && !unavailable.test(clean(value));
const dateLabel = value => {
 if (!/^\d{4}-\d{2}-\d{2}$/.test(value ?? '')) return null;
 const d = new Date(value + 'T00:00:00Z');
 return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === value ? new Intl.DateTimeFormat('en-GB', { day:'numeric', month:'short', year:'numeric', timeZone:'UTC' }).format(d) : null;
};
export function cardMetadata(card,{hasTrend=false}={}) {
 const name = clean(card.name) || 'Trading card';
 const number = clean(card.card_number);
 const set = meaningful(card.set_name) ? clean(card.set_name) : '';
 const setCode = clean(card.set_code);
 const edition=name.length>44?name.match(/^(.+?)\s+\(([^)]+)\)$/):null;
 const coreName=edition?edition[1]:name;
 const numbered=coreName+(number&&!coreName.toLowerCase().includes(number.toLowerCase())?' '+number:'');
 const identity=numbered+(edition?' ('+edition[2]+')':'');
 const scope = setCode || set;
 const hasPrice = typeof card.price_usd === 'number' && Number.isFinite(card.price_usd) && card.price_usd >= 0;
 const title = `${numbered}${scope ? ' (' + scope + ')' : ''}: ${hasPrice ? 'Price & Card Details' : 'Card Details'}${edition?' — '+edition[2]:''} | CardScanFox`;
 const printing = `${identity}${set ? ' from ' + set : ''}`;
 const observed = dateLabel(card.price_as_of);
 const context=[clean(card.language),clean(card.finish),clean(card.reference?.condition)].filter(meaningful).join(', ');
 const description = hasPrice
  ? `Check the published price of ${printing}${context?' ('+context+')':''}${observed?' as of '+observed:''}. Compare the printing and price context${hasTrend?', then view its 30-day trend':''}.`
  : `Identify ${printing}${context?' ('+context+')':''}. Compare its collector number, artwork and printing details. A published price is not currently available.`;
 return {title,description,intent:hasPrice?'exact-card-identification-and-price':'exact-card-identification',identity};
}
export function cardIndexEligibility(card, datasetMode) {
 const reasons = [];
 const id = clean(card.publicCardId ?? card.card_ref);
 if (datasetMode !== 'published-read-only' && datasetMode !== 'published-export') reasons.push('review-or-unverified-dataset');
 if (!id || /^\.{1,2}$/.test(id) || id.length > 128 || typeof (card.publicCardId??card.card_ref)!=='string' || /[\u0000-\u001f]/.test(card.publicCardId??card.card_ref) || (card.publicCardId??card.card_ref)!==(card.publicCardId??card.card_ref).trim()) reasons.push('missing-stable-id');
 if (!meaningful(card.name) || clean(card.name) === id) reasons.push('missing-card-name');
 if (!meaningful(card.set_name)) reasons.push('missing-set');
 if (!meaningful(card.card_number)) reasons.push('missing-collector-number');
 if (card.canonicalPublicCardId && card.canonicalPublicCardId !== id) reasons.push('alternate-record');
 if (card.indexingStatus === 'needsReview' || card.indexingStatus === 'withdrawn') reasons.push('record-needs-review');
 const image = clean(card.image_url);
 if (!image || (!image.startsWith('/assets/cards/') && !/^https:\/\/image\.tcgcard\.fun\/cards\/[^?#]+$/.test(image))) reasons.push('missing-public-catalog-artwork');
 return {eligible:reasons.length===0,reasons,id};
}
export function cardIdentityKey(card) {
 return JSON.stringify([clean(card.gameSlug??card.game),clean(card.sourceSetId??card.set_code),clean(card.set_name),clean(card.card_number),clean(card.name)]);
}
export function cardContentSignature(card) {
 return JSON.stringify([cardIdentityKey(card),card.image_url??null,card.rarity??null,card.reference??null,card.price_usd??null,card.price_as_of??null]);
}
