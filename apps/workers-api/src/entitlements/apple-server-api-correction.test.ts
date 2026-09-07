import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { retryAppleServerApiCorrections } from "./apple-server-api-correction";

describe("Apple Server API correction selection", () => {
  it("selects production and TestFlight rows only for the production Bundle", async () => {
    const calls: Array<{ sql: string; values: unknown[] }> = [];
    const database = {
      prepare(sql: string) {
        const call = { sql: sql.replace(/\s+/g, " ").trim(), values: [] as unknown[] };
        calls.push(call);
        const statement = {
          bind(...values: unknown[]) {
            call.values = values;
            return statement;
          },
          async all() {
            return { results: [] };
          },
        };
        return statement;
      },
    } as unknown as D1Database;

    await retryAppleServerApiCorrections({
      DB: database,
      APP_ENVIRONMENT: "production",
      APPLE_IAP_BUNDLE_ID: "com.cardai.tcg",
    } as Env, { now: () => new Date("2026-08-25T00:00:00.000Z") });

    expect(calls).toHaveLength(2);
    expect(calls[0]!.sql).toContain("i.app_bundle_id = ?");
    expect(calls[0]!.values.slice(0, 3)).toEqual([
      "com.cardai.tcg",
      "Production",
      "Production",
    ]);
    expect(calls[1]!.values.slice(0, 3)).toEqual([
      "com.cardai.tcg",
      "Sandbox",
      "Sandbox",
    ]);
  });
});
