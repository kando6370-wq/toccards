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
  image_url?: string | null;
  raw_response?: string;
};

type ScanQuotaRequestRow = {
  request_id: string;
  owner_type: "anonymous" | "user";
  owner_id: string;
  session_id: string;
  access_mode: "free" | "premium";
  status: "reserved" | "consumed" | "released";
  processing_expires_at: string | null;
  response_json: string | null;
  http_status: number | null;
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
  folder_joined_at: string;
};
type CollectionItemEventRow = Pick<
  CollectionItemRow,
  | "owner_type"
  | "owner_id"
  | "folder_id"
  | "card_ref"
  | "object_type"
  | "grader"
  | "condition"
  | "grade"
  | "language"
  | "finish"
  | "quantity"
> & {
  id: string;
  item_id: string;
  event_type: "upsert" | "delete";
  effective_at: string;
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
  number?: string | null;
};

const PHASH = "vgM8KW2_mtY4LMLQZJvFpzl823zE3mx0mWhpCcRYaGw";

class FakeR2 {
  readonly objects = new Map<string, Uint8Array>();

  async put(key: string, value: Uint8Array): Promise<R2Object> {
    this.objects.set(key, Uint8Array.from(value));
    return {} as R2Object;
  }

  async delete(key: string): Promise<void> {
    this.objects.delete(key);
  }
}

class FakeD1 {
  sessions: SessionRow[] = [];
  anonymousAccounts: AnonymousAccountRow[] = [];
  scanRecords: ScanRecordRow[] = [];
  scanQuotaRequests: ScanQuotaRequestRow[] = [];
  folders: FolderRow[] = [];
  collectionItems: CollectionItemRow[] = [];
  collectionItemEvents: CollectionItemEventRow[] = [];
  wishlistItems: WishlistRow[] = [];
  cards: CardCatalogRow[] = [];
  activePremiumSessionIds = new Set<string>();
  failScanInsert = false;

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
    if (sql.includes("FROM billing_session_entitlement_grant AS grant_record")) {
      const [sessionId] = this.values as [string];
      return (this.db.activePremiumSessionIds.has(sessionId)
        ? { id: "grant-1", purchase_chain_id: "chain-1", expires_at: null }
        : null) as T | null;
    }
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
    if (sql.includes("FROM scan_quota_request") && sql.includes("WHERE request_id = ?")) {
      const [requestId] = this.values as [string];
      return (this.db.scanQuotaRequests.find((row) => row.request_id === requestId) ?? null) as T | null;
    }
    if (sql.includes("FROM scan_quota_request") && sql.includes("SUM(CASE")) {
      const [ownerType, ownerId] = this.values as [string, string];
      const rows = this.db.scanQuotaRequests.filter(
        (row) => row.owner_type === ownerType && row.owner_id === ownerId && row.access_mode === "free",
      );
      return {
        reserved_count: rows.filter((row) => row.status === "reserved").length,
        consumed_count: rows.filter((row) => row.status === "consumed").length,
      } as T;
    }
    if (sql.includes("FROM portfolio_folder")) {
      const [id, ownerType, ownerId] = this.values as [string, string, string];
      return (this.db.folders.find(
        (row) => row.id === id && row.owner_type === ownerType && row.owner_id === ownerId,
      ) ?? null) as T | null;
    }
    if (sql.includes("FROM collection_item") && sql.includes("folder_id = ?")) {
      const [ownerType, ownerId, folderId, cardRef, language, finish] = this.values;
      return (this.db.collectionItems.find((row) =>
        row.owner_type === ownerType && row.owner_id === ownerId && row.folder_id === folderId &&
        row.card_ref === cardRef && row.language === language && row.finish === finish
      ) ?? null) as T | null;
    }
    return null;
  }

  async all<T = unknown>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);
    if (sql.includes("SELECT product_id, number") && sql.includes("FROM cards_all")) {
      const productIds = new Set(this.values.map(String));
      return okResult<T>(
        this.db.cards
          .filter((row) => productIds.has(row.product_id))
          .map((row) => ({ product_id: row.product_id, number: row.number ?? null })) as T[],
      );
    }
    if (sql.includes("FROM cards_all") && sql.includes("LIKE ?")) {
      const termCount = (sql.match(/LIKE \?/g) ?? []).length;
      const terms = this.values
        .slice(0, termCount)
        .map((value) => String(value).replaceAll("%", "").toLowerCase());
      const rows = this.db.cards.filter((row) => {
        const searchable = `${row.name ?? ""} ${row.number ?? ""} ${row.set_name ?? ""} ${row.set_code ?? ""} ${row.rarity ?? ""} ${row.game ?? ""}`
          .toLowerCase();
        return terms.every((term) => searchable.includes(term));
      });
      return okResult<T>(rows as T[]);
    }
    return okResult<T>();
  }

  async run<T = unknown>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);
    if (sql.startsWith("INSERT INTO scan_quota_request")) {
      const [requestId, ownerType, ownerId, sessionId, accessMode, leaseExpiresAt] = this.values as [
        string,
        "anonymous" | "user",
        string,
        string,
        "free" | "premium",
        string,
      ];
      if (this.db.scanQuotaRequests.some((row) => row.request_id === requestId)) {
        throw new Error("UNIQUE constraint failed: scan_quota_request.request_id");
      }
      const used = this.db.scanQuotaRequests.filter(
        (row) => row.owner_type === ownerType && row.owner_id === ownerId && row.access_mode === "free" &&
          (row.status === "reserved" || row.status === "consumed"),
      ).length;
      if (accessMode === "free" && used >= 10) return okResult<T>([], 0);
      this.db.scanQuotaRequests.push({
        request_id: requestId,
        owner_type: ownerType,
        owner_id: ownerId,
        session_id: sessionId,
        access_mode: accessMode,
        status: "reserved",
        processing_expires_at: leaseExpiresAt,
        response_json: null,
        http_status: null,
      });
      return okResult<T>();
    }
    if (sql.startsWith("UPDATE scan_quota_request") && sql.includes("SET status = ?")) {
      const [status, , responseJson, httpStatus, , , requestId, ownerType, ownerId, sessionId] = this.values as [
        "consumed" | "released", string | null, string | null, number | null, string, string, string, string, string, string,
      ];
      const row = this.db.scanQuotaRequests.find(
        (candidate) => candidate.request_id === requestId && candidate.owner_type === ownerType &&
          candidate.owner_id === ownerId && candidate.session_id === sessionId && candidate.status === "reserved",
      );
      if (!row) return okResult<T>([], 0);
      row.status = status;
      row.response_json = responseJson;
      row.http_status = httpStatus;
      return okResult<T>();
    }
    if (sql.startsWith("INSERT INTO scan_record")) {
      if (this.db.failScanInsert) throw new Error("scan insert failed");
      const [id, ownerType, ownerId, imageUrl, , , , , , recognitionStatus, confirmationStatus, systemResult, userResult, candidates, rawResponse] =
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
        image_url: imageUrl,
        raw_response: rawResponse,
      });
      return okResult<T>();
    }
    if (sql.startsWith("INSERT INTO collection_item_event")) {
      const [id, effectiveAt, itemId, ownerType, ownerId] = this.values as [
        string,
        string,
        string,
        "anonymous" | "user",
        string,
      ];
      const item = this.db.collectionItems.find(
        (row) => row.id === itemId && row.owner_type === ownerType && row.owner_id === ownerId,
      );
      if (!item) return okResult<T>([], 0);
      this.db.collectionItemEvents.push({
        id,
        item_id: item.id,
        owner_type: item.owner_type,
        owner_id: item.owner_id,
        folder_id: item.folder_id,
        card_ref: item.card_ref,
        object_type: item.object_type,
        grader: item.grader,
        condition: item.condition,
        grade: item.grade,
        language: item.language,
        finish: item.finish,
        quantity: item.quantity,
        event_type: "upsert",
        effective_at: effectiveAt,
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
        folderJoinedAt,
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
        folder_joined_at: folderJoinedAt,
      });
      return okResult<T>();
    }
    if (sql.startsWith("DELETE FROM wishlist_item")) {
      const [ownerType, ownerId, cardRef, itemId] = this.values as [
        string,
        string,
        string,
        string,
      ];
      if (!this.db.collectionItems.some((row) => row.id === itemId)) {
        return okResult<T>([], 0);
      }
      const before = this.db.wishlistItems.length;
      this.db.wishlistItems = this.db.wishlistItems.filter(
        (row) => !(row.owner_type === ownerType && row.owner_id === ownerId && row.card_ref === cardRef),
      );
      return okResult<T>([], before - this.db.wishlistItems.length);
    }
    if (sql.startsWith("INSERT INTO mutation_lock")) {
      return okResult<T>();
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
      product_id: "10738",
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
      return Response.json({
        candidates: [
          { product_id: 10738, confidence: 80.99 },
          { product_id: 240872, confidence: 80.729 },
        ],
      });
    });

    const requestId = crypto.randomUUID();
    const response = await app.request(
      "/api/v1/scan/recognize",
      {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Idempotency-Key": requestId },
        body: recognitionForm({
          request_id: requestId,
          r: PHASH, g: PHASH, b: PHASH, filename: "scan.jpg",
          platform: "iOS", app_version: "1.0.0",
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
        quota: {
          access: "free",
          unlimited: false,
          limit: 10,
          reserved: 0,
          consumed: 1,
          remaining: 9,
        },
        results: [
          expect.objectContaining({
            matched: true,
            candidates: [
              expect.objectContaining({
                card_ref: "10738",
                name: "Bushi Tenderfoot",
                set_code: "CHK",
                confidence: 80.99,
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
        image_url: expect.stringMatching(/^scans\/anonymous\/anon-1\/\d{4}\/\d{2}\/.+\.jpg$/),
        candidates: expect.stringContaining('"confidence":80.729'),
        raw_response: JSON.stringify({
          candidates: [
            { product_id: 10738, confidence: 80.99 },
            { product_id: 240872, confidence: 80.729 },
          ],
        }),
      }),
    ]);
  });

  it("returns an unlimited Premium quota without spending Free allowance", async () => {
    const env = createRecognitionEnv();
    env.DB.activePremiumSessionIds.add("session-1");
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ candidates: [] })));

    const response = await recognize(env, token, { r: PHASH, g: PHASH, b: PHASH });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toMatchObject({
      data: {
        quota: {
          access: "premium",
          unlimited: true,
          limit: 10,
          reserved: 0,
          consumed: 0,
          remaining: 10,
        },
      },
    });
    expect(env.DB.scanQuotaRequests).toEqual([
      expect.objectContaining({ access_mode: "premium", status: "consumed" }),
    ]);
  });

  it("promotes an exact printed number because pHash alone cannot distinguish cards with identical artwork", async () => {
    const env = createRecognitionEnv();
    env.DB.cards.push(
      {
        product_id: "610499",
        game_id: 3,
        game: "Pokemon",
        set_name: "Prismatic Evolutions",
        set_code: "PRE",
        name: "Leafeon ex",
        rarity: "Special Illustration Rare",
        product_type_name: "Cards",
        image_url: null,
        number: "144/131",
      },
      {
        product_id: "602664",
        game_id: 3,
        game: "Pokemon",
        set_name: "Terastal Festival ex",
        set_code: "SV8a",
        name: "Leafeon ex",
        rarity: "Special Art Rare",
        product_type_name: "Cards",
        image_url: null,
        number: "200/187",
      },
    );
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", async (_url: string, init: RequestInit) => {
      expect(JSON.parse(String(init.body))).toEqual({ r: PHASH, g: PHASH, b: PHASH });
      return Response.json({
        candidates: [
          { product_id: 610499, confidence: 84.1 },
          { product_id: 602664, confidence: 83.854 },
        ],
      });
    });

    const response = await recognize(env, token, {
      r: PHASH,
      g: PHASH,
      b: PHASH,
      card_number: "200 / 187",
    });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual(expect.objectContaining({
      data: expect.objectContaining({
        results: [expect.objectContaining({
          candidates: [
            expect.objectContaining({
              rank: 1,
              card_ref: "602664",
              card_number: "200/187",
              retrieval: "rgb-phash-16-v1+card-number-ocr",
            }),
            expect.objectContaining({ rank: 2, card_ref: "610499" }),
          ],
        })],
      }),
    }));
    expect(env.DB.scanRecords[0]?.system_result).toContain('"number":"200/187"');
  });

  it("recovers an exact catalog printing because the correct version may fall outside the pHash candidate limit", async () => {
    const env = createRecognitionEnv();
    env.DB.cards.push(
      {
        product_id: "610499",
        game_id: 3,
        game: "Pokemon",
        set_name: "Prismatic Evolutions",
        set_code: "PRE",
        name: "Leafeon ex",
        rarity: "Special Illustration Rare",
        product_type_name: "Cards",
        image_url: null,
        number: "144/131",
      },
      {
        product_id: "602664",
        game_id: 3,
        game: "Pokemon",
        set_name: "Terastal Festival ex",
        set_code: "SV8a",
        name: "Leafeon ex",
        rarity: "Special Art Rare",
        product_type_name: "Cards",
        image_url: null,
        number: "200/187",
      },
    );
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", async () =>
      Response.json({
        candidates: [{ product_id: 610499, confidence: 84.1 }],
      })
    );

    const response = await recognize(env, token, {
      r: PHASH,
      g: PHASH,
      b: PHASH,
      card_number: "200/187",
    });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual(expect.objectContaining({
      data: expect.objectContaining({
        results: [expect.objectContaining({
          candidates: [
            expect.objectContaining({
              card_ref: "602664",
              card_number: "200/187",
              retrieval: "rgb-phash-16-v1+card-number-ocr",
            }),
            expect.objectContaining({ card_ref: "610499" }),
          ],
        })],
      }),
    }));
  });

  it("stores no_match when recognition ids are absent from D1 because an upstream id is not a reviewable card", async () => {
    const env = createRecognitionEnv();
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: 999, confidence: 77.125 }],
    })));

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
      expect.objectContaining({
        recognition_status: "no_match",
        candidates: expect.stringContaining('"confidence":77.125'),
      }),
    ]);
  });

  it("rejects the eleventh Free scan before R2 and OCR because the server quota is authoritative", async () => {
    const env = createRecognitionEnv();
    const token = await recognitionToken(env);
    for (let index = 0; index < 10; index += 1) {
      env.DB.scanQuotaRequests.push({
        request_id: crypto.randomUUID(),
        owner_type: "anonymous",
        owner_id: "anon-1",
        session_id: "session-1",
        access_mode: "free",
        status: "consumed",
        processing_expires_at: null,
        response_json: null,
        http_status: null,
      });
    }
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const response = await recognize(env, token, { r: PHASH, g: PHASH, b: PHASH });

    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({
      error: { code: "SCAN_QUOTA_EXHAUSTED" },
      quota: {
        access: "free",
        unlimited: false,
        limit: 10,
        reserved: 0,
        consumed: 10,
        remaining: 0,
      },
    });
    expect(fetchMock).not.toHaveBeenCalled();
    expect((env.SCAN_IMAGES as unknown as FakeR2).objects.size).toBe(0);
  });

  it("replays a completed request because a lost response must not consume quota or OCR twice", async () => {
    const env = createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();
    const fetchMock = vi.fn().mockResolvedValue(Response.json({ candidates: [] }));
    vi.stubGlobal("fetch", fetchMock);

    const first = await recognize(env, token, { request_id: requestId, r: PHASH, g: PHASH, b: PHASH });
    const firstBody = await first.json();
    const second = await recognize(env, token, { request_id: requestId, r: PHASH, g: PHASH, b: PHASH });

    expect(second.status).toBe(200);
    expect(await second.json()).toEqual(firstBody);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(env.DB.scanQuotaRequests).toEqual([
      expect.objectContaining({ request_id: requestId, status: "consumed" }),
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

  it("stores failed with the raw upstream payload because every valid recognition attempt must remain auditable", async () => {
    const env = createRecognitionEnv();
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json(
      { error: "internal_error" },
      { status: 500 },
    )));

    const response = await recognize(env, token, { r: PHASH, g: PHASH, b: PHASH });
    const body = await response.json() as { scan_id?: unknown };

    expect(response.status).toBe(502);
    expect(body.scan_id).toEqual(expect.any(String));
    expect(env.DB.scanRecords).toEqual([
      expect.objectContaining({
        recognition_status: "failed",
        candidates: "[]",
      }),
    ]);
  });

  it("rejects the retired product_ids response as an upstream failure because clients must not silently lose production confidence", async () => {
    const env = createRecognitionEnv();
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ product_ids: [10738] })));

    const response = await recognize(env, token, { r: PHASH, g: PHASH, b: PHASH });

    expect(response.status).toBe(502);
    expect(env.DB.scanRecords[0]?.recognition_status).toBe("failed");
  });

  it("rejects out-of-range upstream confidence because similarity must remain the exact finite 0 to 100 service value", async () => {
    const env = createRecognitionEnv();
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: 10738, confidence: 100.001 }],
    })));

    const response = await recognize(env, token, { r: PHASH, g: PHASH, b: PHASH });

    expect(response.status).toBe(502);
    expect(env.DB.scanRecords[0]?.recognition_status).toBe("failed");
  });

  it("deletes the private image when D1 insert fails because compensation must not leave an orphaned R2 object", async () => {
    const env = createRecognitionEnv();
    env.DB.failScanInsert = true;
    const token = await recognitionToken(env);
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ candidates: [] })));

    const response = await recognize(env, token, { r: PHASH, g: PHASH, b: PHASH });

    expect(response.status).toBe(500);
    expect((env.SCAN_IMAGES as unknown as FakeR2).objects.size).toBe(0);
    expect(env.DB.scanRecords).toEqual([]);
  });

  it("confirms a stored candidate and records its valuation event because Scan additions must reach Collection and HOME", async () => {
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
        folder_joined_at: expect.any(String),
      }),
    ]);
    expect(env.DB.collectionItemEvents).toEqual([
      expect.objectContaining({
        item_id: env.DB.collectionItems[0]?.id,
        owner_type: "anonymous",
        owner_id: "anon-1",
        folder_id: "main",
        card_ref: "11958",
        object_type: "tcg",
        grader: "PSA",
        condition: null,
        grade: 10,
        language: "Japanese",
        finish: "Foil",
        quantity: 2,
        event_type: "upsert",
        effective_at: env.DB.collectionItems[0]?.folder_joined_at,
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
      card_ref: "240872",
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

  it("rejects the same scanned card, finish, and language despite different grading", async () => {
    const env = createConfirmEnv();
    env.DB.collectionItems.push({
      id: "owned", owner_type: "anonymous", owner_id: "anon-1", folder_id: "main",
      card_ref: "11958", object_type: "tcg", grader: "Raw",
      condition: "Near Mint (NM)", grade: null, language: "English",
      finish: "Holofoil", quantity: 1, purchase_price: null,
      purchase_currency: null, notes: null, folder_joined_at: "2026-07-20T00:00:00.000Z",
    });

    const response = await confirmScan(env, await confirmToken(env), {
      folder_id: "main", card_ref: "11958", quantity: 1, grader: "PSA",
      condition: null, grade: 10, language: "English",
      finish: "Holofoil", purchase_price: null, purchase_currency: null, notes: null,
    });

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ error: { code: "DUPLICATE_COLLECTION_ITEM" } });
    expect(env.DB.collectionItems).toHaveLength(1);
    expect(env.DB.scanRecords[0]?.user_confirmation_status).toBe("pending");
  });
});

type TestEnvWithFakeDb = Omit<TestEnv, "DB"> & { DB: FakeD1 };

function createTestEnv(): TestEnvWithFakeDb {
  const scanImages = new FakeR2();
  return {
    DB: new FakeD1(),
    CACHE_KV: {} as KVNamespace,
    JWT_SECRET: "test-secret",
    OCR_SERVICE_BASE_URL: "https://ocr.example.test",
    SCAN_IMAGES: scanImages as unknown as R2Bucket,
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
  const requestId = typeof body.request_id === "string" ? body.request_id : crypto.randomUUID();
  return await app.request(
    "/api/v1/scan/recognize",
    {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Idempotency-Key": requestId },
      body: recognitionForm({ ...body, request_id: requestId }),
    },
    env,
  );
}

function recognitionForm(body: Record<string, unknown>): FormData {
  const form = new FormData();
  for (const [key, value] of Object.entries(body)) {
    if (value !== undefined && value !== null) form.set(key, String(value));
  }
  form.set(
    "image",
    new File([SCAN_JPEG], "scan.jpg", { type: "image/jpeg" }),
  );
  return form;
}

const SCAN_JPEG = new Uint8Array([
  0xff, 0xd8,
  0xff, 0xc0, 0x00, 0x11, 0x08, 0x04, 0x13, 0x02, 0xe9, 0x03,
  0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00,
  0xff, 0xd9,
]);

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
    candidates: JSON.stringify([
      { card_ref: "11958", name: "Bushi Tenderfoot", catalog_matched: true },
      { card_ref: "240872", name: null, catalog_matched: false },
    ]),
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
