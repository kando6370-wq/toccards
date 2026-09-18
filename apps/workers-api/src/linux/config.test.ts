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
};

describe("Linux runtime configuration", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("binds the local business database and vector service without requiring retired OCR configuration", () => {
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
  });

  it("rejects an old OCR-only configuration instead of starting dev with no usable recognition service", () => {
    vi.spyOn(postgresDatabase, "createPostgresDatabase")
      .mockReturnValue({} as postgresDatabase.PostgresDatabase);

    expect(() => loadLinuxRuntime({
      ...source,
      VECTOR_RECOGNITION_BASE_URL: undefined,
      OCR_SERVICE_BASE_URL: "https://retired-ocr.invalid",
    })).toThrow("VECTOR_RECOGNITION_BASE_URL is required");
  });

  it("rejects production configuration because this entry point only hosts dev", () => {
    expect(() => loadLinuxRuntime({ ...source, APP_ENVIRONMENT: "production" }))
      .toThrow("APP_ENVIRONMENT=development");
  });
});
