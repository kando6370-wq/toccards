import type { Env } from "../env";
import { isRecord } from "../subscription-config/model";
import { playDigest, PlayError, publisher, sealToken, tokenValid } from "./publisher";
import { syncPurchase } from "./purchases";
import { syncOrder } from "./orders";

const day = 86_400_000;
// Retain a frozen time range across pages. Advance only after every row on a page has reached the durable inbox.
export async function scanVoidedPage(env: Env,scope:string,now:Date) {
  const end = now.getTime()-60_000, earliest = end-30*day+10*60_000;
  const cursor = await env.DB.prepare(`INSERT INTO google_play_voided_cursor(scope,start_ms,end_ms) VALUES(?,?,?)
    ON CONFLICT(scope) DO UPDATE SET scope=excluded.scope RETURNING start_ms,end_ms,page_token,scanned_through_ms,revision`)
    .bind(scope,earliest,end).first<{start_ms:number;end_ms:number;page_token:string|null;scanned_through_ms:number|null;revision:number}>();
  if(!cursor || (!cursor.page_token && cursor.scanned_through_ms!==null && end-cursor.scanned_through_ms<3600_000)) return;
  const keepPage=cursor.page_token!==null && cursor.start_ms>=end-30*day;
  const start=keepPage ? cursor.start_ms : Math.max(earliest,(cursor.scanned_through_ms??earliest)-day);
  const until=keepPage ? cursor.end_ms : end;
  const params=new URLSearchParams({type:'1',startTime:String(start),endTime:String(until),maxResults:'100',includeQuantityBasedPartialRefund:'true'});
  if(keepPage) params.set('token',cursor.page_token!);
  const page=await publisher(env,`purchases/voidedpurchases?${params}`);
  if(!isRecord(page) || (page.voidedPurchases!==undefined && !Array.isArray(page.voidedPurchases)))throw new PlayError('GOOGLE_PLAY_VOIDED_UNAVAILABLE');
  const next=isRecord(page.tokenPagination) && typeof page.tokenPagination.nextPageToken==='string' ? page.tokenPagination.nextPageToken : null;
  const statements=[];
  for(const item of (page.voidedPurchases??[]) as unknown[]){
    if(!isRecord(item) || !tokenValid(item.purchaseToken) || typeof item.voidedTimeMillis!=='string' || !/^\d{1,13}$/.test(item.voidedTimeMillis)) throw new PlayError('GOOGLE_PLAY_VOIDED_UNVERIFIED');
    const order=typeof item.orderId==='string' ? item.orderId : null;
    const hash=await playDigest(env,scope,'token',item.purchaseToken);
    const key=[hash,order??'',item.voidedTimeMillis,item.voidedQuantity??''].join('/');
    statements.push(env.DB.prepare(`INSERT INTO google_play_inbox(scope,topic,message_id,kind,event_at,received_at,token_hash,token_encrypted,order_id,state,next_check_at)
      VALUES(?,'voided-purchases',?,'voided',?,?,?,?,?,'pending',?) ON CONFLICT(scope,topic,message_id) DO NOTHING`)
      .bind(scope,key,new Date(Number(item.voidedTimeMillis)).toISOString(),now.toISOString(),hash,await sealToken(env,scope,item.purchaseToken),order,now.toISOString()));
  }
  statements.push(env.DB.prepare(`UPDATE google_play_voided_cursor SET start_ms=?,end_ms=?,page_token=?,scanned_through_ms=?,revision=revision+1 WHERE scope=? AND revision=?`)
    .bind(start,until,next,next?cursor.scanned_through_ms:until,scope,cursor.revision));
  await env.DB.batch(statements);
}

// A sales report supplies the order ID only. Ownership, test status and money come from the store.
export async function reconcileOrderId(env:Env,scope:string,id:string) {
  const order=await publisher(env,`orders/${encodeURIComponent(id)}`);
  if(!isRecord(order) || order.orderId!==id || !tokenValid(order.purchaseToken))throw new PlayError('GOOGLE_PLAY_ORDER_UNVERIFIED');
  const hash=await playDigest(env,scope,'token',order.purchaseToken);
  const lookup=()=>env.DB.prepare('SELECT store_kind FROM google_play_purchase WHERE scope=? AND token_hash=? AND store_kind IS NOT NULL').bind(scope,hash).first<{store_kind:string}>();
  let purchase=await lookup();
  if(!purchase){await syncPurchase(env,scope,order.purchaseToken);purchase=await lookup();}
  if(!purchase)throw new PlayError('GOOGLE_PLAY_ORDER_UNKNOWN',409);
  await env.DB.prepare(`INSERT INTO google_play_order(scope,store_kind,order_id,token_hash,owner_id,product_id,base_plan_id,country)
    SELECT scope,store_kind,?,token_hash,owner_id,product_id,base_plan_id,country FROM google_play_purchase WHERE scope=? AND token_hash=?
    ON CONFLICT(scope,store_kind,order_id) DO NOTHING`).bind(id,scope,hash).run();
  await syncOrder(env,scope,purchase.store_kind,id);
  return {order_id:id,store_kind:purchase.store_kind};
}
