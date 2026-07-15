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
  user_confirmation_status: string;
  system_result: string;
  user_result: string;
  candidates: string;
  modified_result: number;
};

type FolderRow = { id: string; owner_type: "anonymous" | "user"; owner_id: string };
type CollectionItemRow = {
  id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  folder_id: string;
  card_ref: string;
};
type WishlistRow = { owner_type: "anonymous" | "user"; owner_id: string; card_ref: string };

class FakeD1 {
  sessions: SessionRow[] = [];
  anonymousAccounts: AnonymousAccountRow[] = [];
  scanRecords: ScanRecordRow[] = [];
  folders: FolderRow[] = [];
  collectionItems: CollectionItemRow[] = [];
  wishlistItems: WishlistRow[] = [];

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
  }

  async batch<T = unknown>(statements: FakeD1Statement[]): Promise<D1Result<T>[]> {
    const results = [];
    for (const statement of statements) results.push(await statement.run<T>());
    return results;
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
    if (sql.includes("FROM scan_record")) {
      const [id, ownerType, ownerId] = this.values as [string, string, string];
      return (this.db.scanRecords.find(
        (row) => row.id === id && row.owner_type === ownerType && row.owner_id === ownerId,
      ) ?? null) as T | null;
    }
    if (sql.includes("FROM portfolio_folder")) {
      const [id, ownerType, ownerId] = this.values as [string, string, string];
      return (this.db.folders.find(
        (row) => row.id === id && row.owner_type === ownerType && row.owner_id === ownerId,
      ) ?? null) as T | null;
    }
    return null;
  }

  async run<T = unknown>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);
    if (sql.startsWith("INSERT INTO scan_record")) {
      const [id, ownerType, ownerId, , , , , , , recognitionStatus, confirmationStatus, systemResult, userResult, candidates] =
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
        user_confirmation_status: confirmationStatus,
        system_result: systemResult,
        user_result: userResult,
        candidates,
        modified_result: 0,
      });
      return okResult<T>();
    }
    if (sql.startsWith("INSERT INTO collection_item")) {
      const [id, ownerType, ownerId, folderId, cardRef, , , scanId] =
        this.values as [string, "anonymous" | "user", string, string, string, string, string, string];
      const pending = this.db.scanRecords.some(
        (row) => row.id === scanId && row.owner_type === ownerType &&
          row.owner_id === ownerId && row.user_confirmation_status === "pending",
      );
      if (!pending) return okResult<T>([], 0);
      this.db.collectionItems.push({
        id,
        owner_type: ownerType,
        owner_id: ownerId,
        folder_id: folderId,
        card_ref: cardRef,
      });
      return okResult<T>();
    }
    if (sql.startsWith("DELETE FROM wishlist_item")) {
      const [ownerType, ownerId, cardRef] = this.values as [string, string, string];
      const before = this.db.wishlistItems.length;
      this.db.wishlistItems = this.db.wishlistItems.filter(
        (row) => !(row.owner_type === ownerType && row.owner_id === ownerId && row.card_ref === cardRef),
      );
      return okResult<T>([], before - this.db.wishlistItems.length);
    }
    if (sql.startsWith("UPDATE scan_record")) {
      const [modifiedResult, userResult, id, ownerType, ownerId] = this.values as [
        number, string, string, string, string,
      ];
      const row = this.db.scanRecords.find(
        (candidate) => candidate.id === id && candidate.owner_type === ownerType &&
          candidate.owner_id === ownerId && candidate.user_confirmation_status === "pending",
      );
      if (!row) return okResult<T>([], 0);
      row.user_confirmation_status = "confirmed";
      row.modified_result = modifiedResult;
      row.user_result = userResult;
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

  it("confirms a stored candidate into Portfolio atomically because Review must not report a local-only add", async () => {
    const env = createTestEnv();
    env.DB.sessions.push({
      id: "session-1",
      owner_type: "anonymous",
      owner_id: "anon-1",
      expires_at: "2099-01-01T00:00:00.000Z",
      revoked_at: null,
    });
    env.DB.anonymousAccounts.push({ id: "anon-1", upgraded_user_id: null });
    env.DB.folders.push({ id: "main", owner_type: "anonymous", owner_id: "anon-1" });
    env.DB.wishlistItems.push({
      owner_type: "anonymous",
      owner_id: "anon-1",
      card_ref: "11958",
    });
    env.DB.scanRecords.push({
      id: "scan-1",
      owner_type: "anonymous",
      owner_id: "anon-1",
      recognition_status: "success",
      user_confirmation_status: "pending",
      system_result: "{}",
      user_result: "{}",
      candidates: JSON.stringify([{ card_ref: "11958", name: "Bushi Tenderfoot" }]),
      modified_result: 0,
    });
    const token = await signAccessToken(
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      env.JWT_SECRET,
    );

    const response = await app.request(
      "/api/v1/scan/scan-1/confirm",
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({ folder_id: "main", card_ref: "11958" }),
      },
      env,
    );
    const body = await response.json();

    expect(response.status).toBe(201);
    expect(body).toEqual({
      success: true,
      data: {
        scan_id: "scan-1",
        collection_item_id: expect.any(String),
        card_ref: "11958",
        folder_id: "main",
      },
    });
    expect(env.DB.collectionItems).toEqual([
      expect.objectContaining({ folder_id: "main", card_ref: "11958" }),
    ]);
    expect(env.DB.wishlistItems).toEqual([]);
    expect(env.DB.scanRecords[0]).toEqual(
      expect.objectContaining({
        user_confirmation_status: "confirmed",
        user_result: expect.stringContaining('"added_to_inventory":true'),
      }),
    );
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
