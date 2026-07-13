import { adminRoutes } from "./admin/routes";
import { createAppConfigRoutes } from "./app-config/routes";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { authRoutes } from "./auth/anonymous";
import { createDataSourceRoutes } from "./data-source/routes";
import type { Env } from "./env";
import { createPortfolioRoutes } from "./portfolio/routes";
import { createScanRoutes } from "./scan/routes";

export type { Env } from "./env";

const app = new Hono<{ Bindings: Env }>();
app.use(
  "/api/*",
  cors({
    origin: "https://admin.tcgcard.fun",
    allowHeaders: ["Authorization", "Content-Type"],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    maxAge: 86400,
  }),
);
const api = app.basePath("/api/v1");

api.route("/admin", adminRoutes);
api.get("/health", (c) => c.json({ status: "ok" }));
api.route("/auth", authRoutes);
api.route("/", createAppConfigRoutes());
api.route("/", createDataSourceRoutes());
api.route("/", createPortfolioRoutes());
api.route("/", createScanRoutes());

app.notFound((c) => c.json({ error: "NOT_FOUND" }, 404));

export default app;
