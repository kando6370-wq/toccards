import { URL } from "node:url";
import { readFileSync } from "node:fs";
import { parseEnv } from "node:util";
import { generateKeyPairSync, sign as rsaSign } from "node:crypto";
import { hashPassword, signAccessToken } from "@kando/auth-core";
import { afterAll, beforeAll, beforeEach, expect, it, vi } from "vitest";
import { app } from "../app";
import type { Env } from "../env";
import { PGliteDatabase } from "../test-support/pglite-database";
import { insertPlatformSession } from "./session-build";
import { accountRef, syncPurchase } from "./purchases";
import { googlePlayAccess, googlePlayScope } from "./access";
import { orderFacts, syncOrder } from "./orders";
import { processPlayInbox } from "./notifications";
import { reconcileOrderId, scanVoidedPage } from "./reconcile";
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
let fixtureResponse: ((url: string) => Response | Promise<Response> | undefined) | undefined;
beforeEach(() => { fixtureResponse = undefined; });
beforeAll(async () => {
  db = await PGliteDatabase.create();
  for (const name of ["0000_business_schema", "0006_mutation_lock", "0018_platform_account_isolation", "0019_google_play_subscriptions", "0020_google_play_first_charge", "0021_google_play_notification_details"]) {
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
    const override = fixtureResponse?.(url);
    if (override) return override;
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
it("opens the Google admin pages in the Linux dev template before any Play credentials or purchases exist", async () => {
  const sample = parseEnv(readFileSync(new URL("../../../../deploy/linux/.env.example", import.meta.url), "utf8"));
  const beta: Env = { ...sample, DB: db, CACHE_KV: env.CACHE_KV, JWT_SECRET: env.JWT_SECRET };
  const email = "beta-reports@example.invalid", password = "report-fixture";
  await db.prepare("INSERT INTO admin_user(id,email,password_hash,role,status,created_at) VALUES('beta-reports',?,?,'operator','active',?)")
    .bind(email, await hashPassword(password), past).run();
  const login = await app.request("/api/v1/admin/auth/login", { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({email, password}) }, beta);
  expect(login.status).toBe(200);
  const {data} = await login.json() as { data: { access_token: string } };
  const headers = { Authorization: `Bearer ${data.access_token}` };
  const betaScope = "development:google_play:com.kando.kandoApp.beta";
  const pages = {
    notifications: { scope: betaScope, total: 0, rows: [] }, "notifications/options": { kinds: [], skus: [] },
    products: { scope: betaScope, approved: [], catalog: null }, configs: { scope: betaScope, rows: [] },
    orders: { scope: betaScope, rows: [], summary: { order_count: 0 } },
  };
  for (const [path, expected] of Object.entries(pages)) {
    const response = await app.request(`/api/v1/admin/google-play/${path}`, {headers}, beta);
    expect(response.status, path).toBe(200);
    expect(await response.json()).toMatchObject({ success: true, data: expected });
  }
  expect(await googlePlayAccess(beta, owner)).toMatchObject({ access_policy: "free_launch", sales_available: false, can_purchase: false });
  const refresh = await app.request("/api/v1/admin/google-play/products?refresh=1", {headers}, beta);
  expect(refresh.status).toBe(503);
  expect(await refresh.json()).toMatchObject({ success: false, error: { code: "GOOGLE_PLAY_UNAVAILABLE" } });
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
  expect(await list.json()).toMatchObject({data:{scope,summary:{order_count:1,active_chains:1,gross_usd_micros:4990000,refund_usd_micros:1000000,net_usd_micros:3990000}}});
  const exported=await call('orders/export?store_kind=live',operator);
  expect(exported.status).toBe(200); expect(new Uint8Array(await exported.arrayBuffer()).slice(0,2)).toEqual(new Uint8Array([80,75]));
});

it("authenticates the Pub/Sub sender and uses the current store state for duplicate and out-of-order messages", async () => {
  const keys = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const audience = "https://api.example.invalid/google-play/notifications";
  const email = "push@fixture.invalid", topic = "projects/fixture/topics/play";
  const pushEnv = { ...env, GOOGLE_PLAY_PUSH_EMAIL: email, GOOGLE_PLAY_PUSH_AUDIENCE: audience,
    GOOGLE_PLAY_PUSH_SUBSCRIPTION: "projects/fixture/subscriptions/play", GOOGLE_PLAY_TOPIC: topic };
  fixtureResponse = url => url.endsWith("/oauth2/v3/certs")
    ? Response.json({ keys: [{ ...keys.publicKey.export({ format: "jwk" }), kid: "fixture", alg: "RS256" }] }) : undefined;
  function signed(aud = audience, principal = email) {
    const iat = Math.floor(Date.now() / 1000);
    const encode = (part: unknown) => Buffer.from(JSON.stringify(part)).toString("base64url");
    const data = encode({ alg: "RS256", typ: "JWT", kid: "fixture" }) + "." + encode({ iss: "https://accounts.google.com",
      aud, email: principal, email_verified: true, iat, exp: iat + 300 });
    return data + "." + rsaSign("RSA-SHA256", Buffer.from(data), keys.privateKey).toString("base64url");
  }
  const push = (id: string, event: object, bearer = signed(), time = now.getTime()) => app.request("/api/v1/google-play/notifications", {
    method: "POST", headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
    body: JSON.stringify({ subscription: pushEnv.GOOGLE_PLAY_PUSH_SUBSCRIPTION, message: { messageId: id,
      data: Buffer.from(JSON.stringify({ packageName: env.GOOGLE_PLAY_PACKAGE_NAME, eventTimeMillis: String(time), ...event })).toString("base64") } }),
  }, pushEnv);
  const change = { subscriptionNotification: { notificationType: 3, purchaseToken: token } };
  expect((await push("bad-audience", change, signed("another-service"))).status).toBe(401);
  expect((await push("bad-principal", change, signed(audience, "other@fixture.invalid"))).status).toBe(401);
  expect((await push("probe", { testNotification: {} })).status).toBe(204);
  expect((await push("review", { pendingRefundReviewNotification: { orderId: order.orderId } })).status).toBe(204);
  expect((await push("newer", change)).status).toBe(204);
  expect((await push("newer", change)).status).toBe(204);
  expect((await push("older", { subscriptionNotification: { notificationType: 13, purchaseToken: token } }, signed(), now.getTime()-60_000)).status).toBe(204);
  state = "ACTIVE";
  const later = new Date(Date.now()+1000);
  await processPlayInbox(pushEnv, scope, later);
  await processPlayInbox(pushEnv, scope, later);
  expect((await db.query("SELECT message_id,state,attempts FROM google_play_inbox WHERE topic=$1 ORDER BY message_id", [topic])).rows).toEqual([
    { message_id:"newer", state:"processed", attempts:1 }, { message_id:"older", state:"processed", attempts:1 },
    { message_id:"probe", state:"received_test", attempts:0 }, { message_id:"review", state:"quarantined", attempts:0 },
  ]);
  expect((await googlePlayAccess(env, owner)).premium).toBe(true);

  // These share numeric types with subscriptions. Persist diagnostics without enqueueing a subscription or exposing credentials.
  const inboxCount = await db.query("SELECT COUNT(*)::int AS n FROM google_play_order_event");
  const oneTime = {version:"1.0", notificationType:2, sku:"pack.one", purchaseToken:token, obfuscatedAccountId:"private-account"};
  expect((await push("product", {oneTimeProductNotification:oneTime})).status).toBe(204);
  expect((await push("product", {oneTimeProductNotification:{...oneTime, notificationType:1}})).status).toBe(204);
  expect((await push("mixed", {...change, oneTimeProductNotification:oneTime})).status).toBe(422);
  for (const refundType of [1,2]) {
    expect((await push("void-" + refundType, {voidedPurchaseNotification:{productType:2, refundType, orderId:order.orderId, purchaseToken:token}})).status).toBe(204);
  }
  expect((await push("chargeback", {pendingRefundReviewNotification:{orderId:order.orderId,refundReason:7,pendingRefundToken:"private-review",obfuscatedProfileId:"private-profile"}})).status).toBe(204);
  expect((await push("unmapped", {subscriptionNotification:{notificationType:24,purchaseToken:token}})).status).toBe(204);
  const diagnostics = await db.query<{message_id:string}>("SELECT message_id,kind,state,redacted_payload FROM google_play_inbox WHERE topic=$1 ORDER BY message_id",[topic]);
  const events = Object.fromEntries(diagnostics.rows.map(row => [row.message_id,row]));
  expect(events.product).toMatchObject({kind:"one_time:2",state:"quarantined",redacted_payload:{oneTimeProductNotification:{sku:"pack.one",notificationType:2}}});
  for (const refundType of [1,2]) expect(events["void-"+refundType]).toMatchObject({kind:"voided:"+refundType,state:"quarantined"});
  expect(events.chargeback).toMatchObject({kind:"refund_review",state:"quarantined",redacted_payload:{pendingRefundReviewNotification:{refundReason:7}}});
  expect(events.unmapped).toMatchObject({kind:"subscription:24",state:"quarantined"});
  expect(events.older).toMatchObject({kind:"subscription:13",redacted_payload:{subscriptionNotification:{notificationType:13}}});
  expect(events.probe).toMatchObject({kind:"test",redacted_payload:{testNotification:{}}});
  expect(JSON.stringify(events)).not.toMatch(/private-account|private-review|private-profile|purchaseToken|verified-fixture-token|obfuscatedAccountId|pendingRefundToken/i);
  expect((await db.query("SELECT COUNT(*)::int AS n FROM google_play_order_event")).rows).toEqual(inboxCount.rows);
});

it("limits operator notification search, options and redacted details to the configured scope and exact topic", async () => {
  const topic = "projects/fixture/topics/admin-inbox", otherTopic = topic + "-second";
  const reportEnv = {...env, GOOGLE_PLAY_PACKAGE_NAME:"com.example.fixture.inbox", GOOGLE_PLAY_TOPIC:topic};
  const reportScope = googlePlayScope(reportEnv)!;
  const otherScope = googlePlayScope({...reportEnv, APP_ENVIRONMENT:"production"})!;
  const stamp = "2026-01-06T00:00:00.000Z", end = "2026-01-07T00:00:00.000Z";
  const hash = await playDigest(reportEnv,reportScope,"token","admin-inbox-purchase");
  const insert = (scopeValue: string, source: string, id: string, kind: string, received: string, snapshot: object | null) =>
    db.prepare(`INSERT INTO google_play_inbox(scope,topic,message_id,kind,event_at,received_at,state,token_hash,redacted_payload)
      VALUES(?,?,?,?,'2025-12-01T00:00:00.000Z',?,'failed',?,?::jsonb)`)
      .bind(scopeValue,source,id,kind,received,hash,snapshot && JSON.stringify(snapshot)).run();
  await db.prepare(`INSERT INTO google_play_purchase(scope,token_hash,token_encrypted,chain_id,owner_id,store_kind,product_id,latest_order_id)
    VALUES(?,?,'secret-ciphertext','abcdef123456789','android','live','notify-monthly','GPA.notify-latest')`).bind(reportScope,hash).run();
  await db.prepare(`INSERT INTO google_play_order(scope,token_hash,store_kind,order_id) VALUES(?,?,'live','GPA.notify-previous')`).bind(reportScope,hash).run();
  await insert(reportScope,topic,"lookup","subscription:2",stamp,{subscriptionNotification:{version:"1.0",notificationType:2}});
  await insert(reportScope,otherTopic,"lookup","voided",stamp,null);
  await insert(reportScope,topic,"outside","subscription:2",end,null);
  await insert(otherScope,topic,"lookup","one_time:99",stamp,{oneTimeProductNotification:{sku:"foreign-sku"}});
  await db.prepare("INSERT INTO google_play_inbox(scope,topic,message_id,kind,event_at,received_at,state) VALUES(?,?,'only-a-probe','test',?,?,'received_test')")
    .bind(reportScope,topic,stamp,stamp).run();
  async function adminHeaders(role: "operator" | "super_admin") {
    const user = "notification-" + role;
    await db.prepare("INSERT INTO admin_user(id,email,password_hash,role,status,created_at) VALUES(?,?,?,?,'active',?)")
      .bind(user,user+"@example.invalid",await hashPassword("notification-fixture"),role,past).run();
    const login = await app.request("/api/v1/admin/auth/login",{method:"POST",headers:{"Content-Type":"application/json"},
      body:JSON.stringify({email:user+"@example.invalid",password:"notification-fixture"})},reportEnv);
    expect(login.status).toBe(200);
    const {data:{access_token}} = await login.json() as {data:{access_token:string}};
    return {Authorization:"Bearer "+access_token,"Content-Type":"application/json"};
  }
  const headers = await adminHeaders("operator");
  const base = "/api/v1/admin/google-play/notifications";
  const get = async (path: string) => {
    const res = await app.request(base+path,{headers},reportEnv);
    expect(res.status).toBe(200);
    return (await res.json() as {data:Record<string,unknown>}).data;
  };
  const filters = new URLSearchParams({message_id:"lookup",family:"subscription",event_kind:"subscription:2",uid:"android",state:"failed",store_kind:"live",
    sku:"notify-monthly",order_id:"GPA.notify-previous",chain:"abcdef123456",from:stamp,to:end,scope:otherScope});
  const list = await get("?"+filters);
  expect(list).toMatchObject({scope:reportScope,total:1,rows:[{topic,kind:"subscription:2",order_id:null,owner_id:"android",total:1}]});
  expect(JSON.stringify(list)).not.toMatch(/redacted_payload|token_encrypted|token_hash|secret-ciphertext/);
  expect(await get("?"+filters+"&page=2")).toMatchObject({total:1,rows:[]});
  expect(await get("?family=subscription&sku=notify-monthly&from="+stamp+"&to="+end)).toMatchObject({total:1});
  expect((await app.request(base+"?from="+end+"&to="+stamp,{headers},reportEnv)).status).toBe(422);
  expect(await get("?message_id=only-a-probe&store_kind=unknown")).toMatchObject({total:0});
  expect(await get("?message_id=only-a-probe&store_kind=probe")).toMatchObject({total:1});
  const options = await get("/options");
  expect(options.skus).toContain("notify-monthly");
  expect(JSON.stringify(options)).not.toMatch(/foreign-sku|one_time:99/);
  const url = (source: string) => "/detail?"+new URLSearchParams({topic:source,message_id:"lookup"});
  const detail = await get(url(topic));
  expect(detail).toMatchObject({scope:reportScope,topic,kind:"subscription:2",redacted_payload:{subscriptionNotification:{notificationType:2}},latest_order_id:"GPA.notify-latest"});
  expect(JSON.stringify(detail)).not.toMatch(/secret-ciphertext|token_encrypted|token_hash|foreign-sku/);
  expect(await get(url(otherTopic))).toMatchObject({topic:otherTopic,kind:"voided",redacted_payload:null});
  expect((await app.request(base+url("missing"),{headers},reportEnv)).status).toBe(404);
  expect((await app.request(base+url(topic),{},reportEnv)).status).toBe(401);
  const retryBody = {topic,message_id:"lookup",reason:"商店恢复服务后重试",expected_revision:0,request_id:crypto.randomUUID()};
  const retry = (authorization: typeof headers) => app.request("/api/v1/admin/google-play/retry",{method:"POST",headers:authorization,body:JSON.stringify(retryBody)},reportEnv);
  expect((await retry(headers)).status).toBe(403);
  const superAdmin = await adminHeaders("super_admin");
  expect((await retry(superAdmin)).status).toBe(200);
  expect((await retry(superAdmin)).status).toBe(200);
  expect(await get(url(topic))).toMatchObject({state:"pending"});
  expect(await get(url(otherTopic))).toMatchObject({state:"failed"});
  expect((await db.query("SELECT reason FROM google_play_audit WHERE scope=$1 AND action='retry'",[reportScope])).rows).toEqual([{reason:retryBody.reason}]);
});

it("retains the verified owner when a replacement arrives first and an old token is later restored", async () => {
  const oldToken = "predecessor-fixture", newToken = "replacement-fixture";
  fixtureResponse = url => {
    if (!url.endsWith(oldToken) && !url.endsWith(newToken)) return undefined;
    return Response.json({kind:"androidpublisher#subscriptionPurchaseV2", subscriptionState:"SUBSCRIPTION_STATE_ACTIVE",
      acknowledgementState:"ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED", externalAccountIdentifiers:{obfuscatedExternalAccountId:reference},
      ...(url.endsWith(newToken) ? {linkedPurchaseToken:oldToken} : {}), lineItems:[{...plan, latestSuccessfulOrderId:undefined}]});
  };
  expect((await syncPurchase(env, scope, newToken, owner.owner_id)).premium).toBe(true);
  expect((await syncPurchase(env, scope, oldToken, owner.owner_id)).premium).toBe(false);
  await expect(syncPurchase(env, scope, oldToken, "another-owner")).rejects.toMatchObject({code:"GOOGLE_PLAY_OWNER_CONFLICT"});
  const oldHash = await playDigest(env,scope,"token",oldToken);
  expect((await db.query("SELECT owner_id,granted,superseded FROM google_play_purchase WHERE token_hash=$1",[oldHash])).rows)
    .toEqual([{owner_id:owner.owner_id,granted:false,superseded:true}]);
});

it("resumes failed voided pages, overlaps completed windows and reconciles an expired token's historical order", async () => {
  await syncPurchase(env,scope,token,owner.owner_id);
  const id = "GPA.fixture..historical", windows: URLSearchParams[] = [];
  const voided = { orderId:id, purchaseToken:token, voidedTimeMillis:String(now.getTime()-120_000) };
  let page = 0;
  fixtureResponse = url => {
    if (url.includes("/purchases/voidedpurchases?")) {
      windows.push(new URL(url).searchParams);
      page++;
      if (page === 2) return new Response(null,{status:503});
      return Response.json({voidedPurchases:[voided], ...(page === 1 ? {tokenPagination:{nextPageToken:"page2"}} : {})});
    }
    if (url.endsWith(`/orders/${id}`)) return Response.json({...order,orderId:id});
    if (url.endsWith(`/tokens/${token}`)) return new Response(null,{status:410});
    return undefined;
  };
  await scanVoidedPage(env,scope,now);
  await expect(scanVoidedPage(env,scope,now)).rejects.toMatchObject({code:"GOOGLE_PLAY_UPSTREAM_UNAVAILABLE"});
  await scanVoidedPage(env,scope,now);
  expect(windows.map(q=>q.get("token"))).toEqual([null,"page2","page2"]);
  expect(windows[2].get("startTime")).toBe(windows[0].get("startTime"));
  expect(windows[2].get("endTime")).toBe(windows[0].get("endTime"));
  await scanVoidedPage(env,scope,new Date(now.getTime()+7200_000));
  expect(Number(windows[3].get("startTime"))).toBe(Number(windows[0].get("endTime"))-86400_000);
  await processPlayInbox(env,scope,new Date(now.getTime()+1000));
  expect((await db.query("SELECT state,attempts FROM google_play_inbox WHERE topic='voided-purchases'")).rows).toEqual([{state:"processed",attempts:1}]);
  await reconcileOrderId(env,scope,id);
  expect((await db.query("SELECT kind,amount_micros::int AS amount FROM google_play_order_event WHERE order_id=$1 ORDER BY kind",[id])).rows)
    .toEqual([{kind:"charge",amount:4990000},{kind:"refund",amount:1000000}]);
});

it("keeps the newer refund when an earlier order lookup finishes last", async () => {
  await syncPurchase(env,scope,token,owner.owner_id);
  let announce!: () => void, deliver!: (response: Response) => void;
  const started = new Promise<void>(resolve => { announce = resolve; });
  const slow = new Promise<Response>(resolve => { deliver = resolve; });
  let calls = 0;
  fixtureResponse = url => {
    if (!url.endsWith(`/orders/${order.orderId}`)) return undefined;
    if (++calls === 1) { announce(); return slow; }
    return Response.json({ ...order, orderHistory: { ...order.orderHistory,
      refundEvent: { eventTime: future, refundDetails: { total: order.total } } } });
  };
  const first = syncOrder(env, scope, "live", order.orderId);
  await started;
  await syncOrder(env, scope, "live", order.orderId);
  deliver(Response.json(order));
  await expect(first).rejects.toMatchObject({ code: "GOOGLE_PLAY_ORDER_CHANGED" });
  expect((await db.query("SELECT SUM(amount_micros)::int AS amount FROM google_play_order_event WHERE order_id=$1 AND kind='refund'", [order.orderId])).rows)
    .toEqual([{amount:4990000}]);
});

it("attributes only the first verified live charge and lets a single installation finish a handoff after interruption", async () => {
  const revenueToken = "singular-live-fixture", firstId = "GPA.first", renewalId = "GPA.next";
  const purchaseHash = await playDigest(env, scope, "token", revenueToken);
  const subscription = {kind:"androidpublisher#subscriptionPurchaseV2", startTime:past, subscriptionState:"SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState:"ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED", externalAccountIdentifiers:{obfuscatedExternalAccountId:reference},
    lineItems:[{...plan,latestSuccessfulOrderId:firstId}]};
  const period = (start: string, end: string, trial = false) => [{productId:"premium", subscriptionDetails:{basePlanId:"monthly",
    servicePeriodStartTime:start,servicePeriodEndTime:end,offerPhaseDetails:trial?{freeTrialDetails:{}}:{baseDetails:{}}}}];
  const paidOrder = (id: string, purchaseToken: string, start: string, end: string) => ({orderId:id, purchaseToken,
    lineItems:period(start,end),total:usd("4",990000000),orderHistory:{processedEvent:{eventTime:now.toISOString()}}});
  const purchases: Record<string,unknown> = {[revenueToken]:subscription};
  const orders: Record<string,object> = {[firstId]:paidOrder(firstId,revenueToken,past,future), [renewalId]:paidOrder(renewalId,revenueToken,future,future)};
  fixtureResponse = url => {
    const key = url.split('/').at(-1)!;
    if (url.includes('/orders/') && key in orders) return Response.json(orders[key]);
    if (url.includes('/tokens/') && key in purchases) return Response.json(purchases[key]);
    return undefined;
  };
  const install = crypto.randomUUID(), other = crypto.randomUUID();
  const claim = async (device:string,platform="android",reported?:string) => {
    const result = await request("entitlements/google/attribution",platform==="ios" ? "apple" : "new-install",platform,
      {method:"POST",body:JSON.stringify({installation_id:device,handed_off_order:reported})});
    if (platform === "ios") { expect(result.status).toBe(403); return null; }
    expect(result.status).toBe(200);
    return (await result.json() as {data:{receipt?:{order_id:string}}}).data.receipt ?? null;
  };
  await db.query("UPDATE google_play_product SET revenue_event='android_first_live' WHERE scope=$1",[scope]);
  await db.query("INSERT INTO google_play_test_space VALUES($1,$2) ON CONFLICT DO NOTHING",[scope,owner.owner_id]);
  await syncPurchase(env,scope,revenueToken,owner.owner_id);
  expect(await claim(install)).toBeNull();
  env.GOOGLE_PLAY_SINGULAR_SDK_FROM = past;
  try {
    await reconcileOrderId(env,scope,renewalId);
    expect(await claim(install)).toBeNull();
    await syncOrder(env,scope,"live",firstId);
    await claim(install,"ios");
    const receipt = await claim(install);
    expect(receipt).toMatchObject({scope,order_id:firstId,event_name:"android_first_live",currency:"USD",amount_micros:"4990000"});
    expect(await claim(other)).toBeNull();
    expect(await claim(install)).toEqual(receipt);
    await claim(other,"android",firstId);
    expect(await claim(install)).toEqual(receipt);
    await claim(install,"android",firstId);
    await syncOrder(env,scope,"live",firstId);
    expect(await claim(install)).toBeNull();
    expect((await db.query("SELECT COUNT(*)::int AS n FROM google_play_first_charge WHERE chain_id=$1",[purchaseHash])).rows).toEqual([{n:1}]);

    const trialToken = "singular-trial-fixture", trial = "GPA.trial", conversion = "GPA.trial..conversion";
    const trialEnd = new Date(now.getTime()-86400_000).toISOString();
    purchases[trialToken] = {...subscription,lineItems:[{...plan,latestSuccessfulOrderId:conversion}]};
    orders[trial] = {...paidOrder(trial,trialToken,past,trialEnd),total:usd("0",0),lineItems:period(past,trialEnd,true)};
    orders[conversion] = paidOrder(conversion,trialToken,trialEnd,future);
    await syncPurchase(env,scope,trialToken,owner.owner_id);
    await syncOrder(env,scope,"live",conversion);
    expect(await claim(install)).toBeNull();
    await reconcileOrderId(env,scope,trial);
    expect(await claim(install)).toMatchObject({order_id:conversion,amount_micros:"4990000"});
    await claim(install,"android",conversion);

    const tester = "singular-licensed-tester", testOrder = "GPA.fixture.test";
    purchases[tester] = {...subscription,testPurchase:{},lineItems:[{...plan,latestSuccessfulOrderId:testOrder}]};
    orders[testOrder] = paidOrder(testOrder,tester,past,future);
    await syncPurchase(env,scope,tester,owner.owner_id);
    await syncOrder(env,scope,"test",testOrder);
    expect(await claim(install)).toBeNull();
  } finally { delete env.GOOGLE_PLAY_SINGULAR_SDK_FROM; }
});
