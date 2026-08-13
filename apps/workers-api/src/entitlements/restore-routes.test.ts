import { Environment, type JWSTransactionDecodedPayload } from "@apple/app-store-server-library";
import { describe, expect, it } from "vitest";
import { normalizeRestoreTransaction } from "./restore-routes";

const NOW = new Date("2026-08-12T08:00:00.000Z");
const PRODUCTS = new Set(["com.cardai.tcg.pro.yearly", "com.cardai.tcg.pro.lifetime"]);

function transaction(
  overrides: Partial<JWSTransactionDecodedPayload> = {},
): JWSTransactionDecodedPayload {
  return {
    originalTransactionId: "original-1",
    transactionId: "transaction-1",
    productId: "com.cardai.tcg.pro.yearly",
    purchaseDate: NOW.getTime() - 1_000,
    expiresDate: NOW.getTime() + 86_400_000,
    signedDate: NOW.getTime(),
    type: "Auto-Renewable Subscription",
    environment: Environment.SANDBOX,
    transactionReason: "RENEWAL",
    ...overrides,
  };
}

describe("Apple Restore transaction rules", () => {
  it("accepts an active renewal without appAccountToken because App Attest binds the current session", () => {
    expect(normalizeRestoreTransaction(transaction(), Environment.SANDBOX, PRODUCTS, NOW)).toMatchObject({
      originalTransactionId: "original-1",
      transactionReason: "RENEWAL",
      appAccountToken: null,
      chainStatus: "ACTIVE",
    });
  });

  it("accepts a configured non-consumable as Lifetime without fabricating expiry", () => {
    expect(normalizeRestoreTransaction(transaction({
      productId: "com.cardai.tcg.pro.lifetime",
      type: "Non-Consumable",
      transactionReason: "PURCHASE",
      expiresDate: undefined,
    }), Environment.SANDBOX, PRODUCTS, NOW)).toMatchObject({
      chainStatus: "LIFETIME",
      expiresAt: null,
      autoRenew: 0,
    });
  });

  it.each([
    ["expired", { expiresDate: NOW.getTime() }],
    ["revoked", { revocationDate: NOW.getTime() - 1 }],
    ["wrong environment", { environment: Environment.PRODUCTION }],
    ["unconfigured SKU", { productId: "com.cardai.tcg.pro.fake" }],
    ["unsupported reason", { transactionReason: "UPGRADE" }],
    ["consumable", { type: "Consumable" }],
  ])("rejects %s because Restore must not create an active grant", (_name, overrides) => {
    expect(normalizeRestoreTransaction(
      transaction(overrides as Partial<JWSTransactionDecodedPayload>),
      Environment.SANDBOX,
      PRODUCTS,
      NOW,
    )).toBeNull();
  });
});
