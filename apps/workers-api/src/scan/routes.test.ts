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
  object_type: string;
  grader: string;
  condition: string | null;
  grade: number | null;
  language: string | null;
  finish: string | null;
  quantity: number;
  purchase_price: number | null;
  purchase_currency: string | null;
  notes: string | null;
};
type WishlistRow = { owner_type: "anonymous" | "user"; owner_id: string; card_ref: string };
type CardCatalogRow = {
  product_id: string;
  game_id: number;
  game: string | null;
  set_name: string | null;
  set_code: string | null;
  name: string | null;
  rarity: string | null;
  product_type_name: string | null;
  image_url: string | null;
};

const PHASH = "vgM8KW2_mtY4LMLQZJvFpzl823zE3mx0mWhpCcRYaGw";

class FakeD1 {
  sessions: SessionRow[] = [];
  anonymousAccounts: AnonymousAccountRow[] = [];
  scanRecords: ScanRecordRow[] = [];
  folders: FolderRow[] = [];
  collectionItems: CollectionItemRow[] = [];
  wishlistItems: WishlistRow[] = [];
  cards: CardCatalogRow[] = [];

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
    if (sql.includes("FROM cards_all")) {
      const [cardRef] = this.values as [string];
      return (this.db.cards.find((row) => row.product_id === cardRef) ?? null) as T | null;
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
      const [
        id,
        ownerType,
        ownerId,
        folderId,
        cardRef,
        objectType,
        grader,
        condition,
        grade,
        language,
        finish,
        quantity,
        purchasePrice,
        purchaseCurrency,
        notes,
        ,
        ,
        scanId,
      ] = this.values as [
        string,
        "anonymous" | "user",
        string,
        string,
        string,
        string,
        string,
        string | null,
        number | null,
        string | null,
        string | null,
        number,
        number | null,
        string | null,
        string | null,
        string,
        string,
        string,
        string,
        string,
      ];
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
        object_type: objectType,
        grader,
        condition,
        grade,
        language,
        finish,
        quantity,
        purchase_price: purchasePrice,
        purchase_currency: purchaseCurrency,
        notes,
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

  it("resolves production pHash product ids through D1 and stores an audit record because App scans must be reviewable", async () => {
    const env = createTestEnv();
    env.DB.sessions.push({
      id: "session-1",
      owner_type: "anonymous",
      owner_id: "anon-1",
      expires_at: "2099-01-01T00:00:00.000Z",
      revoked_at: null,
    });
    env.DB.anonymousAccounts.push({ id: "anon-1", upgraded_user_id: null });
    env.DB.cards.push({
      product_id: "11958",
      game_id: 1,
      game: "Magic: The Gathering",
      set_name: "Champions of Kamigawa",
      set_code: "CHK",
      name: "Bushi Tenderfoot",
      rarity: "Uncommon",
      product_type_name: "Cards",
      image_url: null,
    });
    const token = await signAccessToken(
      { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
      env.JWT_SECRET,
    );

    vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
      expect(url).toBe("https://ocr.example.test/recognize");
      expect(init.method).toBe("POST");
      expect(init.headers).toEqual({
        Accept: "application/json",
        "Content-Type": "application/json",
      });
      expect(JSON.parse(String(init.body))).toEqual({ r: PHASH, g: PHASH, b: PHASH });
      return Response.json({ product_ids: [11958] });
    });

    const response = await app.request(
      "/api/v1/scan/recognize",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          r: PHASH,
          g: PHASH,
          b: PHASH,
          filename: "scan.jpg",
          platform: "iOS",
          app_version: "1.0.0",
        }),
      },
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
            candidates: [
              expect.objectContaining({
                card_ref: "11958",
                name: "Bushi Tenderfoot",
                set_code: "CHK",
                confidence: null,
                retrieval: "rgb-phash-16-v1",
              }),
            ],
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

  it("stores no_match when recognition ids are absent from D1 because an upstream id is not a reviewable card", async () => {
    const env = createRecognitionEnv();
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ product_ids: [999] })));

    const response = await recognize(env, token, { r: PHASH, g: PHASH, b: PHASH });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: expect.objectContaining({
        recognition_status: "no_match",
        cards_detected: 0,
        warnings: ["Some recognized cards are missing from the catalog."],
        results: [{ index: 1, matched: false, candidates: [] }],
      }),
    });
    expect(env.DB.scanRecords).toEqual([
      expect.objectContaining({ recognition_status: "no_match", candidates: "[]" }),
    ]);
  });

  it("rejects malformed pHashes before calling recognition because protocol errors must not create scan records", async () => {
    const env = createRecognitionEnv();
    const token = await recognitionToken(env);
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const response = await recognize(env, token, { r: "invalid", g: PHASH, b: PHASH });

    expect(response.status).toBe(422);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(env.DB.scanRecords).toEqual([]);
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
        body: JSON.stringify({
          folder_id: "main",
          card_ref: "11958",
          quantity: 2,
          grader: "PSA",
          condition: null,
          grade: 10,
          language: "Japanese",
          finish: "Foil",
          purchase_price: 12.5,
          purchase_currency: "USD",
          notes: "reviewed scan",
        }),
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
      expect.objectContaining({
        folder_id: "main",
        card_ref: "11958",
        object_type: "tcg",
        grader: "PSA",
        condition: null,
        grade: 10,
        language: "Japanese",
        finish: "Foil",
        quantity: 2,
        purchase_price: 12.5,
        purchase_currency: "USD",
        notes: "reviewed scan",
      }),
    ]);
    expect(env.DB.wishlistItems).toEqual([]);
    expect(env.DB.scanRecords[0]).toEqual(
      expect.objectContaining({
        user_confirmation_status: "confirmed",
        user_result: expect.stringContaining('"added_to_inventory":true'),
      }),
    );
  });

  it("persists Raw review fields because condition-based valuation must survive Scan confirmation", async () => {
    const env = createConfirmEnv();
    const token = await confirmToken(env);

    const response = await confirmScan(env, token, {
      folder_id: "main",
      card_ref: "11958",
      quantity: 3,
      grader: "Raw",
      condition: "Lightly Played (LP)",
      grade: null,
      language: "English",
      finish: "Holofoil",
      purchase_price: null,
      purchase_currency: null,
      notes: "binder copies",
    });

    expect(response.status).toBe(201);
    expect(env.DB.collectionItems).toEqual([
      expect.objectContaining({
        grader: "Raw",
        condition: "Lightly Played (LP)",
        grade: null,
        quantity: 3,
        purchase_price: null,
        purchase_currency: null,
        notes: "binder copies",
      }),
    ]);
  });

  it("rejects invalid review fields because Portfolio and Scan must enforce the same item invariants", async () => {
    const invalidBodies = [
      { grader: "Raw", condition: null, grade: null },
      { grader: "Raw", condition: "Near Mint (NM)", grade: 10 },
      { grader: "PSA", condition: "Near Mint (NM)", grade: 10 },
      { grader: "PSA", condition: null, grade: 10.25 },
      { grader: "Raw", condition: "Near Mint (NM)", grade: null, quantity: 0 },
      {
        grader: "Raw",
        condition: "Near Mint (NM)",
        grade: null,
        purchase_price: -1,
        purchase_currency: "USD",
      },
      {
        grader: "Raw",
        condition: "Near Mint (NM)",
        grade: null,
        notes: "x".repeat(501),
      },
      {
        grader: "Raw",
        condition: "Near Mint (NM)",
        grade: null,
        purchase_price: 1,
        purchase_currency: "usd",
      },
    ];

    for (const invalid of invalidBodies) {
      const env = createConfirmEnv();
      const token = await confirmToken(env);
      const response = await confirmScan(env, token, {
        folder_id: "main",
        card_ref: "11958",
        quantity: 1,
        purchase_price: null,
        purchase_currency: null,
        notes: null,
        ...invalid,
      });

      expect(response.status).toBe(422);
      expect(env.DB.collectionItems).toEqual([]);
      expect(env.DB.scanRecords[0]?.user_confirmation_status).toBe("pending");
    }
  });

  it("rejects foreign folders, non-candidates, and repeated confirmation because Review cannot cross ownership or duplicate items", async () => {
    const env = createConfirmEnv();
    env.DB.folders.push({ id: "foreign", owner_type: "user", owner_id: "other" });
    const token = await confirmToken(env);
    const base = {
      quantity: 1,
      grader: "Raw",
      condition: "Near Mint (NM)",
      grade: null,
      purchase_price: null,
      purchase_currency: null,
      notes: null,
    };

    const foreignFolder = await confirmScan(env, token, {
      ...base,
      folder_id: "foreign",
      card_ref: "11958",
    });
    const nonCandidate = await confirmScan(env, token, {
      ...base,
      folder_id: "main",
      card_ref: "not-a-candidate",
    });
    const first = await confirmScan(env, token, {
      ...base,
      folder_id: "main",
      card_ref: "11958",
    });
    const repeated = await confirmScan(env, token, {
      ...base,
      folder_id: "main",
      card_ref: "11958",
    });

    expect(foreignFolder.status).toBe(404);
    expect(nonCandidate.status).toBe(422);
    expect(first.status).toBe(201);
    expect(repeated.status).toBe(409);
    expect(env.DB.collectionItems).toHaveLength(1);
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

function createRecognitionEnv(): TestEnvWithFakeDb {
  const env = createTestEnv();
  env.DB.sessions.push({
    id: "session-1",
    owner_type: "anonymous",
    owner_id: "anon-1",
    expires_at: "2099-01-01T00:00:00.000Z",
    revoked_at: null,
  });
  env.DB.anonymousAccounts.push({ id: "anon-1", upgraded_user_id: null });
  return env;
}

function recognitionToken(env: TestEnvWithFakeDb): Promise<string> {
  return signAccessToken(
    { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
    env.JWT_SECRET,
  );
}

async function recognize(
  env: TestEnvWithFakeDb,
  token: string,
  body: Record<string, unknown>,
): Promise<Response> {
  return await app.request(
    "/api/v1/scan/recognize",
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
}

function createConfirmEnv(): TestEnvWithFakeDb {
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
  return env;
}

function confirmToken(env: TestEnvWithFakeDb): Promise<string> {
  return signAccessToken(
    { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
    env.JWT_SECRET,
  );
}

async function confirmScan(
  env: TestEnvWithFakeDb,
  token: string,
  body: Record<string, unknown>,
): Promise<Response> {
  return await app.request(
    "/api/v1/scan/scan-1/confirm",
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    },
    env,
  );
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
