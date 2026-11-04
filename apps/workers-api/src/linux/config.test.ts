import { afterEach, describe, expect, it, vi } from "vitest";

import * as postgresDatabase from "../db/postgres-database";
import { loadLinuxRuntime } from "./config";

const source = {
  APP_ENVIRONMENT: "development",
  DATABASE_URL: "postgres://dev:password@127.0.0.1:15432/toccards_test",
  OBJECT_STORAGE_PATH: "./test-scan-images",
  JWT_SECRET: "linux-test-secret",
  ALLOWED_ORIGINS: "http://localhost:8080",
  VECTOR_RECOGNITION_BASE_URL: "https://recognize-vec.tcgcard.fun",
  PHASH_RECOGNITION_BASE_URL: "https://recognize.tcgcard.fun",
};

describe("Linux runtime configuration", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("binds the local business database and keeps vector and pHash recognition separate", () => {
    const database = {} as postgresDatabase.PostgresDatabase;
    const createDatabase = vi.spyOn(postgresDatabase, "createPostgresDatabase")
      .mockReturnValue(database);

    const runtime = loadLinuxRuntime(source);

    expect(createDatabase).toHaveBeenCalledExactlyOnceWith(source.DATABASE_URL);
    expect(runtime.database).toBe(database);
    expect(runtime.env.DB).toBe(database);
    expect(runtime.env.HYPERDRIVE).toBeUndefined();
    expect(runtime.env.APP_ENVIRONMENT).toBe("development");
    expect(runtime.env.VECTOR_RECOGNITION?.fetch).toBeTypeOf("function");
    expect(runtime.env.PHASH_RECOGNITION_BASE_URL).toBe(source.PHASH_RECOGNITION_BASE_URL);
    expect(runtime.env.EXTENSION_RECOGNITION_KEY).toBeUndefined();
    expect(runtime.env.EXTENSION_RECOGNITION_RATE_LIMITER?.limit).toBeTypeOf("function");
    expect(runtime.extensionTrustProxy).toBe(false);
  });

  it("rejects an old OCR-only configuration instead of starting dev with no usable recognition service", () => {
    vi.spyOn(postgresDatabase, "createPostgresDatabase")
      .mockReturnValue({} as postgresDatabase.PostgresDatabase);

    expect(() => loadLinuxRuntime({
      ...source,
      VECTOR_RECOGNITION_BASE_URL: undefined,
      OCR_SERVICE_BASE_URL: "https://retired-ocr.invalid",
    })).toThrow("VECTOR_RECOGNITION_BASE_URL is required");
    expect(() => loadLinuxRuntime({
      ...source,
      PHASH_RECOGNITION_BASE_URL: undefined,
    })).toThrow("PHASH_RECOGNITION_BASE_URL is required");
  });

  it("loads an independent plugin key and explicit proxy trust without requiring user login", async () => {
    vi.spyOn(postgresDatabase, "createPostgresDatabase")
      .mockReturnValue({} as postgresDatabase.PostgresDatabase);
    const runtime = loadLinuxRuntime({
      ...source,
      EXTENSION_RECOGNITION_KEY: "plugin-test-only",
      EXTENSION_RECOGNITION_REQUESTS_PER_MINUTE: "1",
      EXTENSION_TRUST_PROXY: "true",
    });
    expect(runtime.env.EXTENSION_RECOGNITION_KEY).toBe("plugin-test-only");
    expect(runtime.extensionTrustProxy).toBe(true);
    const limiter = runtime.env.EXTENSION_RECOGNITION_RATE_LIMITER!;
    expect(await limiter.limit({ key: "192.0.2.1" })).toEqual({ success: true });
    expect(await limiter.limit({ key: "192.0.2.1" })).toEqual({ success: false });
  });

  it.each(["0", "-1", "1.5", "not-a-number"])("rejects invalid burst limits %s rather than silently removing protection", (value) => {
    expect(() => loadLinuxRuntime({ ...source, EXTENSION_RECOGNITION_REQUESTS_PER_MINUTE: value }))
      .toThrow("EXTENSION_RECOGNITION_REQUESTS_PER_MINUTE must be a positive integer");
  });

  it("rejects ambiguous proxy trust configuration instead of accepting forged forwarding headers", () => {
    expect(() => loadLinuxRuntime({ ...source, EXTENSION_TRUST_PROXY: "yes" }))
      .toThrow("EXTENSION_TRUST_PROXY must be true or false");
  });

  it("keeps the catalog optional and uses dedicated catalog credentials without changing purchase settings", () => {
    vi.spyOn(postgresDatabase, "createPostgresDatabase")
      .mockReturnValue({} as postgresDatabase.PostgresDatabase);
    const optionalRuntime = loadLinuxRuntime(source);
    expect(optionalRuntime.env.APP_STORE_CONNECT_PRIVATE_KEY).toBeUndefined();
    const runtime = loadLinuxRuntime({ ...source,
      APPLE_IAP_PRODUCT_IDS: "legacy.product", APPLE_IAP_PRIVATE_KEY: "existing-purchase-key",
      APP_STORE_CONNECT_APP_ID: "123", APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID: "456",
      APP_STORE_CONNECT_ISSUER_ID: "catalog-issuer", APP_STORE_CONNECT_KEY_ID: "catalog-key",
      APP_STORE_CONNECT_PRIVATE_KEY: "catalog-private-key",
      SUBSCRIPTION_LIFETIME_PRODUCT_IDS: "legacy.lifetime", SUBSCRIPTION_DISPLAY_PRODUCT_IDS: "legacy.product",
    });
    expect(runtime.env.APPLE_IAP_PRIVATE_KEY).toBe("existing-purchase-key");
    expect(runtime.env.APPLE_IAP_PRODUCT_IDS).toBe("legacy.product");
    expect(runtime.env.APP_STORE_CONNECT_PRIVATE_KEY).toBe("catalog-private-key");
    expect(runtime.env.APP_STORE_CONNECT_APP_ID).toBe("123");
    expect(runtime.env.APP_STORE_CONNECT_SUBSCRIPTION_GROUP_ID).toBe("456");
    expect(runtime.env.SUBSCRIPTION_LIFETIME_PRODUCT_IDS).toBe("legacy.lifetime");
    expect(runtime.env.SUBSCRIPTION_DISPLAY_PRODUCT_IDS).toBe("legacy.product");
  });

  it("rejects production configuration because this entry point only hosts dev", () => {
    expect(() => loadLinuxRuntime({ ...source, APP_ENVIRONMENT: "production" }))
      .toThrow("APP_ENVIRONMENT=development");
  });
});
