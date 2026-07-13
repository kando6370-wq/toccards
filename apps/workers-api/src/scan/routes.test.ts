import { signAccessToken } from "@kando/auth-core";
import { afterEach, describe, expect, it, vi } from "vitest";
import app, { type Env as AppEnv } from "../index";

type TestEnv = AppEnv & { JWT_SECRET: string; OCR_SERVICE_BASE_URL: string };

type SessionRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

type AnonymousAccountRow = {
  id: string;
  upgraded_user_id: string | null;
};

type ScanRecordRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  recognition_status: string;
  system_result: string;
  candidates: string;
};

class FakeD1 {
  sessions: SessionRow[] = [];
  anonymousAccounts: AnonymousAccountRow[] = [];
  scanRecords: ScanRecordRow[] = [];

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
  }
}

class FakeD1Statement {
  private values: unknown[] = [];

  constructor(
    private readonly db: FakeD1,
    private readonly sql: string,
  ) {}

  bind(...values: unknown[]): FakeD1Statement {
    this.values = values;
    return this;
  }

  async first<T = unknown>(): Promise<T | null> {
    const sql = normalizeSql(this.sql);
    if (sql.includes("FROM session") && sql.includes("WHERE id = ?")) {
      const [id] = this.values as [string];
      return (this.db.sessions.find((row) => row.id === id) ?? null) as T | null;
    }
    if (sql.includes("FROM anonymous_account")) {
      const [id] = this.values as [string];
      return (this.db.anonymousAccounts.find((row) => row.id === id && row.upgraded_user_id === null) ?? null) as T | null;
    }
    return null;
  }

  async run<T = unknown>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);
    if (sql.startsWith("INSERT INTO scan_record")) {
      const [id, ownerType, ownerId, , , , , , , recognitionStatus, , systemResult, , candidates] =
        this.values as [
          string,
          "anonymous" | "user",
          string,
          string | null,
          string,
          string,
          string | null,
          string | null,
          string | null,
          string,
          string,
          string,
          string,
          string,
          string,
          string,
        ];
      this.db.scanRecords.push({
        id,
        owner_type: ownerType,
        owner_id: ownerId,
        recognition_status: recognitionStatus,
        system_result: systemResult,
        candidates,
      });
      return okResult<T>();
    }
    throw new Error(`Unsupported run SQL: ${sql}`);
  }
}

describe("scan routes", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("proxies images to OCR and stores an audit record because App scans must be visible in Admin", async () => {
    const env = createTestEnv();
    env.DB.sessions.push({
      id: "session-1",
      owner_type: "anonymous",
      owner_id: "anon-1",
      expires_at: "2099-01-01T00:00:00.000Z",
      revoked_at: null,
    });
    env.DB.anonymousAccounts.push({ id: "anon-1", upgraded_user_id: null });
    const token = await signAccessToken(
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      env.JWT_SECRET,
    );

    vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
      expect(url).toBe("https://ocr.example.test/recognize");
      expect(init.method).toBe("POST");
      expect(init.body).toBeInstanceOf(FormData);
      return Response.json({
        ok: true,
        filename: "scan.jpg",
        elapsed: 0.25,
        retrieval: "phash",
        ocr_model: "small",
        cards_detected: 1,
        warnings: [],
        results: [
          {
            index: 1,
            matched: true,
            matches: [
              {
                product_id: "11958",
                game: "Magic: The Gathering",
                name: "Bushi Tenderfoot",
                set: "CHK",
                number: "1",
                confidence: 86.2,
                retrieval: "phash",
              },
            ],
          },
        ],
      });
    });

    const form = new FormData();
    form.set("image", new File(["image-bytes"], "scan.jpg", { type: "image/jpeg" }));
    form.set("platform", "iOS");
    form.set("app_version", "1.0.0");

    const response = await app.request(
      "/api/v1/scan/recognize",
      { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form },
      env,
    );
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: expect.objectContaining({
        recognition_status: "success",
        results: [
          expect.objectContaining({
            matched: true,
            candidates: [expect.objectContaining({ card_ref: "11958", confidence: 86.2 })],
          }),
        ],
      }),
    });
    expect(env.DB.scanRecords).toEqual([
      expect.objectContaining({
        owner_type: "anonymous",
        owner_id: "anon-1",
        recognition_status: "success",
        system_result: expect.stringContaining("Bushi Tenderfoot"),
        candidates: expect.stringContaining("11958"),
      }),
    ]);
  });
});

type TestEnvWithFakeDb = Omit<TestEnv, "DB"> & { DB: FakeD1 };

function createTestEnv(): TestEnvWithFakeDb {
  return {
    DB: new FakeD1(),
    CACHE_KV: {} as KVNamespace,
    JWT_SECRET: "test-secret",
    OCR_SERVICE_BASE_URL: "https://ocr.example.test",
  };
}

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim();
}

function okResult<T>(results: T[] = [], changes = 1): D1Result<T> {
  return {
    success: true,
    results,
    meta: {
      duration: 0,
      size_after: 0,
      rows_read: 0,
      rows_written: changes,
      last_row_id: 0,
      changed_db: changes > 0,
      changes,
    },
  };
}
