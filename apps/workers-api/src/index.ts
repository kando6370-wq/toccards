import { adminRoutes } from "./admin/routes";
import { createAppConfigRoutes } from "./app-config/routes";
import { Hono } from "hono";
import { cors } from "hono/cors";
import { authRoutes } from "./auth/anonymous";
import { createDataSourceRoutes } from "./data-source/routes";
import type { Env, RuntimeEnv } from "./env";
import { createFeedbackRoutes } from "./feedback/routes";
import { createLegalRoutes } from "./legal/routes";
import { createPortfolioRoutes } from "./portfolio/routes";
import { createScanRoutes } from "./scan/routes";
import { createCardShareRoutes } from "./card-share/routes";
import { createEntitlementRoutes } from "./entitlements/routes";
import { createAppleRestoreRoutes } from "./entitlements/restore-routes";
import { createAppleNotificationRoutes, retryAppleNotificationInbox } from "./entitlements/apple-notification-routes";
import { retryAppleServerApiCorrections } from "./entitlements/apple-server-api-correction";
import { createPostgresDatabase, runWithDatabaseLifecycle } from "./db/postgres-database";

export type { Env } from "./env";

const app = new Hono<{ Bindings: Env }>();
const allowedOrigins = new Set([
  "https://admin.tcgcard.fun",
  "https://dev.toccards2.pages.dev",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
  "http://192.168.35.3:3000",
  "https://192.168.35.3:3000",
]);
app.use(
  "/api/*",
  cors({
    origin: (origin) => (allowedOrigins.has(origin) ? origin : ""),
    allowHeaders: [
      "Authorization",
      "Content-Type",
      "Idempotency-Key",
      "X-Local-Premium-State",
    ],
    allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    maxAge: 86400,
  }),
);
app.route("/", createCardShareRoutes());
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
api.route("/", createEntitlementRoutes());
api.route("/", createAppleRestoreRoutes());
api.route("/", createAppleNotificationRoutes());

app.notFound((c) => c.json({ error: "NOT_FOUND" }, 404));

const honoFetch = app.fetch.bind(app);

async function fetch(
  request: Request,
  env: RuntimeEnv,
  ctx?: ExecutionContext,
): Promise<Response> {
  if (env?.HYPERDRIVE) {
    if (!ctx) throw new Error("ExecutionContext is required for PostgreSQL requests");
    const database = createPostgresDatabase(env.HYPERDRIVE.connectionString);
    const requestEnv = { ...env, DB: database } as Env;
    return runWithDatabaseLifecycle(database, ctx, (trackedContext) =>
      Promise.resolve(honoFetch(request, requestEnv, trackedContext)));
  }
  if (env?.DB) return Promise.resolve(honoFetch(request, env as Env, ctx));
  throw new Error("HYPERDRIVE binding is required");
}

function scheduled(
  _controller: ScheduledController,
  env: RuntimeEnv,
  ctx: ExecutionContext,
): void {
  if (env.HYPERDRIVE) {
    const database = createPostgresDatabase(env.HYPERDRIVE.connectionString);
    const scheduledEnv = { ...env, DB: database } as Env;
    ctx.waitUntil((async () => {
      try {
        await runScheduledTasks(scheduledEnv);
      } finally {
        await database.close();
      }
    })());
    return;
  }
  if (env.DB) {
    ctx.waitUntil(runScheduledTasks(env as Env));
    return;
  }
  throw new Error("HYPERDRIVE binding is required");
}

async function runScheduledTasks(env: Env): Promise<void> {
  await retryAppleNotificationInbox(env);
  await retryAppleServerApiCorrections(env);
}

export default {
  fetch,
  request: app.request.bind(app),
  scheduled,
};
