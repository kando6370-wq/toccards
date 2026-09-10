import { Hono } from "hono";
import { cors } from "hono/cors";

import { adminRoutes } from "./admin/routes";
import { createAppConfigRoutes } from "./app-config/routes";
import { authRoutes } from "./auth/anonymous";
import { createCardShareRoutes } from "./card-share/routes";
import { createDataSourceRoutes } from "./data-source/routes";
import {
  createAppleNotificationRoutes,
  retryAppleNotificationInbox,
} from "./entitlements/apple-notification-routes";
import { retryAppleServerApiCorrections } from "./entitlements/apple-server-api-correction";
import { createAppleRestoreRoutes } from "./entitlements/restore-routes";
import { createEntitlementRoutes } from "./entitlements/routes";
import type { Env } from "./env";
import { createFeedbackRoutes } from "./feedback/routes";
import { createLegalRoutes } from "./legal/routes";
import { createPortfolioRoutes } from "./portfolio/routes";
import { createScanRoutes } from "./scan/routes";

const DEFAULT_ALLOWED_ORIGINS = [
  "https://admin.tcgcard.fun",
  "https://dev.toccards2.pages.dev",
  "http://localhost:3000",
  "http://127.0.0.1:3000",
  "http://192.168.35.3:3000",
  "https://192.168.35.3:3000",
];

export const app = new Hono<{ Bindings: Env }>();

app.use(
  "/api/*",
  cors({
    origin: (origin, context) =>
      allowedOrigins(context.env?.ALLOWED_ORIGINS).has(origin) ? origin : "",
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
api.get("/health", (context) => context.json({ status: "ok" }));
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

app.notFound((context) => context.json({ error: "NOT_FOUND" }, 404));

export async function runScheduledTasks(env: Env): Promise<void> {
  await retryAppleNotificationInbox(env);
  await retryAppleServerApiCorrections(env);
}

function allowedOrigins(configuredOrigins: string | undefined): Set<string> {
  if (!configuredOrigins?.trim()) return new Set(DEFAULT_ALLOWED_ORIGINS);
  return new Set(
    configuredOrigins
      .split(",")
      .map((origin) => origin.trim())
      .filter(Boolean),
  );
}
