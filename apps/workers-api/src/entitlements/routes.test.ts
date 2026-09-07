import { Environment, type JWSTransactionDecodedPayload } from "@apple/app-store-server-library";
import { describe, expect, it } from "vitest";
import {
  APPLE_VERIFICATION_PROCESSING_HTTP_STATUS,
  APPLE_VERIFICATION_PROCESSING_RESPONSE,
  configuredProductIds,
  type ExistingFreshPurchaseRecord,
  isLinkableExistingFreshPurchase,
  normalizeAppleTransaction,
  shouldResumeAppleVerificationAttempt,
} from "./routes";

const NOW = new Date("2026-08-12T08:00:00.000Z");
const TOKEN = "123e4567-e89b-42d3-a456-426614174000";
const PRODUCTS = new Set([
  "com.cardai.tcg.pro.weekly",
  "com.cardai.tcg.pro.yearly",
  "com.cardai.tcg.pro.lifetime",
]);

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
    appAccountToken: TOKEN,
    environment: Environment.SANDBOX,
    transactionReason: "PURCHASE",
    storefront: "USA",
    price: 49_990,
    currency: "USD",
    ...overrides,
  };
}

describe("Apple entitlement verification rules", () => {
  it("accepts an active allowlisted Fresh Purchase because only that flow may create a session grant", () => {
    expect(normalizeAppleTransaction(transaction(), Environment.SANDBOX, PRODUCTS, NOW)).toEqual({
      originalTransactionId: "original-1",
      transactionId: "transaction-1",
      productId: "com.cardai.tcg.pro.yearly",
      productType: "subscription",
      appAccountToken: TOKEN,
      environment: "Sandbox",
      transactionReason: "PURCHASE",
      purchaseAt: "2026-08-12T07:59:59.000Z",
      expiresAt: "2026-08-13T08:00:00.000Z",
      stateEffectiveAt: "2026-08-12T08:00:00.000Z",
      chainStatus: "ACTIVE",
      autoRenew: 1,
      autoRenewSnapshot: null,
      storefront: "USA",
      amountMicros: 49_990_000,
      currency: "USD",
      businessStatus: "initial_purchase",
    });
  });

  it("keeps a free trial distinguishable while granting active Premium", () => {
    expect(normalizeAppleTransaction(
      transaction({ price: 0, offerDiscountType: "FREE_TRIAL" }),
      Environment.SANDBOX,
      PRODUCTS,
      NOW,
    )).toMatchObject({ chainStatus: "TRIAL", businessStatus: "trial" });
  });

  it("accepts an allowlisted non-consumable as Lifetime without fabricating an expiry", () => {
    const normalized = normalizeAppleTransaction(
      transaction({
        productId: "com.cardai.tcg.pro.lifetime",
        type: "Non-Consumable",
        expiresDate: undefined,
      }),
      Environment.SANDBOX,
      PRODUCTS,
      NOW,
    );

    expect(normalized).toMatchObject({
      productType: "non_consumable",
      chainStatus: "LIFETIME",
      expiresAt: null,
      autoRenew: 0,
      autoRenewSnapshot: 0,
    });
  });

  it.each([
    ["renewal", { transactionReason: "RENEWAL" }],
    ["expired subscription", { expiresDate: NOW.getTime() }],
    ["revoked transaction", { revocationDate: NOW.getTime() - 1 }],
    ["wrong environment", { environment: Environment.PRODUCTION }],
    ["unallowlisted SKU", { productId: "com.cardai.tcg.pro.fake" }],
    ["missing session proof", { appAccountToken: undefined }],
    ["non-UUID session proof", { appAccountToken: "session-1" }],
    ["consumable", { type: "Consumable" }],
  ])("rejects %s because it must not create a Fresh Purchase grant", (_name, overrides) => {
    expect(
      normalizeAppleTransaction(
        transaction(overrides as Partial<JWSTransactionDecodedPayload>),
        Environment.SANDBOX,
        PRODUCTS,
        NOW,
      ),
    ).toBeNull();
  });

  it("requires an explicit product allowlist because pending Product IDs cannot be guessed", () => {
    expect(configuredProductIds(undefined)).toBeNull();
    expect(configuredProductIds(" , ")).toBeNull();
    expect(configuredProductIds(" weekly, yearly ")).toEqual(new Set(["weekly", "yearly"]));
  });

  it("only resumes abandoned or temporarily unavailable attempts because live leases prevent duplicate writes", () => {
    expect(shouldResumeAppleVerificationAttempt({
      result_code: "PROCESSING",
      processing_expires_at: "2026-08-12T08:01:00.000Z",
    }, NOW)).toBe(false);
    expect(shouldResumeAppleVerificationAttempt({
      result_code: "PROCESSING",
      processing_expires_at: "2026-08-12T07:59:59.000Z",
    }, NOW)).toBe(true);
    expect(shouldResumeAppleVerificationAttempt({
      result_code: "VERIFICATION_UNAVAILABLE",
      processing_expires_at: null,
    }, NOW)).toBe(true);
    expect(shouldResumeAppleVerificationAttempt({
      result_code: "EVIDENCE_INVALID",
      processing_expires_at: null,
    }, NOW)).toBe(false);
  });
  it("returns retryable unavailable for a live processing lease because the client must retain its durable proof", () => {
    expect(APPLE_VERIFICATION_PROCESSING_HTTP_STATUS).toBe(503);
    expect(APPLE_VERIFICATION_PROCESSING_RESPONSE.error.code).toBe(
      "VERIFICATION_UNAVAILABLE",
    );
  });

  it("links a notification-first unlinked transaction without treating its later notification timestamp as replay", () => {
    const normalized = normalizeAppleTransaction(
      transaction(),
      Environment.SANDBOX,
      PRODUCTS,
      NOW,
    )!;
    expect(isLinkableExistingFreshPurchase(
      existingPurchase(),
      normalized,
      "performance_pro",
      "user",
      "user-1",
      NOW,
    )).toBe(true);
  });

  it.each([
    ["another owner", { original_owner_type: "user", original_owner_id: "user-2", app_account_token: TOKEN }],
    ["another challenge", { app_account_token: "123e4567-e89b-42d3-a456-426614174999" }],
    ["another chain environment", { chain_environment: "Production" }],
    ["an expired chain", { chain_expires_at: NOW.toISOString() }],
    ["a revoked chain", { chain_revoked_at: NOW.toISOString() }],
    ["a refunded transaction", { transaction_status: "refunded" }],
  ])("still rejects %s because an existing transaction is not transferable", (_name, overrides) => {
    const normalized = normalizeAppleTransaction(
      transaction(),
      Environment.SANDBOX,
      PRODUCTS,
      NOW,
    )!;
    expect(isLinkableExistingFreshPurchase(
      existingPurchase(overrides as Partial<ExistingFreshPurchaseRecord>),
      normalized,
      "performance_pro",
      "user",
      "user-1",
      NOW,
    )).toBe(false);
  });
});

function existingPurchase(
  overrides: Partial<ExistingFreshPurchaseRecord> = {},
): ExistingFreshPurchaseRecord {
  return {
    transaction_id: "transaction-1",
    transaction_product_id: "com.cardai.tcg.pro.yearly",
    transaction_status: "purchased",
    transaction_revoked_at: null,
    purchase_chain_id: "chain-1",
    chain_store: "app_store",
    chain_environment: "Sandbox",
    original_transaction_id: "original-1",
    chain_product_id: "com.cardai.tcg.pro.yearly",
    entitlement_id: "performance_pro",
    original_owner_type: "unlinked",
    original_owner_id: "",
    app_account_token: null,
    chain_status: "ACTIVE",
    chain_expires_at: "2026-08-13T08:00:00.000Z",
    chain_revoked_at: null,
    ...overrides,
  };
}
