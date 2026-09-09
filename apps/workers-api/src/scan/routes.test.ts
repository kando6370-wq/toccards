import { signAccessToken } from "@kando/auth-core";
import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import app, { type Env as AppEnv } from "../index";
import { PGliteDatabase } from "../test-support/pglite-database";

type TestEnvWithPostgres = Omit<AppEnv, "DB"> & { DB: PGliteDatabase; queries: string[]; VECTOR_RECOGNITION?: Fetcher };
const VECTOR = Array.from({ length: 512 }, (_, index) => (index + 1) / 512);
const databases: PGliteDatabase[] = [];
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


describe("scan routes", () => {
  it("rejects retired hashes and invalid vectors before storage or quota consumption", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const upstream = vi.fn();
    stubVectorRecognition(env, upstream);
    for (const body of [
      { r: "legacy", g: "legacy", b: "legacy" },
      { vector: [] },
      { vector: [1, 2, 3] },
      { vector: Array.from({ length: 512 }, () => 0) },
      { vector: [...VECTOR.slice(0, 511), null] },
      { vector: [...VECTOR, 1] },
    ]) {
      expect((await recognize(env, token, body)).status).toBe(422);
    }
    expect(upstream).not.toHaveBeenCalled();
    expect(await readRows(env.DB, "scan_record")).toEqual([]);
    expect(await readRows(env.DB, "scan_quota_request")).toEqual([]);
    expect((env.SCAN_IMAGES as unknown as FakeR2).objects.size).toBe(0);
  });

  it("keeps the game filter in the catalog boundary because vector search receives no game or owner information", async () => {
    const env = await createRecognitionEnv();
    await insertRows(env.DB, "cards_all",
      { product_id: "same-game", game_id: 1, game: "Pokemon", name: "Wanted Card", set_name: "Set A", product_type_name: "Cards" },
      { product_id: "other-game", game_id: 2, game: "Magic", name: "Other Card", set_name: "Set B", product_type_name: "Cards" },
    );
    const upstream = vi.fn(async (_url, init) => {
      expect(JSON.parse(init.body)).toEqual({ vector: VECTOR });
      return Response.json({ candidates: [{ product_id: "other-game", confidence: 99 }, { product_id: "same-game", confidence: 90 }] });
    });
    stubVectorRecognition(env, upstream);
    const response = await recognize(env, await recognitionToken(env), { vector: VECTOR, game_id: 1 });
    expect(response.status).toBe(200);
    const body = await response.json() as { data: { results: Array<{ candidates: Array<{ card_ref: string }> }> } };
    expect(body.data.results[0].candidates.map((candidate) => candidate.card_ref)).toEqual(["same-game"]);
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    await Promise.all(databases.splice(0).map((db) => db.close()));
  });

  it("resolves production vector product ids through PostgreSQL and stores an audit record because App scans must be reviewable", async () => {
    const env = await createTestEnv();
    await insertRows(env.DB, "session", {
      id: "session-1",
      owner_type: "anonymous",
      owner_id: "anon-1",
      expires_at: "2099-01-01T00:00:00.000Z",
      revoked_at: null,
    });
    await insertRows(env.DB, "anonymous_account", { id: "anon-1", upgraded_user_id: null });
    await insertRows(env.DB, "cards_all", {
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

    stubVectorRecognition(env, async (url: string, init: RequestInit) => {
      expect(url).toBe("https://recognize-vec.internal/recognize");
      expect(init.method).toBe("POST");
      expect(init.headers).toEqual({
        Accept: "application/json",
        "Content-Type": "application/json",
      });
      expect(JSON.parse(String(init.body))).toEqual({ vector: VECTOR });
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
          vector: VECTOR, filename: "scan.jpg",
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
                product_id: "10738",
                card_ref: "10738",
                name: "Bushi Tenderfoot",
                set_code: "CHK",
                confidence: 80.99,
                retrieval: "pe-core-t16-384-cosine-v1",
              }),
            ],
          }),
        ],
      }),
    });
    expect((await readRows(env.DB, "scan_record"))).toEqual([
      expect.objectContaining({
        environment: "development",
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

  it("preserves an alphanumeric sports product id because catalog identity is text across the App", async () => {
    const env = await createRecognitionEnv();
    await insertRows(env.DB, "cards_all", {
      product_id: "sports:soccer:rookie-001",
      game_id: 100003,
      game: "Soccer",
      set_name: "Rookie Debut",
      set_code: "RD",
      name: "Alex Rookie",
      rarity: "Rookie",
      product_type_name: "Cards",
      image_url: null,
    });
    const token = await recognitionToken(env);
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [
        { product_id: "sports:soccer:rookie-001", confidence: 91.25 },
      ],
    })));

    const response = await recognize(env, token, { vector: VECTOR });
    const body = await response.json() as {
      data: { results: Array<{ candidates: Array<{ product_id: string; card_ref: string }> }> };
    };

    expect(response.status).toBe(200);
    expect(body.data.results[0]?.candidates[0]).toEqual(expect.objectContaining({
      product_id: "sports:soccer:rookie-001",
      card_ref: "sports:soccer:rookie-001",
    }));
    expect((await readRows(env.DB, "scan_record"))[0]?.candidates).toContain(
      '"product_id":"sports:soccer:rookie-001"',
    );
  });

  it("resolves thirty vector search candidates with one catalog query and no price query because Scan must not amplify latency per candidate", async () => {
    const env = await createRecognitionEnv();
    const recognized = Array.from({ length: 30 }, (_, index) => ({
      product_id: `scan-card-${index}`,
      confidence: 90 - index,
    }));
    await insertRows(env.DB, "cards_all", ...recognized.map((candidate, index) => ({
      product_id: candidate.product_id,
      game_id: 1,
      game: "Magic: The Gathering",
      set_name: "Scan Set",
      set_code: "SCN",
      name: `Scan Card ${index}`,
      rarity: "Common",
      product_type_name: "Cards",
      image_url: null,
      number: `${index + 1}/030`,
    })));
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: recognized,
    })));

    const response = await recognize(
      env,
      await recognitionToken(env),
      { vector: VECTOR },
    );
    const body = await response.json() as {
      data: { results: Array<{ candidates: Array<{ product_id: string }> }> };
    };
    const catalogQueries = env.queries.filter((sql) =>
      sql.includes("FROM cards_all")
    );
    const priceQueries = env.queries.filter((sql) =>
      sql.includes("WITH ranked_current")
    );

    expect(response.status).toBe(200);
    expect(body.data.results[0]?.candidates.map((item) => item.product_id)).toEqual(
      recognized.map((item) => item.product_id),
    );
    expect(catalogQueries).toHaveLength(1);
    expect(priceQueries).toHaveLength(0);
  });

  it("returns an unlimited Premium quota without spending Free allowance", async () => {
    const env = await createRecognitionEnv();
    await grantPremium(env.DB);
    const token = await recognitionToken(env);
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({ candidates: [] })));

    const response = await recognize(env, token, { vector: VECTOR });
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
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({ access_mode: "premium", status: "released" }),
    ]);
  });

  it("returns the server reservation before vector search because Processing must show the current remaining quota", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();

    const reservation = await app.request(
      "/api/v1/scan/quota/reserve",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          "Idempotency-Key": requestId,
        },
        body: JSON.stringify({ request_id: requestId }),
      },
      env,
    );

    expect(reservation.status).toBe(200);
    expect(await reservation.json()).toMatchObject({
      success: true,
      data: {
        request_id: requestId,
        quota: {
          access: "free",
          unlimited: false,
          reserved: 1,
          consumed: 0,
          remaining: 9,
        },
      },
    });
    expect((await readRows(env.DB, "scan_record"))).toEqual([]);

    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({ candidates: [] })));
    const response = await recognize(env, token, {
      request_id: requestId,
      vector: VECTOR,
    });
    expect(response.status).toBe(200);
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({ status: "released" }),
    ]);
  });

  it("releases a queued reservation when recognition cannot start because unavailable vector search must not hold Free quota", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();
    const reservation = await app.request(
      "/api/v1/scan/quota/reserve",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          "Idempotency-Key": requestId,
        },
        body: JSON.stringify({ request_id: requestId }),
      },
      env,
    );
    expect(reservation.status).toBe(200);
    env.VECTOR_RECOGNITION = undefined;

    const response = await recognize(env, token, {
      request_id: requestId,
      vector: VECTOR,
    });

    expect(response.status).toBe(503);
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({ status: "released" }),
    ]);
  });

  it("releases a queued reservation when the trusted app environment is missing", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();
    const reservation = await app.request(
      "/api/v1/scan/quota/reserve",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          "Idempotency-Key": requestId,
        },
        body: JSON.stringify({ request_id: requestId }),
      },
      env,
    );
    expect(reservation.status).toBe(200);
    delete env.APP_ENVIRONMENT;

    const response = await recognize(env, token, {
      request_id: requestId,
      vector: VECTOR,
    });

    expect(response.status).toBe(503);
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({ status: "released" }),
    ]);
    expect((env.SCAN_IMAGES as unknown as FakeR2).objects.size).toBe(0);
  });

  it("promotes an exact printed number because vector alone cannot distinguish cards with identical artwork", async () => {
    const env = await createRecognitionEnv();
    await insertRows(env.DB, "cards_all",
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
    stubVectorRecognition(env, async (_url: string, init: RequestInit) => {
      expect(JSON.parse(String(init.body))).toEqual({ vector: VECTOR });
      return Response.json({
        candidates: [
          { product_id: 610499, confidence: 84.1 },
          { product_id: 602664, confidence: 83.854 },
        ],
      });
    });

    const response = await recognize(env, token, {
      vector: VECTOR,
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
              retrieval: "pe-core-t16-384-cosine-v1+card-number-ocr",
            }),
            expect.objectContaining({ rank: 2, card_ref: "610499" }),
          ],
        })],
      }),
    }));
    expect((await readRows(env.DB, "scan_record"))[0]?.system_result).toContain('"number":"200/187"');
  });

  it("recovers an exact catalog printing because the correct version may fall outside the vector candidate limit", async () => {
    const env = await createRecognitionEnv();
    await insertRows(env.DB, "cards_all",
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
    stubVectorRecognition(env, async () =>
      Response.json({
        candidates: [{ product_id: 610499, confidence: 84.1 }],
      })
    );

    const response = await recognize(env, token, {
      vector: VECTOR,
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
              retrieval: "pe-core-t16-384-cosine-v1+card-number-ocr",
            }),
            expect.objectContaining({ card_ref: "610499" }),
          ],
        })],
      }),
    }));
  });

  it("recovers an alphanumeric sports printing because card-number disambiguation must not coerce catalog ids to numbers", async () => {
    const env = await createRecognitionEnv();
    await insertRows(env.DB, "cards_all",
      {
        product_id: "610499",
        game_id: 100003,
        game: "Soccer",
        set_name: "Rookie Debut",
        set_code: "RD",
        name: "Alex Rookie",
        rarity: "Rookie",
        product_type_name: "Cards",
        image_url: null,
        number: "14/100",
      },
      {
        product_id: "sports:soccer:rookie-200",
        game_id: 100003,
        game: "Soccer",
        set_name: "Rookie Debut",
        set_code: "RD",
        name: "Alex Rookie",
        rarity: "Rookie Parallel",
        product_type_name: "Cards",
        image_url: null,
        number: "200/200",
      },
    );
    const token = await recognitionToken(env);
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: 610499, confidence: 84.1 }],
    })));

    const response = await recognize(env, token, {
      vector: VECTOR,
      card_number: "200/200",
    });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual(expect.objectContaining({
      data: expect.objectContaining({
        results: [expect.objectContaining({
          candidates: [
            expect.objectContaining({
              product_id: "sports:soccer:rookie-200",
              card_ref: "sports:soccer:rookie-200",
              card_number: "200/200",
              retrieval: "pe-core-t16-384-cosine-v1+card-number-ocr",
            }),
            expect.objectContaining({ card_ref: "610499" }),
          ],
        })],
      }),
    }));
  });

  it("stores no_match when recognition ids are absent from PostgreSQL because an upstream id is not a reviewable card", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: 999, confidence: 77.125 }],
    })));

    const response = await recognize(env, token, { vector: VECTOR });
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
    expect((await readRows(env.DB, "scan_record"))).toEqual([
      expect.objectContaining({
        recognition_status: "no_match",
        candidates: expect.stringContaining('"confidence":77.125'),
      }),
    ]);
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({ status: "released" }),
    ]);
  });

  it("releases Free quota when vector search resolves only an incomplete catalog card because unusable details are not a successful scan", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();
    await insertRows(env.DB, "cards_all", {
      product_id: "incomplete-card",
      game_id: 1,
      game: "Pokemon",
      set_name: null,
      set_code: "TST",
      name: "Recognized Name Only",
      rarity: "Rare",
      product_type_name: "Cards",
      image_url: null,
      number: "001/100",
    });
    const fetchMock = vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: "incomplete-card", confidence: 95 }],
    }));
    stubVectorRecognition(env, fetchMock);

    const first = await recognize(env, token, {
      request_id: requestId,
      vector: VECTOR,
    });
    const firstBody = await first.json();
    const replay = await recognize(env, token, {
      request_id: requestId,
      vector: VECTOR,
    });

    expect(first.status).toBe(200);
    expect(firstBody).toEqual({
      success: true,
      data: expect.objectContaining({
        recognition_status: "failed",
        cards_detected: 0,
        quota: {
          access: "free",
          unlimited: false,
          limit: 10,
          reserved: 0,
          consumed: 0,
          remaining: 10,
        },
        results: [{ index: 1, matched: false, candidates: [] }],
      }),
    });
    expect(await replay.json()).toEqual(firstBody);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({
        request_id: requestId,
        status: "released",
      }),
    ]);
    expect((await readRows(env.DB, "scan_record"))).toEqual([
      expect.objectContaining({ recognition_status: "failed" }),
    ]);
  });

  it("consumes one Free scan for a complete catalog card without price data because price is not required for usable details", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    await insertRows(env.DB, "cards_all", {
      product_id: "complete-card-without-price",
      game_id: 1,
      game: "Pokemon",
      set_name: "Test Set",
      set_code: "TST",
      name: "Complete Card",
      rarity: "Rare",
      product_type_name: "Cards",
      image_url: null,
      number: "002/100",
    });
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: "complete-card-without-price", confidence: 94 }],
    })));

    const response = await recognize(env, token, {
      vector: VECTOR,
    });
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body).toEqual({
      success: true,
      data: expect.objectContaining({
        recognition_status: "success",
        quota: expect.objectContaining({ consumed: 1, remaining: 9 }),
        results: [expect.objectContaining({
          matched: true,
          candidates: [expect.objectContaining({
            card_ref: "complete-card-without-price",
            name: "Complete Card",
            set_name: "Test Set",
            object_type: "tcg",
          })],
        })],
      }),
    });
  });

  it("settles complete and incomplete batch items independently because one bad card must not change another result", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    await insertRows(env.DB, "cards_all",
      {
        product_id: "batch-valid",
        game_id: 1,
        game: "Pokemon",
        set_name: "Batch Set",
        set_code: "BAT",
        name: "Valid Batch Card",
        rarity: "Rare",
        product_type_name: "Cards",
        image_url: null,
        number: "001/100",
      },
      {
        product_id: "batch-invalid",
        game_id: 1,
        game: "Pokemon",
        set_name: null,
        set_code: "BAT",
        name: "Invalid Batch Card",
        rarity: "Rare",
        product_type_name: "Cards",
        image_url: null,
        number: "002/100",
      },
    );
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(Response.json({
        candidates: [{ product_id: "batch-valid", confidence: 96 }],
      }))
      .mockResolvedValueOnce(Response.json({
        candidates: [{ product_id: "batch-invalid", confidence: 93 }],
      }));
    stubVectorRecognition(env, fetchMock);

    const valid = await recognize(env, token, { vector: VECTOR });
    const invalid = await recognize(env, token, { vector: VECTOR });

    expect(await valid.json()).toMatchObject({
      data: {
        recognition_status: "success",
        quota: { consumed: 1, remaining: 9 },
      },
    });
    expect(await invalid.json()).toMatchObject({
      data: {
        recognition_status: "failed",
        quota: { consumed: 1, remaining: 9 },
      },
    });
    expect((await readRows(env.DB, "scan_quota_request")).map((request) => request.status)).toEqual([
      "consumed",
      "released",
    ]);
    expect((await readRows(env.DB, "scan_record")).map((record) => record.recognition_status)).toEqual([
      "success",
      "failed",
    ]);
  });

  it("rejects the eleventh Free scan before R2 and vector search because the server quota is authoritative", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    for (let index = 0; index < 10; index += 1) {
      await insertRows(env.DB, "scan_quota_request", {
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
    stubVectorRecognition(env, fetchMock);

    const response = await recognize(env, token, { vector: VECTOR });

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

  it("replays a completed request because a lost response must not consume quota or vector search twice", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();
    const fetchMock = vi.fn().mockResolvedValue(Response.json({ candidates: [] }));
    stubVectorRecognition(env, fetchMock);

    const first = await recognize(env, token, { request_id: requestId, vector: VECTOR });
    const firstBody = await first.json();
    const second = await recognize(env, token, { request_id: requestId, vector: VECTOR });

    expect(second.status).toBe(200);
    expect(await second.json()).toEqual(firstBody);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({ request_id: requestId, status: "released" }),
    ]);
  });

  it("rejects malformed vectores before calling recognition because protocol errors must not create scan records", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const fetchMock = vi.fn();
    stubVectorRecognition(env, fetchMock);

    const response = await recognize(env, token, { vector: [1, 2, 3] });

    expect(response.status).toBe(422);
    expect(fetchMock).not.toHaveBeenCalled();
    expect((await readRows(env.DB, "scan_record"))).toEqual([]);
  });

  it("stores failed with the raw upstream payload because every valid recognition attempt must remain auditable", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json(
      { error: "internal_error" },
      { status: 500 },
    )));

    const response = await recognize(env, token, { vector: VECTOR });
    const body = await response.json() as { scan_id?: unknown };

    expect(response.status).toBe(502);
    expect(body.scan_id).toEqual(expect.any(String));
    expect((await readRows(env.DB, "scan_record"))).toEqual([
      expect.objectContaining({
        recognition_status: "failed",
        candidates: "[]",
      }),
    ]);
  });

  it("rejects the retired product_ids response as an upstream failure because clients must not silently lose production confidence", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({ product_ids: [10738] })));

    const response = await recognize(env, token, { vector: VECTOR });

    expect(response.status).toBe(502);
    expect((await readRows(env.DB, "scan_record"))[0]?.recognition_status).toBe("failed");
  });

  it("rejects out-of-range upstream confidence because similarity must remain the exact finite 0 to 100 service value", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: 10738, confidence: 100.001 }],
    })));

    const response = await recognize(env, token, { vector: VECTOR });

    expect(response.status).toBe(502);
    expect((await readRows(env.DB, "scan_record"))[0]?.recognition_status).toBe("failed");
  });

  it("deletes the private image when PostgreSQL insert fails because compensation must not leave an orphaned R2 object", async () => {
    const env = await createRecognitionEnv();
    await env.DB.exec("CREATE FUNCTION fail_scan_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test scan insert failure'; END $$; CREATE TRIGGER fail_scan_insert BEFORE INSERT ON scan_record FOR EACH ROW EXECUTE FUNCTION fail_scan_insert();");
    const token = await recognitionToken(env);
    stubVectorRecognition(env, vi.fn().mockResolvedValue(Response.json({ candidates: [] })));

    const response = await recognize(env, token, { vector: VECTOR });

    expect(response.status).toBe(500);
    expect((env.SCAN_IMAGES as unknown as FakeR2).objects.size).toBe(0);
    expect((await readRows(env.DB, "scan_record"))).toEqual([]);
  });

  it("confirms a stored candidate with its purchase price event because Scan additions must reach Collection and Performance", async () => {
    const env = await createTestEnv();
    await insertRows(env.DB, "session", {
      id: "session-1",
      owner_type: "anonymous",
      owner_id: "anon-1",
      expires_at: "2099-01-01T00:00:00.000Z",
      revoked_at: null,
    });
    await insertRows(env.DB, "anonymous_account", { id: "anon-1", upgraded_user_id: null });
    await insertRows(env.DB, "portfolio_folder", { id: "main", owner_type: "anonymous", owner_id: "anon-1" });
    await insertRows(env.DB, "wishlist_item", {
      owner_type: "anonymous",
      owner_id: "anon-1",
      card_ref: "11958",
    });
    await insertRows(env.DB, "scan_record", {
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
    expect((await readRows(env.DB, "collection_item"))).toEqual([
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
    expect((await readRows(env.DB, "collection_item_event"))).toEqual([
      expect.objectContaining({
        item_id: (await readRows(env.DB, "collection_item"))[0]?.id,
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
        purchase_price: 12.5,
        purchase_currency: "USD",
        performance_history_available_from: (await readRows(env.DB, "collection_item"))[0]?.folder_joined_at,
        event_type: "upsert",
        effective_at: (await readRows(env.DB, "collection_item"))[0]?.folder_joined_at,
      }),
    ]);
    expect((await readRows(env.DB, "wishlist_item"))).toEqual([]);
    expect((await readRows(env.DB, "scan_record"))[0]).toEqual(
      expect.objectContaining({
        user_confirmation_status: "confirmed",
        user_result: expect.stringContaining('"added_to_inventory":true'),
      }),
    );
  });

  it("persists Raw review fields because condition-based valuation must survive Scan confirmation", async () => {
    const env = await createConfirmEnv();
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
    expect((await readRows(env.DB, "collection_item"))).toEqual([
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

    const env = await createConfirmEnv();
    const token = await confirmToken(env);
    for (const invalid of invalidBodies) {
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
      expect((await readRows(env.DB, "collection_item"))).toEqual([]);
      expect((await readRows(env.DB, "scan_record"))[0]?.user_confirmation_status).toBe("pending");
    }
  });

  it("rejects foreign folders, non-candidates, and repeated confirmation because Review cannot cross ownership or duplicate items", async () => {
    const env = await createConfirmEnv();
    await insertRows(env.DB, "portfolio_folder", { id: "foreign", owner_type: "user", owner_id: "other" });
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
    expect((await readRows(env.DB, "collection_item"))).toHaveLength(1);
  });

  it("allows the same scanned card, finish, and language when grading differs", async () => {
    const env = await createConfirmEnv();
    await insertRows(env.DB, "collection_item", {
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

    expect(response.status).toBe(201);
    expect((await readRows(env.DB, "collection_item"))).toHaveLength(2);
    expect((await readRows(env.DB, "scan_record"))[0]?.user_confirmation_status).toBe("confirmed");
  });
});


async function createTestEnv(): Promise<TestEnvWithPostgres> {
  const db = await PGliteDatabase.create();
  databases.push(db);
  for (const name of ["0000_business_schema", "0001_price_domain", "0006_mutation_lock", "0008_collection_item_grading_identity", "0010_scan_record_environment"]) {
    await db.exec(readFileSync(new URL('../db/postgres/migrations/' + name + '.sql', import.meta.url), 'utf8'));
  }
  const queries: string[] = [];
  const prepare = db.prepare.bind(db);
  vi.spyOn(db, "prepare").mockImplementation((sql) => { queries.push(sql.replace(/\s+/g, " ").trim()); return prepare(sql); });
  return { DB: db, queries, CACHE_KV: {} as KVNamespace, JWT_SECRET: "test-secret",
    VECTOR_RECOGNITION: { fetch: vi.fn() } as unknown as Fetcher, SCAN_IMAGES: new FakeR2() as unknown as R2Bucket,
    APP_ENVIRONMENT: "development", APPLE_IAP_PRODUCT_IDS: "yearly" };
}

async function insertRows(db: PGliteDatabase, table: string, ...values: Record<string, unknown>[]) {
  const now = new Date().toISOString();
  const defaults: Record<string, Record<string, unknown>> = {
    session: { refresh_token: crypto.randomUUID(), created_at: now },
    anonymous_account: { device_id: crypto.randomUUID(), created_at: now },
    portfolio_folder: { name: crypto.randomUUID(), created_at: now, updated_at: now },
    scan_record: { filename: "scan.jpg", platform: "iOS", app_version: "1.0.0", raw_response: "{}", created_at: now },
    scan_quota_request: { created_at: now, updated_at: now },
    collection_item: { created_at: now, updated_at: now },
    wishlist_item: { id: crypto.randomUUID(), created_at: now },
  };
  for (const value of values) {
    const row = { ...defaults[table], ...value };
    // Production derives card image URLs; they are not a cards_all column.
    if (table === "cards_all") delete row.image_url;
    const columns = Object.keys(row);
    await db.prepare('INSERT INTO ' + table + ' (' + columns.join(', ') + ') VALUES (' + columns.map(() => '?').join(', ') + ')')
      .bind(...Object.values(row)).run();
  }
}

async function readRows(db: PGliteDatabase, table: string): Promise<Record<string, any>[]> {
  return (await db.query<Record<string, any>>('SELECT * FROM ' + table + ' ORDER BY ctid')).rows;
}

async function grantPremium(db: PGliteDatabase) {
  await db.exec(`
    INSERT INTO billing_purchase_chain (id, store, environment, original_transaction_id, product_id, entitlement_id,
      original_owner_type, original_owner_id, status, created_at, updated_at)
    VALUES ('scan-premium-chain', 'apple', 'Sandbox', 'scan-original', 'yearly', 'performance_pro', 'anonymous', 'anon-1', 'LIFETIME', '2026-09-08', '2026-09-08');
    INSERT INTO billing_session_entitlement_grant (id, session_id, purchase_chain_id, entitlement_id, source, status, granted_at, last_verified_at, updated_at)
    VALUES ('scan-premium-grant', 'session-1', 'scan-premium-chain', 'performance_pro', 'verified', 'active', '2026-09-08', '2026-09-08', '2026-09-08');
  `);
}
async function createRecognitionEnv(): Promise<TestEnvWithPostgres> {
  const env = await createTestEnv();
  await insertRows(env.DB, "session", {
    id: "session-1",
    owner_type: "anonymous",
    owner_id: "anon-1",
    expires_at: "2099-01-01T00:00:00.000Z",
    revoked_at: null,
  });

  await insertRows(env.DB, "anonymous_account", { id: "anon-1", upgraded_user_id: null });
  return env;
}

function recognitionToken(env: TestEnvWithPostgres): Promise<string> {
  return signAccessToken(
    { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
    env.JWT_SECRET,
  );
}

async function recognize(
  env: TestEnvWithPostgres,
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
    if (value !== undefined && value !== null) form.set(key, key === "vector" ? JSON.stringify(value) : String(value));
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

async function createConfirmEnv(): Promise<TestEnvWithPostgres> {
  const env = await createTestEnv();
  await insertRows(env.DB, "session", {
    id: "session-1",
    owner_type: "anonymous",
    owner_id: "anon-1",
    expires_at: "2099-01-01T00:00:00.000Z",
    revoked_at: null,
  });
  await insertRows(env.DB, "anonymous_account", { id: "anon-1", upgraded_user_id: null });
  await insertRows(env.DB, "portfolio_folder", { id: "main", owner_type: "anonymous", owner_id: "anon-1" });
  await insertRows(env.DB, "scan_record", {
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

function confirmToken(env: TestEnvWithPostgres): Promise<string> {
  return signAccessToken(
    { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
    env.JWT_SECRET,
  );
}

async function confirmScan(
  env: TestEnvWithPostgres,
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

function stubVectorRecognition(env: TestEnvWithPostgres, handler: (...args: any[]) => Promise<Response>): void {
  env.VECTOR_RECOGNITION = { fetch: handler } as unknown as Fetcher;
}
