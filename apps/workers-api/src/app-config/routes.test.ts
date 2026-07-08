import { describe, expect, it } from "vitest";
import app, { type Env } from "../index";

type AppConfigRow = {
  key: string;
  value: string;
  updated_by: string | null;
  updated_at: string;
};

class FakeD1 {
  constructor(readonly appConfigs: AppConfigRow[] = []) {}

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
  }
}

class FakeD1Statement {
  constructor(
    private readonly db: FakeD1,
    private readonly sql: string,
  ) {}

  bind(): FakeD1Statement {
    return this;
  }

  async all<T = unknown>(): Promise<D1Result<T>> {
    if (this.sql.includes("FROM app_config")) {
      return okResult<T>(this.db.appConfigs as T[]);
    }

    throw new Error(`Unsupported SQL: ${this.sql}`);
  }
}

describe("public app config routes", () => {
  it("exposes upgrade config without Admin auth because app startup cannot use back-office tokens", async () => {
    const env = createTestEnv([
      appConfigRow(
        "upgrade_prompt",
        JSON.stringify({
          latest_version: "1.0.2",
          force_update: true,
          title: "Update required",
          message: "Please install the latest Kando build.",
          store_url: "https://apps.apple.com/app/kando",
        }),
      ),
      appConfigRow("app_store_url", "https://apps.apple.com/app/kando"),
      appConfigRow("announcement", "{\"title\":\"Ops only\"}"),
    ]);

    const response = await app.request("/api/v1/app-config", {}, env);

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        upgrade_prompt: {
          latest_version: "1.0.2",
          force_update: true,
          title: "Update required",
          message: "Please install the latest Kando build.",
          store_url: "https://apps.apple.com/app/kando",
        },
        app_store_url: "https://apps.apple.com/app/kando",
      },
    });
  });

  it("drops malformed upgrade JSON because a bad operations value must not break app startup", async () => {
    const env = createTestEnv([
      appConfigRow("upgrade_prompt", "{bad json"),
      appConfigRow("app_store_url", "https://apps.apple.com/app/kando"),
    ]);

    const response = await app.request("/api/v1/app-config", {}, env);

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        upgrade_prompt: null,
        app_store_url: "https://apps.apple.com/app/kando",
      },
    });
  });
});

function appConfigRow(key: string, value: string): AppConfigRow {
  return {
    key,
    value,
    updated_by: "operator-1",
    updated_at: "2026-07-08T00:00:00.000Z",
  };
}

function createTestEnv(appConfigs: AppConfigRow[]): Env {
  return {
    DB: new FakeD1(appConfigs) as unknown as D1Database,
    CACHE_KV: {} as KVNamespace,
    JWT_SECRET: "test-secret",
  };
}

function okResult<T>(results: T[]): D1Result<T> {
  return {
    success: true,
    results,
    meta: {
      duration: 0,
      size_after: 0,
      rows_read: 0,
      rows_written: 0,
      last_row_id: 0,
      changed_db: false,
      changes: 0,
    },
  };
}
