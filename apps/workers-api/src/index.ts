import { Hono } from "hono";
import { authRoutes } from "./auth/anonymous";
import { createDataSourceRoutes } from "./data-source/routes";
import type { Env } from "./env";
import { createPortfolioRoutes } from "./portfolio/routes";

export type { Env } from "./env";

const app = new Hono<{ Bindings: Env }>();
const api = app.basePath("/api/v1");

api.get("/health", (c) => c.json({ status: "ok" }));
api.route("/auth", authRoutes);
api.route("/", createDataSourceRoutes());
api.route("/", createPortfolioRoutes());

app.notFound((c) => c.json({ error: "NOT_FOUND" }, 404));

export default app;
