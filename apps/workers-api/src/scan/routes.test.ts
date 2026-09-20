import { signAccessToken } from "@kando/auth-core";
import { readFileSync } from "node:fs";
import { URL } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import app, { type Env as AppEnv } from "../index";
import { PGliteDatabase } from "../test-support/pglite-database";
import { createHttpVectorRecognition } from "../linux/vector-recognition";

type TestEnvWithPostgres = Omit<AppEnv, "DB"> & { DB: PGliteDatabase; queries: string[]; VECTOR_RECOGNITION?: Fetcher };
const HASHES = { r: "A".repeat(43), g: "B".repeat(43), b: "C".repeat(43) };
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
  it("rejects missing and malformed RGB hashes before storage or quota consumption", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const upstream = vi.fn();
    stubPhashRecognition(env, upstream);
    for (const body of [
      { vector: [1, 2, 3] },
      { ...HASHES, r: "short" },
      { ...HASHES, g: "A".repeat(44) },
      { ...HASHES, b: "!".repeat(43) },
      { r: HASHES.r, g: HASHES.g },
    ]) {
      expect((await recognize(env, token, body)).status).toBe(422);
    }
    expect(upstream).not.toHaveBeenCalled();
    expect(await readRows(env.DB, "scan_record")).toEqual([]);
    expect(await readRows(env.DB, "scan_quota_request")).toEqual([]);
    expect((env.SCAN_IMAGES as unknown as FakeR2).objects.size).toBe(0);
  });

  it("passes game_id to pHash retrieval and still filters the local catalog", async () => {
    const env = await createRecognitionEnv();
    await insertRows(env.DB, "cards_all",
      { product_id: "same-game", game_id: 1, game: "Pokemon", name: "Wanted Card", set_name: "Set A", product_type_name: "Cards" },
      { product_id: "other-game", game_id: 2, game: "Magic", name: "Other Card", set_name: "Set B", product_type_name: "Cards" },
    );
    const upstream = vi.fn(async (_url, init) => {
      expect(JSON.parse(init.body)).toEqual({ ...HASHES, game_id: 1 });
      return Response.json({ candidates: [{ product_id: "other-game", confidence: 99 }, { product_id: "same-game", confidence: 90 }] });
    });
    stubPhashRecognition(env, upstream);
    const response = await recognize(env, await recognitionToken(env), { ...HASHES, game_id: 1 });
    expect(response.status).toBe(200);
    const body = await response.json() as { data: { results: Array<{ candidates: Array<{ card_ref: string }> }> } };
    expect(body.data.results[0].candidates.map((candidate) => candidate.card_ref)).toEqual(["same-game"]);
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    await Promise.all(databases.splice(0).map((db) => db.close()));
  });

  it("keeps Linux catalog, records and quota local while sending only hashes and game_id upstream", async () => {
    const env = await createRecognitionEnv();
    await insertRows(env.DB, "cards_all", {
      product_id: "linux-card",
      game_id: 1,
      game: "Pokemon",
      name: "Card from the Linux catalog",
      set_name: "Local Set",
      product_type_name: "Cards",
    });
    const upstream = vi.fn().mockResolvedValue(Response.json({
      candidates: [
        { product_id: "cloud-only-card", confidence: 99 },
        { product_id: "linux-card", confidence: 92.125 },
      ],
    }));
    vi.stubGlobal("fetch", upstream);
    env.VECTOR_RECOGNITION = createHttpVectorRecognition("https://recognize.tcgcard.fun");
    const requestId = crypto.randomUUID();

    const response = await recognize(env, await recognitionToken(env), {
      request_id: requestId, ...HASHES, game_id: 1, platform: "iOS",
    });

    expect(upstream).toHaveBeenCalledExactlyOnceWith(
      "https://recognize.tcgcard.fun/recognize",
      expect.objectContaining({
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify({ ...HASHES, game_id: 1 }),
      }),
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      data: {
        recognition_status: "success",
        quota: { reserved: 0, consumed: 1, remaining: 9 },
        results: [{ candidates: [{ card_ref: "linux-card", name: "Card from the Linux catalog" }] }],
      },
    });
    expect(await readRows(env.DB, "scan_record")).toEqual([
      expect.objectContaining({ id: requestId, environment: "development", recognition_status: "success" }),
    ]);
    expect(await readRows(env.DB, "scan_quota_request")).toEqual([
      expect.objectContaining({ request_id: requestId, status: "consumed" }),
    ]);
    expect((env.SCAN_IMAGES as unknown as FakeR2).objects.size).toBe(1);
  });

  it.each([
    { scenario: "no candidates", candidates: [] },
    { scenario: "a candidate missing from the local catalog", candidates: [{ product_id: "cloud-only-card", confidence: 95 }] },
  ])("releases Linux Free quota for $scenario because a CF response alone is not a usable local match", async ({ candidates }) => {
    const env = await createRecognitionEnv();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json({ candidates })));
    env.VECTOR_RECOGNITION = createHttpVectorRecognition("https://recognize.tcgcard.fun");

    const response = await recognize(env, await recognitionToken(env), { ...HASHES });

    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      data: { recognition_status: "no_match", quota: { reserved: 0, consumed: 0, remaining: 10 } },
    });
    expect(await readRows(env.DB, "scan_quota_request")).toEqual([
      expect.objectContaining({ status: "released" }),
    ]);
    expect(await readRows(env.DB, "scan_record")).toEqual([
      expect.objectContaining({ recognition_status: "no_match" }),
    ]);
  });

  it.each([
    { failure: "an HTTP failure", response: () => Response.json({ error: "unavailable" }, { status: 503 }) },
    { failure: "an invalid JSON response", response: () => new Response("invalid JSON") },
  ])("releases Linux Free quota and records $failure because transport failures must not consume scans", async ({ response: upstreamResponse }) => {
    const env = await createRecognitionEnv();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(upstreamResponse()));
    env.VECTOR_RECOGNITION = createHttpVectorRecognition("https://recognize.tcgcard.fun");

    const response = await recognize(env, await recognitionToken(env), { ...HASHES });

    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({ error: { code: "VECTOR_RECOGNITION_UNAVAILABLE" } });
    expect(await readRows(env.DB, "scan_quota_request")).toEqual([
      expect.objectContaining({ status: "released" }),
    ]);
    expect(await readRows(env.DB, "scan_record")).toEqual([
      expect.objectContaining({ recognition_status: "failed" }),
    ]);
  });

  it("releases a queued Linux reservation after the HTTP deadline because a slow CF service must not retain Free quota", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();
    const reservation = await app.request("/api/v1/scan/quota/reserve", {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "Idempotency-Key": requestId },
      body: JSON.stringify({ request_id: requestId }),
    }, env);
    expect(reservation.status).toBe(200);
    let abortReason: unknown;
    const upstream = vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => {
        abortReason = init.signal!.reason;
        reject(abortReason);
      }, { once: true });
    }));
    vi.stubGlobal("fetch", upstream);
    env.VECTOR_RECOGNITION = createHttpVectorRecognition("https://recognize.tcgcard.fun", 20);

    const response = await recognize(env, token, { request_id: requestId, ...HASHES });

    expect(abortReason).toMatchObject({ name: "TimeoutError" });
    expect(upstream).toHaveBeenCalledOnce();
    expect(response.status).toBe(502);
    expect(await readRows(env.DB, "scan_quota_request")).toEqual([
      expect.objectContaining({ request_id: requestId, status: "released" }),
    ]);
    expect(await readRows(env.DB, "scan_record")).toEqual([
      expect.objectContaining({ id: requestId, recognition_status: "failed" }),
    ]);
  });

  it("resolves pHash product ids through PostgreSQL and stores an audit record because App scans must be reviewable", async () => {
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

    stubPhashRecognition(env, async (url: string, init: RequestInit) => {
      expect(url).toBe("https://recognize.tcgcard.fun/recognize");
      expect(init.method).toBe("POST");
      expect(init.headers).toEqual({
        Accept: "application/json",
        "Content-Type": "application/json",
      });
      expect(JSON.parse(String(init.body))).toEqual(HASHES);
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
          ...HASHES, filename: "scan.jpg",
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
                retrieval: "rgb-phash-16-v1",
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
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [
        { product_id: "sports:soccer:rookie-001", confidence: 91.25 },
      ],
    })));

    const response = await recognize(env, token, { ...HASHES });
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
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: recognized,
    })));

    const response = await recognize(
      env,
      await recognitionToken(env),
      { ...HASHES },
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
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({ candidates: [] })));

    const response = await recognize(env, token, { ...HASHES });
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

    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({ candidates: [] })));
    const response = await recognize(env, token, {
      request_id: requestId,
      ...HASHES,
    });
    expect(response.status).toBe(200);
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({ status: "released" }),
    ]);
  });

  it("inserts a new queued reservation before lookup because the common reserve path must avoid an empty read", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();

    const response = await app.request(
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

    expect(response.status).toBe(200);
    expect(env.queries.filter((sql) =>
      sql.includes("FROM scan_quota_request WHERE request_id = ?")
    )).toHaveLength(0);

    const replay = await app.request(
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
    expect(replay.status).toBe(200);
    expect(await replay.json()).toMatchObject({
      data: { request_id: requestId, quota: { reserved: 1, remaining: 9 } },
    });
    expect(await readRows(env.DB, "scan_quota_request")).toHaveLength(1);
  });

  it("starts independent quota and Premium reads together because a quota refresh must not add their database waits", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const originalQuery = env.DB.query.bind(env.DB);
    let releaseGrant!: () => void;
    let grantStarted!: () => void;
    let quotaStarted = false;
    const grantGate = new Promise<void>((resolve) => { releaseGrant = resolve; });
    const started = new Promise<void>((resolve) => { grantStarted = resolve; });
    vi.spyOn(env.DB, "query").mockImplementation(async (sql, values) => {
      if (sql.includes("FROM billing_session_entitlement_grant AS grant_record")) {
        grantStarted();
        await grantGate;
      }
      if (sql.includes("AS reserved_count")) quotaStarted = true;
      return originalQuery(sql, values);
    });

    const responsePromise = app.request(
      "/api/v1/scan/quota",
      { headers: { Authorization: `Bearer ${token}` } },
      env,
    );
    await started;
    try {
      expect(quotaStarted).toBe(true);
    } finally {
      releaseGrant();
      const response = await responsePromise;
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({
        data: { access: "free", reserved: 0, consumed: 0, remaining: 10 },
      });
    }
  });

  it("filters non-billable quota history in SQL because released and Premium audits must not slow lifetime quota reads", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);

    const response = await app.request(
      "/api/v1/scan/quota",
      { headers: { Authorization: `Bearer ${token}` } },
      env,
    );

    expect(response.status).toBe(200);
    const quotaSql = env.queries.find((sql) => sql.includes("AS reserved_count"));
    expect(quotaSql?.replace(/\s+/g, " ")).toContain(
      "WHERE owner_type = ? AND owner_id = ? AND access_mode = 'free' AND status IN ('reserved', 'consumed')",
    );
  });

  it("settles a processed scan without re-reading its reservation because success must not add a database wait", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    stubPhashRecognition(
      env,
      vi.fn().mockResolvedValue(Response.json({ candidates: [] })),
    );

    const response = await recognize(env, token, { ...HASHES });

    expect(response.status).toBe(200);
    const requestLookups = env.queries.filter((sql) =>
      sql.includes("FROM scan_quota_request WHERE request_id = ?")
    );
    expect(requestLookups).toHaveLength(1);
  });

  it("keeps entitlement sync required ahead of quota reads because a verified client must receive the original 409", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);

    const response = await app.request(
      "/api/v1/scan/quota",
      {
        headers: {
          Authorization: `Bearer ${token}`,
          "X-Local-Premium-State": "verified",
        },
      },
      env,
    );

    expect(response.status).toBe(409);
    expect(env.queries.some((sql) => sql.includes("AS reserved_count"))).toBe(false);
  });

  it("reports only stage durations for slow recognition because production timing must locate waits without exposing scan data", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const requestId = crypto.randomUUID();
    stubPhashRecognition(env, vi.fn().mockImplementation(async () => Response.json({ candidates: [] })));
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});
    let clock = 0;
    const timing = vi.spyOn(performance, "now").mockImplementation(() => clock += 500);
    try {
      const response = await recognize(env, token, { request_id: requestId, ...HASHES });
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({ data: { recognition_status: "no_match" } });
      const entry = logs.mock.calls.find(([name]) => name === "scan_recognize_timing");
      expect(entry).toBeDefined();
      const payload = JSON.parse(String(entry![1])) as Record<string, unknown>;
      expect(payload).toMatchObject({ outcome: "no_match" });
      expect(Object.keys(payload).sort()).toEqual([
        "audit_ms", "auth_ms", "catalog_ms", "image_ms", "outcome",
        "preflight_ms", "recognition_ms", "settlement_ms", "total_ms",
      ]);
      expect(JSON.stringify(payload)).not.toContain(requestId);
      expect(JSON.stringify(payload)).not.toContain("anon-1");
      expect(Object.entries(payload).filter(([key]) => key.endsWith("_ms"))
        .every(([, value]) => typeof value === "number" && value >= 0)).toBe(true);

      clock = 0;
      timing.mockImplementation(() => clock += 1);
      logs.mockClear();
      expect((await recognize(env, token, { ...HASHES })).status).toBe(200);
      expect(logs.mock.calls.some(([name]) => name === "scan_recognize_timing")).toBe(false);

      clock = 0;
      timing.mockImplementation(() => clock += 40);
      logs.mockClear();
      expect((await recognize(env, token, { ...HASHES })).status).toBe(200);
      const thresholdEntry = logs.mock.calls.find(
        ([name]) => name === "scan_recognize_timing",
      );
      expect(thresholdEntry).toBeDefined();
      const thresholdPayload = JSON.parse(String(thresholdEntry?.[1])) as {
        total_ms: number;
      };
      expect(thresholdPayload.total_ms).toBeGreaterThanOrEqual(1000);
      expect(thresholdPayload.total_ms).toBeLessThan(3000);

      clock = 0;
      timing.mockImplementation(() => clock += 500);
      logs.mockClear();
      stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({ error: "upstream" }, { status: 503 })));
      expect((await recognize(env, token, { ...HASHES })).status).toBe(502);
      const failure = logs.mock.calls.find(([name]) => name === "scan_recognize_timing");
      expect(JSON.parse(String(failure?.[1]))).toMatchObject({ outcome: "failed" });
      expect(String(failure?.[1])).not.toContain("upstream");
    } finally {
      timing.mockRestore();
      logs.mockRestore();
    }
  });

  it("releases a queued reservation when recognition cannot start because an unavailable service must not hold Free quota", async () => {
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
      ...HASHES,
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
      ...HASHES,
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
    stubPhashRecognition(env, async (_url: string, init: RequestInit) => {
      expect(JSON.parse(String(init.body))).toEqual({ ...HASHES });
      return Response.json({
        candidates: [
          { product_id: 610499, confidence: 84.1 },
          { product_id: 602664, confidence: 83.854 },
        ],
      });
    });

    const response = await recognize(env, token, {
      ...HASHES,
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
    stubPhashRecognition(env, async () =>
      Response.json({
        candidates: [{ product_id: 610499, confidence: 84.1 }],
      })
    );

    const response = await recognize(env, token, {
      ...HASHES,
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
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: 610499, confidence: 84.1 }],
    })));

    const response = await recognize(env, token, {
      ...HASHES,
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
              retrieval: "rgb-phash-16-v1+card-number-ocr",
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
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: 999, confidence: 77.125 }],
    })));

    const response = await recognize(env, token, { ...HASHES });
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
    stubPhashRecognition(env, fetchMock);

    const first = await recognize(env, token, {
      request_id: requestId,
      ...HASHES,
    });
    const firstBody = await first.json();
    const replay = await recognize(env, token, {
      request_id: requestId,
      ...HASHES,
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
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: "complete-card-without-price", confidence: 94 }],
    })));

    const response = await recognize(env, token, {
      ...HASHES,
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
    stubPhashRecognition(env, fetchMock);

    const valid = await recognize(env, token, { ...HASHES });
    const invalid = await recognize(env, token, { ...HASHES });

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
    stubPhashRecognition(env, fetchMock);

    const response = await recognize(env, token, { ...HASHES });

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
    stubPhashRecognition(env, fetchMock);

    const first = await recognize(env, token, { request_id: requestId, ...HASHES });
    const firstBody = await first.json();
    const second = await recognize(env, token, { request_id: requestId, ...HASHES });

    expect(second.status).toBe(200);
    expect(await second.json()).toEqual(firstBody);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect((await readRows(env.DB, "scan_quota_request"))).toEqual([
      expect.objectContaining({ request_id: requestId, status: "released" }),
    ]);
  });

  it("rejects malformed hashes before calling recognition because protocol errors must not create scan records", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    const fetchMock = vi.fn();
    stubPhashRecognition(env, fetchMock);

    const response = await recognize(env, token, { ...HASHES, r: "invalid" });

    expect(response.status).toBe(422);
    expect(fetchMock).not.toHaveBeenCalled();
    expect((await readRows(env.DB, "scan_record"))).toEqual([]);
  });

  it("stores failed with the raw upstream payload because every valid recognition attempt must remain auditable", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json(
      { error: "internal_error" },
      { status: 500 },
    )));

    const response = await recognize(env, token, { ...HASHES });
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
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({ product_ids: [10738] })));

    const response = await recognize(env, token, { ...HASHES });

    expect(response.status).toBe(502);
    expect((await readRows(env.DB, "scan_record"))[0]?.recognition_status).toBe("failed");
  });

  it("rejects out-of-range upstream confidence because similarity must remain the exact finite 0 to 100 service value", async () => {
    const env = await createRecognitionEnv();
    const token = await recognitionToken(env);
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({
      candidates: [{ product_id: 10738, confidence: 100.001 }],
    })));

    const response = await recognize(env, token, { ...HASHES });

    expect(response.status).toBe(502);
    expect((await readRows(env.DB, "scan_record"))[0]?.recognition_status).toBe("failed");
  });

  it("deletes the private image when PostgreSQL insert fails because compensation must not leave an orphaned R2 object", async () => {
    const env = await createRecognitionEnv();
    await env.DB.exec("CREATE FUNCTION fail_scan_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test scan insert failure'; END $$; CREATE TRIGGER fail_scan_insert BEFORE INSERT ON scan_record FOR EACH ROW EXECUTE FUNCTION fail_scan_insert();");
    const token = await recognitionToken(env);
    stubPhashRecognition(env, vi.fn().mockResolvedValue(Response.json({ candidates: [] })));

    const response = await recognize(env, token, { ...HASHES });

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

function stubPhashRecognition(env: TestEnvWithPostgres, handler: (...args: any[]) => Promise<Response>): void {
  env.VECTOR_RECOGNITION = { fetch: handler } as unknown as Fetcher;
}
