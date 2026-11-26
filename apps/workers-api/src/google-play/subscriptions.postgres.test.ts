import { URL } from "node:url";
import { readFileSync } from "node:fs";
import { generateKeyPairSync } from "node:crypto";
import { hashPassword, signAccessToken } from "@kando/auth-core";
import { afterAll, beforeAll, expect, it, vi } from "vitest";
import { app } from "../app";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { insertPlatformSession } from "./session-build";
import { accountRef, syncPurchase } from "./purchases";
import { googlePlayAccess, googlePlayScope } from "./access";
import { orderFacts, syncOrder } from "./orders";
import { playDigest } from "./publisher";
import { reserveScanQuota, settleScanQuota } from "../scan/quota";

let db: PGliteDatabase, env: Env, scope: string;
const now = new Date(), past = new Date(now.getTime()-10*86400_000).toISOString(), future = new Date(now.getTime()+86400_000).toISOString();
const owner = { platform: "android", owner_id: "android", owner_type: "user", user_id: "identity", data_space_id: "android", session_id: "new-install" } as const;
const plan = { productId: "premium", offerDetails: { basePlanId: "monthly" }, autoRenewingPlan: { autoRenewEnabled: true }, expiryTime: future, latestSuccessfulOrderId: "GPA.fixture..1" };
let reference: string, acknowledgements = 0, state = "ACTIVE", testPurchase = false;
const token = "verified-fixture-token", usd = (units: string, nanos: number) => ({ currencyCode: "USD", units, nanos });
const order = { orderId: plan.latestSuccessfulOrderId, purchaseToken: token, total: usd("4",990000000), orderHistory: {
  processedEvent: {eventTime: now.toISOString()}, partialRefundEvents: [{state:"PROCESSED_SUCCESSFULLY",processTime:future, refundDetails:{total:usd("1",0)}}],
} };
beforeAll(async () => {
  db = await PGliteDatabase.create();
  for (const name of ["0000_business_schema", "0006_mutation_lock", "0018_platform_account_isolation", "0019_google_play_subscriptions"]) {
    await db.exec(readFileSync(new URL(`../db/postgres/migrations/${name}.sql`, import.meta.url), "utf8"));
  }
  const key = generateKeyPairSync("rsa", {modulusLength:2048}).privateKey.export({format:"pem",type:"pkcs8"}).toString();
  env = { DB: db, APP_ENVIRONMENT: "development", GOOGLE_PLAY_PACKAGE_NAME: "com.example.fixture", GOOGLE_PLAY_TOKEN_HASH_KEY:"A".repeat(43),
    GOOGLE_PLAY_ENCRYPTION_KEYS:`first:${"B".repeat(43)}`, GOOGLE_PLAY_PUBLISHER_EMAIL:"fixture@invalid.example",GOOGLE_PLAY_PUBLISHER_PRIVATE_KEY:key,
    JWT_SECRET:"independent-play-integration-fixture-jwt",CACHE_KV:{} as KVNamespace };
  scope = googlePlayScope(env)!;
  await db.query(`INSERT INTO "user"(id,email,created_at,updated_at) VALUES ('identity','fixture@example.invalid',$1,$1)`, [past]);
  await db.query(`INSERT INTO platform_account(id,user_id,platform,created_at,updated_at) VALUES ('ios','identity','ios',$1,$1),('android','identity','android',$2,$2)`,[past,now.toISOString()]);
  await db.query(`SELECT google_play_prepare_rollout($1,$2,222)`,[scope,past]);
  const sessionSql = `INSERT INTO session(id,owner_type,owner_id,user_id,platform,refresh_token,expires_at,created_at) VALUES (?,'user',?,'identity',?,?,?,?)`;
  for(const [id, space, platform, version] of [["new-install","android","android",222],["old-install","android","android",221],["apple","ios","ios",0]] as const) {
    await insertPlatformSession(db, version ? { package_name:env.GOOGLE_PLAY_PACKAGE_NAME!,version_code:version,certificate_digest:"test",verified_at:now.toISOString() } : undefined,
      sessionSql,id,space,platform,id,future,past).run();
  }
  await db.query(`UPDATE google_play_rollout SET metering_enabled=true,sales_enabled=true WHERE scope=$1`,[scope]);
  await db.query(`INSERT INTO google_play_product(scope,product_id,base_plan_id,revenue_event) VALUES($1,'premium','monthly','android_month')`,[scope]);
  reference = await accountRef(env,scope,owner.owner_id);
  vi.stubGlobal("fetch",vi.fn(async (url: string) => {
    if (url === "https://oauth2.googleapis.com/token") return Response.json({access_token:"fixture-google-auth",expires_in:3600});
    if (url.includes("/basePlans/monthly/offers?")) return Response.json({subscriptionOffers:[]});
    if (url.includes("/subscriptions?")) return Response.json({subscriptions:[{packageName:env.GOOGLE_PLAY_PACKAGE_NAME, productId:"premium", basePlans:[{basePlanId:"monthly",state:"ACTIVE",autoRenewingBasePlanType:{},regionalConfigs:[{regionCode:"US",newSubscriberAvailability:true}]}]}]});
    if (url.includes("/orders/")) return Response.json(order);
    if (url.endsWith(":acknowledge")) { acknowledgements++; return new Response(null,{status:204}); }
    if (!url.includes("/purchases/subscriptionsv2/tokens/")) throw new Error("Unexpected network request");
    return Response.json({ kind:"androidpublisher#subscriptionPurchaseV2",subscriptionState:`SUBSCRIPTION_STATE_${state}`,
      acknowledgementState:acknowledgements || testPurchase ? "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED" : "ACKNOWLEDGEMENT_STATE_PENDING",
      ...(testPurchase ? {testPurchase:{}} : {}),externalAccountIdentifiers:{obfuscatedExternalAccountId:reference},lineItems:[plan] });
  }));
});
afterAll(async () => {vi.unstubAllGlobals(); await db?.close();});
async function request(path: string, session: string, store: string, init: RequestInit = {}) {
  const auth = await signAccessToken({owner_type:"user",owner_id:store,session_id:session},env.JWT_SECRET);
  return app.request(`/api/v1/${path}`,{...init, headers:{Authorization:`Bearer ${auth}`,"Content-Type":"application/json", ...init.headers}},env);
}
it("meters only the approved build on this device and never charges historical free scans to a new cohort",async () => {
  expect((await googlePlayAccess(env,{...owner,session_id:"old-install"})).access_policy).toBe("free_launch");
  expect((await googlePlayAccess(env,owner)).access_policy).toBe("metered");
  const legacy = await reserveScanQuota(db,owner,"old-reservation","free",now,{unlimited:true,startProcessing:false});
  expect(legacy.status).toBe("reserved");
  for(let i=0;i<10;i++) {
    expect((await reserveScanQuota(db,owner,`new-${i}`,"free",now,{cohort:scope})).status).toBe("reserved");
    await settleScanQuota(db,owner,`new-${i}`,"consumed",null,null,now,scope);
  }
  expect((await reserveScanQuota(db,owner,"eleventh","free",now,{cohort:scope})).status).toBe("exhausted");
  expect((await reserveScanQuota(db,owner,"old-reservation","free",now,{cohort:scope})).status).toBe("reserved");
});
it("verifies against Play, delivers only to the bound Android space and keeps repeat verification and refunds idempotent",async () => {
  const id = crypto.randomUUID(), args={method:"POST",headers:{"Idempotency-Key":id},body:JSON.stringify({purchase_token:token})};
  expect((await request("entitlements/google/verify","apple","ios",args)).status).toBe(403);
  const first = await request("entitlements/google/verify","new-install","android",args);
  expect([first.status,await first.json()]).toMatchObject([200,{data:{premium:true}}]);
  expect((await request("entitlements/google/verify","new-install","android",args)).status).toBe(200);
  expect(acknowledgements).toBe(1);
  expect((await request("entitlements/google/verify","new-install","android",{...args,body:JSON.stringify({purchase_token:"other"})})).status).toBe(409);
  expect((await googlePlayAccess({...env,APP_ENVIRONMENT:"production"},owner)).premium).toBe(false);
  await expect(syncPurchase(env,scope,token,"different-space")).rejects.toMatchObject({code:"GOOGLE_PLAY_OWNER_CONFLICT"});
  expect((await googlePlayAccess(env,owner)).premium).toBe(true);
  await syncOrder(env,scope,"live",order.orderId);
  await syncOrder(env,scope,"live",order.orderId);
  expect((await db.query(`SELECT kind,usd_micros::int FROM google_play_order_event ORDER BY event_at`)).rows).toEqual([{kind:"charge",usd_micros:4990000},{kind:"refund",usd_micros:1000000}]);
  expect((await db.query('SELECT COUNT(*)::int AS n FROM billing_purchase_chain')).rows).toEqual([{n:0}]);
  state="ON_HOLD";
  expect((await syncPurchase(env,scope,token,owner.owner_id)).premium).toBe(false);
  state="CANCELED";
  expect((await syncPurchase(env,scope,token,owner.owner_id)).premium).toBe(true);
});
it("allows test access only for approved Android spaces and keeps test orders independent",async () => {
  testPurchase=true; state="ACTIVE";
  await expect(syncPurchase(env,scope,"test-purchase",owner.owner_id)).rejects.toMatchObject({code:"GOOGLE_PLAY_TEST_SPACE_REQUIRED"});
  await db.query("INSERT INTO google_play_test_space VALUES($1,$2)",[scope,owner.owner_id]);
  expect((await syncPurchase(env,scope,"test-purchase",owner.owner_id)).premium).toBe(true);
  const hash = await playDigest(env,scope,"token","test-purchase");
  expect((await db.query(`SELECT store_kind,token_encrypted FROM google_play_purchase WHERE token_hash=$1`,[hash])).rows[0]).toMatchObject({store_kind:"test",token_encrypted:expect.not.stringContaining("test-purchase")});
  testPurchase=false;
});
it("clips a final refund to the unpaid balance and preserves previously processed partial refunds",() => {
  const facts=orderFacts({...order,orderHistory:{...order.orderHistory,refundEvent:{eventTime:future,refundDetails:{total:order.total}}}},order.orderId);
  expect(facts.events.map(item=>item.amount)).toEqual([4990000,1000000,3990000]);
});
it("publishes approved Google placements with scoped role checks, revisions and an idempotent audit, leaving Apple configuration independent",async()=>{
  for(const role of ["super_admin","operator"]){
    await db.prepare(`INSERT INTO admin_user(id,email,password_hash,role,status,created_at) VALUES(?,?,?,?,'active',?)`)
      .bind(role,`${role}@example.invalid`,await hashPassword("test-only-password"),role,past).run();
  }
  async function adminToken(name:string){
    const res=await app.request('/api/v1/admin/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`${name}@example.invalid`,password:'test-only-password'})},env);
    expect(res.status).toBe(200); return (await res.json() as {data:{access_token:string}}).data.access_token;
  }
  const operator=await adminToken('operator'), admin=await adminToken('super_admin');
  const call=(path:string,bearer:string,body?:unknown)=>app.request(`/api/v1/admin/google-play/${path}`,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${bearer}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})},env);
  const product={product_id:'premium',base_plan_id:'monthly',offer_id:'',revenue_event:'card_android_month',reason:'monthly plan fixture',request_id:crypto.randomUUID(),expected_revision:1};
  expect((await call('products',operator,product)).status).toBe(403);
  expect((await call('products',admin,product)).status).toBe(200);
  expect((await call('products',admin,product)).status).toBe(200);
  expect((await call('products',admin,{...product,expected_revision:1,request_id:crypto.randomUUID()})).status).toBe(409);
  const draft={placement:'page',operation:'save',expected_revision:0,request_id:crypto.randomUUID(),reason:'display fixture',draft:{title:'Premium',plans:[{...product,label:'Monthly',is_default:true}]}};
  expect((await call('configs',operator,draft)).status).toBe(200);
  expect((await call('configs',operator,{...draft,operation:'enable',request_id:crypto.randomUUID(),expected_revision:1})).status).toBe(200);
  const catalog=await request('google-play/catalog','new-install','android');
  expect(await catalog.json()).toMatchObject({data:{status:'configured',config:{title:'Premium'}}});
  const legacyGoogle=await app.request('/api/v1/subscription-supported-products?platform=google',{},env);
  expect(await legacyGoogle.json()).toMatchObject({data:{products:[]}});
  const list=await call('orders?store_kind=live',operator);
  expect(await list.json()).toMatchObject({data:{scope,summary:{order_count:1,gross_usd_micros:4990000,refund_usd_micros:1000000,net_usd_micros:3990000}}});
  const exported=await call('orders/export?store_kind=live',operator);
  expect(exported.status).toBe(200); expect(new Uint8Array(await exported.arrayBuffer()).slice(0,2)).toEqual(new Uint8Array([80,75]));
});
