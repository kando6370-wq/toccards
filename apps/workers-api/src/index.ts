import { Hono } from "hono";

export interface Env {
  DB: D1Database;
  CACHE_KV: KVNamespace;
}

const app = new Hono<{ Bindings: Env }>();

// /api/v1 路由组（M0 仅挂健康检查；业务路由在 M1–M2 逐步注册）
const api = app.basePath("/api/v1");

api.get("/health", (c) => c.json({ status: "ok" }));

// 未注册路由统一返回 404（而非崩溃）—— 对齐 dev-plan §2 M0 验收
app.notFound((c) => c.json({ error: "NOT_FOUND" }, 404));

export default app;
