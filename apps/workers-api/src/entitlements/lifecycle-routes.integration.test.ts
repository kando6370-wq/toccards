import { signAccessToken } from "@kando/auth-core";
import { Miniflare } from "miniflare";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { Env } from "../env";
import { createEntitlementRoutes } from "./routes";

describe("current-session Apple lifecycle route", () => {
  let miniflare: Miniflare;
  let db: D1Database;
  let env: Env;

  beforeEach(async () => {
    miniflare = new Miniflare({
      modules: true,
      script: "export default { fetch() { return new Response('ok') } }",
      compatibilityDate: "2024-11-01",
      d1Databases: ["DB"],
    });
    db = await miniflare.getD1Database("DB");
    await db.exec(SCHEMA);
    await db.batch([
      db.prepare("INSERT INTO anonymous_account VALUES ('owner-1', NULL)"),
      db.prepare("INSERT INTO session VALUES ('session-a', 'anonymous', 'owner-1', '2099-01-01T00:00:00.000Z', NULL)"),
      db.prepare("INSERT INTO session VALUES ('session-b', 'anonymous', 'owner-1', '2099-01-01T00:00:00.000Z', NULL)"),
      chain("chain-a", "Sandbox", "original-a", "REVOKED"),
      chain("chain-b", "Sandbox", "original-b", "ACTIVE"),
      chain("chain-prod", "Production", "original-prod", "ACTIVE"),
      grant("grant-a", "session-a", "chain-a", "revoked"),
      grant("grant-b", "session-b", "chain-b", "active"),
      grant("grant-prod", "session-a", "chain-prod", "active"),
    ]);
    env = {
      DB: db,
      JWT_SECRET: "lifecycle-test-secret",
      APP_ENVIRONMENT: "development",
    } as Env;
  });

  afterEach(async () => miniflare.dispose());

  it("returns only chains proved by the live session in the current environment", async () => {
    const app = createEntitlementRoutes();
    const token = await signAccessToken(
      { owner_type: "anonymous", owner_id: "owner-1", session_id: "session-a" },
      env.JWT_SECRET,
    );

    const response = await app.request("/entitlements/apple/lifecycle", {
      headers: { Authorization: `Bearer ${token}` },
    }, env);

    expect(response.status).toBe(200);
    const envelope = await response.json<{
      data: { purchase_chains: unknown[] };
    }>();
    expect(envelope.data.purchase_chains).toEqual([
      {
        original_transaction_id: "original-a",
        product_id: "yearly",
        lifecycle_status: "REVOKED",
        state_effective_at: "2026-08-13T00:00:00.000Z",
      },
    ]);
  });

  function chain(id: string, environment: string, originalId: string, status: string) {
    return db.prepare(`INSERT INTO billing_purchase_chain VALUES (?, 'app_store', ?, ?, 'yearly', 'performance_pro', ?, ?)`).bind(
      id, environment, originalId, status, "2026-08-13T00:00:00.000Z",
    );
  }

  function grant(id: string, sessionId: string, chainId: string, status: string) {
    return db.prepare("INSERT INTO billing_session_entitlement_grant VALUES (?, ?, ?, 'performance_pro', ?)").bind(
      id, sessionId, chainId, status,
    );
  }
});

const SCHEMA = `
CREATE TABLE anonymous_account (id TEXT PRIMARY KEY, upgraded_user_id TEXT);
CREATE TABLE session (id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL, expires_at TEXT NOT NULL, revoked_at TEXT);
CREATE TABLE billing_purchase_chain (id TEXT PRIMARY KEY, store TEXT NOT NULL, environment TEXT NOT NULL, original_transaction_id TEXT NOT NULL, product_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, status TEXT NOT NULL, state_effective_at TEXT);
CREATE TABLE billing_session_entitlement_grant (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, purchase_chain_id TEXT NOT NULL, entitlement_id TEXT NOT NULL, status TEXT NOT NULL);
`;
