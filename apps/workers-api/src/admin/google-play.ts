import { Hono, type Context } from "hono";
import type { AdminBindings } from "./routes";
import { createXlsx } from "./xlsx";
import { googlePlayScope } from "../google-play/access";
import { displayConfig, parsePlan, planKey, storeCatalog } from "../google-play/catalog";
import { reconcileOrderId } from "../google-play/reconcile";
import { PlayError } from "../google-play/publisher";
import { isPageType, isRecord, payloadHash } from "../subscription-config/model";
import type { PlayPlan } from "../google-play/purchases";

export const playAdmin = new Hono<AdminBindings>();
const error = (code: string) => ({success:false,error:{code,message:code}});
playAdmin.onError((e,c) => e instanceof PlayError ? c.json(error(e.code),e.status) : c.json(error("GOOGLE_PLAY_ADMIN_UNAVAILABLE"),503));
function scopeOf(c: Context<AdminBindings>) {
  const scope = googlePlayScope(c.env);
  if (!scope) throw new PlayError("GOOGLE_PLAY_NOT_CONFIGURED");
  return scope;
}
const ok = <T>(data:T) => ({success:true,data});
function page(value?: string) { return Math.max(1,Math.min(100000,Number.parseInt(value ?? "1",10) || 1)); }
playAdmin.get("/orders/options", async c => {
  const scope = scopeOf(c);
  const rows = await c.env.DB.prepare("SELECT DISTINCT country,base_plan_id FROM google_play_order WHERE scope=? ORDER BY country,base_plan_id").bind(scope).all();
  return c.json(ok({scope,rows:rows.results}));
});
async function orders(c: Context<AdminBindings>, exporting: boolean) {
  const scope = scopeOf(c), db=c.env.DB, filters = c.req.query(), kind=filters.store_kind ?? "live";
  if (!["test","live"].includes(kind)) throw new PlayError("INVALID_STORE_KIND",422);
  const where=["o.scope=?","o.store_kind=?"], args: unknown[]=[scope,kind];
  for (const [field,column] of Object.entries({owner_id:"o.owner_id",order_id:"o.order_id",country:"o.country",base_plan_id:"o.base_plan_id",kind:"e.kind",state:"p.state"})) {
    if (filters[field]) {where.push(`${column}=?`); args.push(filters[field]);}
  }
  for (const [field,op] of [["from",">="],["to","<"]] as const) if (filters[field]) {
    const time=Date.parse(filters[field]); if (!Number.isFinite(time)) throw new PlayError("INVALID_UTC_DATE",422);
    where.push(`e.event_at ${op} ?`); args.push(new Date(time).toISOString());
  }
  const source=`FROM google_play_order o LEFT JOIN google_play_order_event e USING(scope,store_kind,order_id)
    JOIN google_play_purchase p ON p.scope=o.scope AND p.token_hash=o.token_hash WHERE ${where.join(" AND ")}`;
  const rows=await db.prepare(`SELECT o.order_id,o.owner_id,o.country,o.product_id,o.base_plan_id,o.store_kind,o.currency,p.state,
    o.tax_micros,o.fx_snapshot,e.kind,e.event_at,e.amount_micros,e.usd_micros ${source} ORDER BY e.event_at DESC NULLS LAST,o.order_id,e.event_key LIMIT ? OFFSET ?`)
    .bind(...args,exporting ? 10001 : 20,exporting ? 0 : (page(filters.page)-1)*20).all<Record<string,unknown>>();
  if (exporting) {
    if (rows.results.length > 10000) throw new PlayError("NARROW_EXPORT_RANGE",422);
    const cols=["order_id","owner_id","country","product_id","base_plan_id","store_kind","state","currency","kind","event_at","amount_micros","usd_micros"];
    return new Response(createXlsx(cols,rows.results.map(r=>cols.map(k=>r[k]))),{headers:{"Content-Type":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet","Content-Disposition":"attachment; filename=google-play-orders.xlsx"}});
  }
  const summary=await db.prepare(`SELECT COUNT(*)::int AS total,COUNT(DISTINCT o.order_id) FILTER(WHERE e.kind IS NOT NULL)::int AS order_count,
    SUM(e.usd_micros) FILTER(WHERE e.kind='charge') AS gross_usd_micros,SUM(e.usd_micros) FILTER(WHERE e.kind='refund') AS refund_usd_micros,
    SUM(CASE WHEN e.kind='refund' THEN -e.usd_micros ELSE e.usd_micros END) AS net_usd_micros,
    COUNT(*) FILTER(WHERE e.usd_micros IS NULL AND (e.kind='charge' OR e.kind IS NULL))::int AS missing_charges,
    COUNT(*) FILTER(WHERE e.usd_micros IS NULL AND e.kind='refund')::int AS missing_refunds ${source}`).bind(...args).first();
  return c.json(ok({scope,summary,rows:rows.results}));
}
playAdmin.get("/orders",c=>orders(c,false));
playAdmin.get("/orders/export",c=>orders(c,true));
playAdmin.get("/notifications", async c => {
  const scope=scopeOf(c), clauses=["i.scope=?"], args:unknown[]=[scope];
  for(const [key,col] of Object.entries({message_id:"i.message_id",kind:"i.kind",state:"i.state",order_id:"i.order_id",chain:"left(p.chain_id,12)"})) {
    const value=c.req.query(key); if(value){clauses.push(`${col}=?`);args.push(value);}
  }
  const rows=await c.env.DB.prepare(`SELECT i.message_id,i.kind,i.state,i.received_at,i.event_at,i.attempts,i.next_check_at,i.last_error,i.order_id,
    left(p.chain_id,12) AS chain,p.store_kind,p.checked_at,p.acknowledgement,COUNT(*) OVER()::int AS total
    FROM google_play_inbox i LEFT JOIN google_play_purchase p ON p.scope=i.scope AND p.token_hash=i.token_hash WHERE ${clauses.join(' AND ')}
    ORDER BY i.received_at DESC,i.message_id LIMIT 20 OFFSET ?`).bind(...args,(page(c.req.query("page"))-1)*20).all();
  return c.json(ok({scope,rows:rows.results}));
});
playAdmin.get("/products", async c => {
  const scope=scopeOf(c), approved=await c.env.DB.prepare("SELECT product_id,base_plan_id,offer_id,revenue_event,revision FROM google_play_product WHERE scope=? ORDER BY product_id,base_plan_id,offer_id").bind(scope).all();
  const catalog=c.req.query("refresh") === "1" ? await storeCatalog(c.env) : null;
  return c.json(ok({scope,approved:approved.results,catalog}));
});
playAdmin.get("/configs", async c => {
  const scope=scopeOf(c), rows=await c.env.DB.prepare("SELECT placement,draft,published,revision FROM google_play_display WHERE scope=? ORDER BY placement").bind(scope).all();
  return c.json(ok({scope,rows:rows.results}));
});

playAdmin.post("/orders/reconcile", async c => {
  if (c.get("admin").role !== "super_admin") return c.json(error("FORBIDDEN"),403);
  const scope=scopeOf(c), body:unknown=await c.req.json().catch(()=>null);
  if(!isRecord(body) || typeof body.order_id!=="string" || !/^GPA\.[0-9-]{12,30}(?:\.\.\d+)?$/.test(body.order_id) ||
    typeof body.reason!=="string" || !body.reason.trim() || body.reason.length>300 || typeof body.request_id!=="string" || !/^[a-z0-9-]{16,80}$/i.test(body.request_id)) return c.json(error("VALIDATION_ERROR"),422);
  const admin=c.get("admin").admin_id, hash=await payloadHash(body);
  const prior=await c.env.DB.prepare("SELECT admin_id,payload_hash,after_value FROM google_play_audit WHERE scope=? AND request_id=?").bind(scope,body.request_id).first<{admin_id:string;payload_hash:string;after_value:unknown}>();
  if(prior) return prior.admin_id===admin && prior.payload_hash===hash ? c.json(ok(prior.after_value)) : c.json(error("IDEMPOTENCY_CONFLICT"),409);
  const result=await reconcileOrderId(c.env,scope,body.order_id);
  const audit=await c.env.DB.prepare(`INSERT INTO google_play_audit(scope,request_id,admin_id,action,payload_hash,after_value,reason,created_at)
    VALUES(?,?,?,'reconcile_order',?,?::jsonb,?,?) ON CONFLICT(scope,request_id) DO UPDATE SET request_id=excluded.request_id
    WHERE google_play_audit.payload_hash=excluded.payload_hash AND google_play_audit.admin_id=excluded.admin_id RETURNING after_value`)
    .bind(scope,body.request_id,admin,hash,JSON.stringify(result),body.reason.trim(),new Date().toISOString()).first();
  return audit ? c.json(ok(result)) : c.json(error("IDEMPOTENCY_CONFLICT"),409);
});

playAdmin.post("/:resource", async c => {
  const action=c.req.param("resource"), admin=c.get("admin"), scope=scopeOf(c), db=c.env.DB;
  if (!["configs","products","retry"].includes(action)) return c.json(error("NOT_FOUND"),404);
  if (action !== "configs" && admin.role !== "super_admin") return c.json(error("FORBIDDEN"),403);
  const body:unknown=await c.req.json().catch(()=>null);
  if (!isRecord(body) || typeof body.request_id!=="string" || !/^[a-z0-9-]{16,80}$/i.test(body.request_id) || !Number.isSafeInteger(body.expected_revision) ||
    typeof body.reason!=="string" || !body.reason.trim() || body.reason.length>300) return c.json(error("VALIDATION_ERROR"),422);
  const hash=await payloadHash(body), revision=Number(body.expected_revision), requestId=body.request_id, stamp=new Date().toISOString();
  const replay=async()=>db.prepare("SELECT admin_id,action,payload_hash,after_value FROM google_play_audit WHERE scope=? AND request_id=?").bind(scope,requestId).first<{admin_id:string;action:string;payload_hash:string;after_value:unknown}>();
  const existing=await replay();
  if(existing) return existing.admin_id===admin.admin_id && existing.action===action && existing.payload_hash===hash ? c.json(ok(existing.after_value)) : c.json(error("IDEMPOTENCY_CONFLICT"),409);
  let beforeSql:string, beforeArgs:unknown[], mutateSql:string, mutateArgs:unknown[];
  if(action==="products") {
    const plan=parsePlan(body), event=body.revenue_event;
    if(!plan || typeof event!=="string" || !/^[A-Za-z][A-Za-z0-9_]{0,31}$/.test(event)) return c.json(error("INVALID_PRODUCT"),422);
    if(!(await storeCatalog(c.env)).some(item=>planKey(item)===planKey(plan))) return c.json(error("PRODUCT_NOT_SELLABLE"),422);
    beforeArgs=[scope,plan.product_id,plan.base_plan_id,plan.offer_id];beforeSql="SELECT * FROM google_play_product WHERE scope=? AND product_id=? AND base_plan_id=? AND offer_id=?";
    mutateSql=`INSERT INTO google_play_product(scope,product_id,base_plan_id,offer_id,revenue_event,revision) SELECT ?,?,?,?,?,? WHERE (SELECT COALESCE(MAX(revision),0) FROM prior)=?
      ON CONFLICT(scope,product_id,base_plan_id,offer_id) DO UPDATE SET revenue_event=excluded.revenue_event,revision=excluded.revision WHERE google_play_product.revision=? RETURNING *`;
    mutateArgs=[...beforeArgs,event,revision+1,revision,revision];
  } else if(action==="configs") {
    if(!isPageType(body.placement) || !["save","enable","disable"].includes(String(body.operation))) return c.json(error("INVALID_CONFIG"),422);
    beforeSql="SELECT * FROM google_play_display WHERE scope=? AND placement=?";beforeArgs=[scope,body.placement];
    if(body.operation==="save") {
      const config=displayConfig(body.draft);
      if(!config) return c.json(error("INVALID_CONFIG"),422);
      const approved=await db.prepare("SELECT product_id,base_plan_id,offer_id FROM google_play_product WHERE scope=?").bind(scope).all<PlayPlan>();
      if(config.plans.some(p=>!approved.results.some(a=>planKey(a)===planKey(p)))) return c.json(error("PRODUCT_NOT_APPROVED"),422);
      mutateSql=`INSERT INTO google_play_display(scope,placement,draft,revision) SELECT ?,?,?::jsonb,? WHERE (SELECT COALESCE(MAX(revision),0) FROM prior)=?
        ON CONFLICT(scope,placement) DO UPDATE SET draft=excluded.draft,revision=excluded.revision WHERE google_play_display.revision=? RETURNING *`;
      mutateArgs=[...beforeArgs,JSON.stringify(config),revision+1,revision,revision];
    } else {
      if(body.operation==="enable") {
        const saved=await db.prepare(beforeSql).bind(...beforeArgs).first<{draft:unknown;revision:number}>(), config=displayConfig(saved?.draft);
        if(saved?.revision!==revision || !config) return c.json(error("REVISION_CONFLICT"),409);
        const active=new Set((await storeCatalog(c.env)).map(planKey));
        if(config.plans.some(p=>!active.has(planKey(p)))) return c.json(error("PRODUCT_NOT_SELLABLE"),422);
      }
      mutateSql=`UPDATE google_play_display SET published=${body.operation === "enable" ? "draft" : "NULL"},revision=revision+1 WHERE scope=? AND placement=? AND revision=? RETURNING *`;
      mutateArgs=[...beforeArgs,revision];
    }
  } else {
    if(typeof body.message_id!=="string") return c.json(error("INVALID_MESSAGE"),422);
    beforeArgs=[scope,c.env.GOOGLE_PLAY_TOPIC ?? "",body.message_id];
    beforeSql="SELECT message_id,state,attempts FROM google_play_inbox WHERE scope=? AND topic=? AND message_id=?";
    mutateSql=`UPDATE google_play_inbox SET state='pending',next_check_at=? WHERE scope=? AND topic=? AND message_id=? AND state='failed' AND attempts=? RETURNING message_id,state,attempts`;
    mutateArgs=[stamp,...beforeArgs,revision];
  }
  // Row-lock the prior version. Only a successful compare-and-swap writes the audit entry, in the same statement.
  try {
    const saved=await db.prepare(`WITH prior AS MATERIALIZED (${beforeSql} FOR UPDATE), changed AS (${mutateSql})
      INSERT INTO google_play_audit(scope,request_id,admin_id,action,payload_hash,before_value,after_value,reason,created_at)
      SELECT ?,?,?,?,?,(SELECT to_jsonb(prior) FROM prior),to_jsonb(changed),?,? FROM changed RETURNING after_value`)
      .bind(...beforeArgs,...mutateArgs,scope,requestId,admin.admin_id,action,hash,body.reason.trim(),stamp).first<{after_value:unknown}>();
    if(saved) return c.json(ok(saved.after_value));
  } catch(e) {if((e as {code?:string}).code!=="23505") throw e;}
  const raced=await replay();
  return raced && raced.admin_id===admin.admin_id && raced.action===action && raced.payload_hash===hash ? c.json(ok(raced.after_value)) : c.json(error("REVISION_CONFLICT"),409);
});
