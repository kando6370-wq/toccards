import { adminRoutes } from "./admin/routes";
import { createAppConfigRoutes } from "./app-config/routes";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { authRoutes } from "./auth/anonymous";
import { createDataSourceRoutes } from "./data-source/routes";
import type { Env } from "./env";
import { createFeedbackRoutes } from "./feedback/routes";
import { createLegalRoutes } from "./legal/routes";
import { createPortfolioRoutes } from "./portfolio/routes";
import { createScanRoutes } from "./scan/routes";

export type { Env } from "./env";

const app = new Hono<{ Bindings: Env }>();
const allowedOrigins = new Set([
  "https://admin.tcgcard.fun",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
]);
app.use(
  "/api/*",
  cors({
    origin: (origin) => (allowedOrigins.has(origin) ? origin : ""),
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
api.route("/", createFeedbackRoutes());
api.route("/", createLegalRoutes());
api.route("/", createPortfolioRoutes());
api.route("/", createScanRoutes());

app.notFound((c) => c.json({ error: "NOT_FOUND" }, 404));

export default app;
