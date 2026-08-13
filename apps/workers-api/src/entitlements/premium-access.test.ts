import { describe, expect, it } from "vitest";
import { hasActivePremiumGrant } from "./premium-access";

type Grant = {
  sessionId: string;
  entitlementId: string;
  status: "active" | "revoked" | "expired";
  expiresAt: string | null;
  revokedAt: string | null;
  environment: "Sandbox" | "Production";
  purchaseChainStatus: string;
  purchaseChainExpiresAt: string | null;
  purchaseChainRevokedAt: string | null;
};

class FakeD1 {
  grants: Grant[] = [];

  prepare(): D1PreparedStatement {
    return new FakeStatement(this) as unknown as D1PreparedStatement;
  }
}

class FakeStatement {
  private values: unknown[] = [];

  constructor(private readonly db: FakeD1) {}

  bind(...values: unknown[]): FakeStatement {
    this.values = values;
    return this;
  }

  async first<T>(): Promise<T | null> {
    const [sessionId, entitlementId, now, environment] = this.values as string[];
    const grant = this.db.grants.find(
      (item) =>
        item.sessionId === sessionId &&
        item.entitlementId === entitlementId &&
        item.status === "active" &&
        item.revokedAt === null &&
        (item.expiresAt === null || item.expiresAt > now) &&
        item.environment === environment &&
        ["ACTIVE", "TRIAL", "GRACE_PERIOD", "LIFETIME"].includes(
          item.purchaseChainStatus,
        ) &&
        item.purchaseChainRevokedAt === null &&
        (item.purchaseChainExpiresAt === null || item.purchaseChainExpiresAt > now),
    );

    return (grant ? { id: "grant", purchase_chain_id: "chain", expires_at: grant.expiresAt } : null) as T | null;
  }
}

const NOW = new Date("2026-08-12T00:00:00.000Z");

describe("session Premium grant", () => {
  it("does not share Premium across sessions of the same UID", async () => {
    const db = databaseWithActiveGrant("session-a", "Sandbox");

    await expect(access(db, "session-a", "development")).resolves.toBe(true);
    await expect(access(db, "session-b", "development")).resolves.toBe(false);
  });

  it("isolates Sandbox from Production because test purchases must never grant production access", async () => {
    const db = databaseWithActiveGrant("session-a", "Sandbox");

    await expect(access(db, "session-a", "production")).resolves.toBe(false);
  });

  it.each(["BILLING_RETRY", "EXPIRED", "REFUNDED", "REVOKED"])(
    "denies %s purchase chains because only Apple-valid lifecycle states are Premium",
    async (purchaseChainStatus) => {
      const db = databaseWithActiveGrant("session-a", "Sandbox");
      db.grants[0]!.purchaseChainStatus = purchaseChainStatus;

      await expect(access(db, "session-a", "development")).resolves.toBe(false);
    },
  );

  it("denies expired grants because a historical Apple proof cannot grant indefinitely", async () => {
    const db = databaseWithActiveGrant("session-a", "Sandbox");
    db.grants[0]!.expiresAt = "2026-08-11T23:59:59.000Z";

    await expect(access(db, "session-a", "development")).resolves.toBe(false);
  });
});

function databaseWithActiveGrant(
  sessionId: string,
  environment: "Sandbox" | "Production",
): FakeD1 {
  const db = new FakeD1();
  db.grants.push({
    sessionId,
    entitlementId: "performance_pro",
    status: "active",
    expiresAt: "2026-08-13T00:00:00.000Z",
    revokedAt: null,
    environment,
    purchaseChainStatus: "ACTIVE",
    purchaseChainExpiresAt: "2026-08-13T00:00:00.000Z",
    purchaseChainRevokedAt: null,
  });
  return db;
}

function access(
  db: FakeD1,
  sessionId: string,
  appEnvironment: "production" | "development",
): Promise<boolean> {
  return hasActivePremiumGrant(
    {
      DB: db as unknown as D1Database,
      APP_ENVIRONMENT: appEnvironment,
    },
    sessionId,
    NOW,
  );
}
