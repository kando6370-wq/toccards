import { Hono } from "hono";
import { collectionItemDraftFromBody } from "../collection-item";
import type { CardSearchResult, DataSourceAdapter } from "../data-source/adapter";
import { createLocalDbDataSourceAdapter } from "../data-source/local-db-adapter";
import {
  mutationLockKey,
  ownerCardMutationLockKey,
  runWithMutationLocks,
} from "../db/mutation-lock";
import type { Env } from "../env";
import { createId } from "../id";
import { authenticateOwner } from "../owner-auth";
import {
  LOCAL_PREMIUM_STATE_HEADER,
  resolvePremiumAccess,
} from "../entitlements/premium-access";
import {
  loadScanQuota,
  reserveScanQuota,
  settleScanQuota,
  type ScanQuotaSnapshot,
} from "./quota";
import { validateScanImage, type ValidatedScanImage } from "./scan-image";

type ScanBindings = { Bindings: Env };

type ScanCandidate = {
  rank: number;
  product_id: number;
  card_ref: string;
  catalog_matched: boolean;
  game: string | null;
  name: string | null;
  set_code: string | null;
  card_number: string | null;
  rarity: string | null;
  confidence: number | null;
  retrieval: string | null;
  distance: number | null;
};

type RecognitionCandidate = { productId: number; confidence: number };

type ScanResult = {
  index: number;
  matched: boolean;
  candidates: ScanCandidate[];
};

type ScanRecordRow = {
  id: string;
  candidates: string;
  user_confirmation_status: string;
};

type PortfolioFolderRow = { id: string };

const UNAUTHORIZED_RESPONSE = {
  success: false,
  error: { code: "UNAUTHORIZED", message: "Unauthorized." },
} as const;

const VALIDATION_ERROR_RESPONSE = {
  success: false,
  error: { code: "VALIDATION_ERROR", message: "Invalid request." },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const OCR_UNAVAILABLE_RESPONSE = {
  success: false,
  error: {
    code: "OCR_SERVICE_UNAVAILABLE",
    message: "Recognition service is unavailable.",
  },
} as const;

const NOT_FOUND_RESPONSE = {
  success: false,
  error: { code: "NOT_FOUND", message: "Not found." },
} as const;

const CONFLICT_RESPONSE = {
  success: false,
  error: { code: "CONFLICT", message: "Scan is already confirmed." },
} as const;

const DUPLICATE_COLLECTION_ITEM_RESPONSE = {
  success: false,
  error: {
    code: "DUPLICATE_COLLECTION_ITEM",
    message: "This card with the same finish and language is already in this portfolio.",
  },
} as const;

const ENTITLEMENT_SYNC_REQUIRED_RESPONSE = {
  success: false,
  error: {
    code: "ENTITLEMENT_SYNC_REQUIRED",
    message: "Premium access is still syncing.",
  },
} as const;

const SCAN_QUOTA_EXHAUSTED_RESPONSE = {
  success: false,
  error: { code: "SCAN_QUOTA_EXHAUSTED", message: "No free scans remaining." },
} as const;

const SCAN_REQUEST_CONFLICT_RESPONSE = {
  success: false,
  error: { code: "SCAN_REQUEST_CONFLICT", message: "Scan request was already processed." },
} as const;

const INSERT_SCAN_RECORD_SQL = `
INSERT INTO scan_record
  (id, owner_type, owner_id, image_url, filename, platform, app_version,
   device_model, os_version, recognition_status, user_confirmation_status,
   system_result, user_result, candidates, raw_response, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
`;

const SELECT_SCAN_RECORD_SQL = `
SELECT id, candidates, user_confirmation_status
FROM scan_record
WHERE id = ? AND owner_type = ? AND owner_id = ?
LIMIT 1
`;

const SELECT_PORTFOLIO_FOLDER_SQL = `
SELECT id
FROM portfolio_folder
WHERE id = ? AND owner_type = ? AND owner_id = ?
LIMIT 1
`;

const INSERT_CONFIRMED_COLLECTION_ITEM_SQL = `
INSERT INTO collection_item
  (id, owner_type, owner_id, folder_id, card_ref, object_type, grader, condition,
   grade, language, finish, quantity, purchase_price, purchase_currency, notes,
   folder_joined_at, created_at, updated_at)
SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
WHERE EXISTS (
  SELECT 1 FROM scan_record
  WHERE id = ? AND owner_type = ? AND owner_id = ?
    AND user_confirmation_status = 'pending'
)
`;

const SELECT_COLLECTION_ITEM_BY_SKU_SQL = `
SELECT id
FROM collection_item
WHERE owner_type = ? AND owner_id = ? AND folder_id = ? AND card_ref = ?
  AND language IS NOT DISTINCT FROM ? AND finish IS NOT DISTINCT FROM ?
LIMIT 1
`;

const INSERT_CONFIRMED_COLLECTION_ITEM_EVENT_SQL = `
INSERT INTO collection_item_event
  (id, item_id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
   condition, grade, language, finish, quantity, event_type, effective_at)
SELECT ?, id, owner_type, owner_id, folder_id, card_ref, object_type, grader,
  condition, grade, language, finish, quantity, 'upsert', ?
FROM collection_item
WHERE id = ? AND owner_type = ? AND owner_id = ?
LIMIT 1
`;

const DELETE_CONFIRMED_WISHLIST_CARD_SQL = `
DELETE FROM wishlist_item
WHERE owner_type = ? AND owner_id = ? AND card_ref = ?
  AND EXISTS (
    SELECT 1 FROM collection_item
    WHERE id = ? AND owner_type = ? AND owner_id = ?
  )
`;

const UPDATE_SCAN_CONFIRMATION_SQL = `
UPDATE scan_record
SET user_confirmation_status = 'confirmed', modified_result = ?, user_result = ?
WHERE id = ? AND owner_type = ? AND owner_id = ?
  AND user_confirmation_status = 'pending'
`;

const PHASH_PATTERN = /^[A-Za-z0-9_-]{43}$/;
const CARD_NUMBER_PATTERN = /^(?:\d{1,4}\/(?:\d{1,4}|[A-Z]{1,5}-P)|[A-Z]{1,5}-P)$/;

function scanQuotaPayload(
  quota: ScanQuotaSnapshot,
  access: "free" | "premium",
) {
  return {
    access,
    unlimited: access === "premium",
    ...quota,
  };
}

export function createScanRoutes() {
  const routes = new Hono<ScanBindings>();

  routes.get("/scan/quota", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "unauthorized") return c.json(UNAUTHORIZED_RESPONSE, 401);
    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    const access = await resolvePremiumAccess(
      c.env,
      auth.owner.session_id,
      c.req.header(LOCAL_PREMIUM_STATE_HEADER),
    );
    if (access === "sync_required") {
      return c.json(ENTITLEMENT_SYNC_REQUIRED_RESPONSE, 409);
    }
    const quota = await loadScanQuota(c.env.DB, auth.owner);
    return c.json({
      success: true,
      data: scanQuotaPayload(quota, access),
    });
  });

  routes.post("/scan/recognize", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "unauthorized") return c.json(UNAUTHORIZED_RESPONSE, 401);
    if (auth.status === "internal_error") return c.json(INTERNAL_ERROR_RESPONSE, 500);

    const serviceBaseUrl = normalizeBaseUrl(c.env.OCR_SERVICE_BASE_URL);
    if (!serviceBaseUrl) return c.json(OCR_UNAVAILABLE_RESPONSE, 503);
    const imageBucket = c.env.SCAN_IMAGES;
    if (!imageBucket) return c.json(INTERNAL_ERROR_RESPONSE, 503);

    const body = await readFormData(c.req);
    if (!body) return c.json(VALIDATION_ERROR_RESPONSE, 422);
    const requestId = readUuid(body.get("request_id"));
    if (!requestId || c.req.header("Idempotency-Key") !== requestId) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }
    const r = readPhash(body.get("r"));
    const g = readPhash(body.get("g"));
    const b = readPhash(body.get("b"));
    const gameId = readOptionalGameId(body.get("game_id"));
    const cardNumber = readOptionalCardNumber(body.get("card_number"));
    const image = await validateScanImage(body.get("image"));
    if (!r || !g || !b || gameId === null || cardNumber === null || !image) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const access = await resolvePremiumAccess(
      c.env,
      auth.owner.session_id,
      c.req.header(LOCAL_PREMIUM_STATE_HEADER),
    );
    if (access === "sync_required") {
      return c.json(ENTITLEMENT_SYNC_REQUIRED_RESPONSE, 409);
    }
    const reservation = await reserveScanQuota(
      c.env.DB,
      auth.owner,
      requestId,
      access,
    );
    if (reservation.status === "exhausted") {
      return c.json({
        ...SCAN_QUOTA_EXHAUSTED_RESPONSE,
        quota: scanQuotaPayload(reservation.quota, "free"),
      }, 403);
    }
    if (reservation.status === "existing" && reservation.response !== null) {
      return new Response(JSON.stringify(reservation.response.body), {
        status: reservation.response.status,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (reservation.status === "conflict" || reservation.status === "existing") {
      return c.json(SCAN_REQUEST_CONFLICT_RESPONSE, 409);
    }

    const outbound = {
      r,
      g,
      b,
      ...(gameId === undefined ? {} : { game_id: gameId }),
    };

    const scanId = requestId;
    const createdAt = new Date();
    const imageKey = scanImageKey(
      auth.owner.owner_type,
      auth.owner.owner_id,
      scanId,
      image,
      createdAt,
    );
    try {
      await imageBucket.put(imageKey, image.bytes, {
        httpMetadata: { contentType: image.contentType },
        customMetadata: {
          scanId,
          ownerType: auth.owner.owner_type,
          ownerId: auth.owner.owner_id,
        },
      });
    } catch (error) {
      console.error("Failed to store scan image.", error);
      await settleScanQuota(c.env.DB, auth.owner, requestId, "released", null, {
        body: INTERNAL_ERROR_RESPONSE,
        status: 500,
      });
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    let ocrPayload: unknown = null;
    let upstreamFailed = false;
    const startedAt = Date.now();
    try {
      const response = await fetch(`${serviceBaseUrl}/recognize`, {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify(outbound),
      });
      ocrPayload = await response.json().catch(() => null);
      upstreamFailed = !response.ok;
    } catch (error) {
      upstreamFailed = true;
      ocrPayload = { error: "upstream_request_failed", message: String(error) };
    }

    const payload = isRecord(ocrPayload) ? ocrPayload : {};
    const recognized = upstreamFailed ? null : readRecognitionCandidates(payload.candidates);
    if (!recognized) upstreamFailed = true;
    const adapter = createLocalDbDataSourceAdapter(c.env.DB);
    let candidates: ScanCandidate[] = [];
    let auditCandidates: ScanCandidate[] = [];
    if (!upstreamFailed && recognized) {
      try {
        auditCandidates = await Promise.all(
          recognized.map(async (candidate, index) => {
            const card = await adapter.getCard(String(candidate.productId));
            return card
              ? toCatalogCandidate(card, candidate, index)
              : toUnresolvedCandidate(candidate, index);
          }),
        );
        auditCandidates = await disambiguateByCardNumber(
          auditCandidates,
          cardNumber,
          adapter,
        );
        candidates = auditCandidates.filter((candidate) => candidate.catalog_matched);
      } catch (error) {
        console.error("Failed to resolve recognition candidates.", error);
        upstreamFailed = true;
        candidates = [];
        auditCandidates = [];
      }
    }
    const results: ScanResult[] = [
      { index: 1, matched: candidates.length > 0, candidates },
    ];

    const recognitionStatus = upstreamFailed
      ? "failed"
      : candidates.length > 0 ? "success" : "no_match";
    const systemResult = buildSystemResult(
      recognitionStatus,
      candidates[0] ?? null,
      auditCandidates.length,
    );
    const userResult = {
      confirmation_status: "pending",
      final_card: null,
      modified_result: false,
      added_to_inventory: false,
      added_to_wishlist: false,
    };

    try {
      await c.env.DB.prepare(INSERT_SCAN_RECORD_SQL)
        .bind(
          scanId,
          auth.owner.owner_type,
          auth.owner.owner_id,
          imageKey,
          readString(body.get("filename")) ?? `scan.${image.extension}`,
          readString(body.get("platform")) ?? "unknown",
          readString(body.get("app_version")) ?? "unknown",
          readString(body.get("device_model")),
          readString(body.get("os_version")),
          recognitionStatus,
          "pending",
          JSON.stringify({
            ...systemResult,
            image: {
              mime_type: image.contentType,
              byte_size: image.bytes.byteLength,
              width: image.width,
              height: image.height,
            },
          }),
          JSON.stringify(userResult),
          JSON.stringify(auditCandidates),
          JSON.stringify(ocrPayload),
          createdAt.toISOString(),
        )
        .run();
    } catch (error) {
      console.error("Failed to persist scan audit record.", error);
      await deleteUploadedImage(imageBucket, imageKey);
      await settleScanQuota(c.env.DB, auth.owner, requestId, "released", null, {
        body: INTERNAL_ERROR_RESPONSE,
        status: 500,
      });
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (upstreamFailed) {
      const responseBody = { ...OCR_UNAVAILABLE_RESPONSE, scan_id: scanId };
      await settleScanQuota(c.env.DB, auth.owner, requestId, "released", scanId, {
        body: responseBody,
        status: 502,
      });
      return c.json(responseBody, 502);
    }

    const quota = reservation.accessMode === "free"
      ? {
          ...reservation.quota,
          reserved: Math.max(0, reservation.quota.reserved - 1),
          consumed: reservation.quota.consumed + 1,
        }
      : reservation.quota;
    const responseBody = {
      success: true,
      data: {
        scan_id: scanId,
        recognition_status: recognitionStatus,
        cards_detected: candidates.length > 0 ? 1 : 0,
        elapsed: (Date.now() - startedAt) / 1000,
        quota: scanQuotaPayload(quota, reservation.accessMode),
        warnings: recognized?.length === candidates.length
          ? []
          : ["Some recognized cards are missing from the catalog."],
        results,
      },
    };
    await settleScanQuota(
      c.env.DB,
      auth.owner,
      requestId,
      "consumed",
      scanId,
      { body: responseBody, status: 200 },
    );
    return c.json(responseBody);
  });

  routes.post("/scan/:scan_id/confirm", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "unauthorized") return c.json(UNAUTHORIZED_RESPONSE, 401);
    if (auth.status === "internal_error") return c.json(INTERNAL_ERROR_RESPONSE, 500);

    const body = await readJson(c.req);
    const draft = collectionItemDraftFromBody(body, { object_type: "tcg" });
    if (!draft) return c.json(VALIDATION_ERROR_RESPONSE, 422);

    const scanId = c.req.param("scan_id");
    const scan = await c.env.DB.prepare(SELECT_SCAN_RECORD_SQL)
      .bind(scanId, auth.owner.owner_type, auth.owner.owner_id)
      .first<ScanRecordRow>();
    if (!scan) return c.json(NOT_FOUND_RESPONSE, 404);
    if (scan.user_confirmation_status !== "pending") {
      return c.json(CONFLICT_RESPONSE, 409);
    }

    const candidates = parseStoredCandidates(scan.candidates);
    const selectedCandidate = candidates.find(
      (candidate) => candidate.card_ref === draft.card_ref,
    );
    if (!selectedCandidate) return c.json(VALIDATION_ERROR_RESPONSE, 422);

    const folder = await c.env.DB.prepare(SELECT_PORTFOLIO_FOLDER_SQL)
      .bind(draft.folder_id, auth.owner.owner_type, auth.owner.owner_id)
      .first<PortfolioFolderRow>();
    if (!folder) return c.json(NOT_FOUND_RESPONSE, 404);

    const duplicate = await c.env.DB.prepare(SELECT_COLLECTION_ITEM_BY_SKU_SQL)
      .bind(
        auth.owner.owner_type,
        auth.owner.owner_id,
        draft.folder_id,
        draft.card_ref,
        draft.language,
        draft.finish,
      )
      .first<{ id: string }>();
    if (duplicate) return c.json(DUPLICATE_COLLECTION_ITEM_RESPONSE, 409);

    const itemId = createId();
    const now = new Date().toISOString();
    const userResult = JSON.stringify({
      confirmation_status: "confirmed",
      final_card: selectedCandidate,
      modified_result: candidates[0]?.card_ref !== draft.card_ref,
      added_to_inventory: true,
      collection_item_id: itemId,
      added_to_wishlist: false,
    });
    let results: D1Result<unknown>[];
    try {
      results = await runWithMutationLocks(
        c.env.DB,
        [
          await ownerCardMutationLockKey(auth.owner, draft.card_ref),
          await mutationLockKey(
            "scan-confirm",
            `${auth.owner.owner_type}:${auth.owner.owner_id}:${scanId}`,
          ),
        ],
        [
          c.env.DB.prepare(INSERT_CONFIRMED_COLLECTION_ITEM_SQL).bind(
            itemId,
            auth.owner.owner_type,
            auth.owner.owner_id,
            draft.folder_id,
            draft.card_ref,
            draft.object_type,
            draft.grader,
            draft.condition,
            draft.grade,
            draft.language,
            draft.finish,
            draft.quantity,
            draft.purchase_price,
            draft.purchase_currency,
            draft.notes,
            now,
            now,
            now,
            scanId,
            auth.owner.owner_type,
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(INSERT_CONFIRMED_COLLECTION_ITEM_EVENT_SQL).bind(
            createId(),
            now,
            itemId,
            auth.owner.owner_type,
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(DELETE_CONFIRMED_WISHLIST_CARD_SQL).bind(
            auth.owner.owner_type,
            auth.owner.owner_id,
            draft.card_ref,
            itemId,
            auth.owner.owner_type,
            auth.owner.owner_id,
          ),
          c.env.DB.prepare(UPDATE_SCAN_CONFIRMATION_SQL).bind(
            candidates[0]?.card_ref === draft.card_ref ? 0 : 1,
            userResult,
            scanId,
            auth.owner.owner_type,
            auth.owner.owner_id,
          ),
        ],
      );
    } catch (error) {
      if (isUniqueConstraintError(error)) {
        return c.json(DUPLICATE_COLLECTION_ITEM_RESPONSE, 409);
      }
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (
      results[0]?.meta.changes !== 1 ||
      results[1]?.meta.changes !== 1 ||
      results[3]?.meta.changes !== 1
    ) {
      return c.json(CONFLICT_RESPONSE, 409);
    }

    return c.json(
      {
        success: true,
        data: {
          scan_id: scanId,
          collection_item_id: itemId,
          card_ref: draft.card_ref,
          folder_id: draft.folder_id,
        },
      },
      201,
    );
  });

  return routes;
}

async function readFormData(request: { formData(): Promise<FormData> }): Promise<FormData | null> {
  try {
    return await request.formData();
  } catch {
    return null;
  }
}

function parseStoredCandidates(value: string): ScanCandidate[] {
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed)
      ? parsed.filter(isStoredScanCandidate)
      : [];
  } catch {
    return [];
  }
}

function isStoredScanCandidate(value: unknown): value is ScanCandidate {
  return isRecord(value) &&
    readString(value.card_ref) !== null &&
    value.catalog_matched !== false;
}

function toCatalogCandidate(
  card: CardSearchResult,
  recognized: RecognitionCandidate,
  index: number,
): ScanCandidate {
  return {
    rank: index + 1,
    product_id: recognized.productId,
    card_ref: card.card_ref,
    catalog_matched: true,
    game: card.game ?? null,
    name: card.name,
    set_code: card.set_code || null,
    card_number: card.card_number || null,
    rarity: card.rarity,
    confidence: recognized.confidence,
    retrieval: "rgb-phash-16-v1",
    distance: null,
  };
}

function toUnresolvedCandidate(
  recognized: RecognitionCandidate,
  index: number,
): ScanCandidate {
  return {
    rank: index + 1,
    product_id: recognized.productId,
    card_ref: String(recognized.productId),
    catalog_matched: false,
    game: null,
    name: null,
    set_code: null,
    card_number: null,
    rarity: null,
    confidence: recognized.confidence,
    retrieval: "rgb-phash-16-v1",
    distance: null,
  };
}

async function readJson(request: { json(): Promise<unknown> }): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function buildSystemResult(
  status: string,
  candidate: ScanCandidate | null,
  candidateCount: number,
) {
  return {
    status,
    name: candidate?.name ?? null,
    ip_game: candidate?.game ?? null,
    set: candidate?.set_code ?? null,
    number: candidate?.card_number ?? null,
    rarity: candidate?.rarity ?? null,
    confidence: candidate?.confidence ?? null,
    candidate_count: candidateCount,
  };
}

function readPhash(value: unknown): string | null {
  return typeof value === "string" && PHASH_PATTERN.test(value) ? value : null;
}

function readOptionalGameId(value: string | File | null): number | undefined | null {
  if (value === null || value === "") return undefined;
  if (typeof value !== "string" || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 1 && parsed <= 4_294_967_295 ? parsed : null;
}

function readOptionalCardNumber(
  value: string | File | null,
): string | undefined | null {
  if (value === null || value === "") return undefined;
  if (typeof value !== "string") return null;
  const normalized = value.toUpperCase().replace(/\s+/g, "");
  return CARD_NUMBER_PATTERN.test(normalized) ? normalized : null;
}

function prioritizeByCardNumber(
  candidates: ScanCandidate[],
  cardNumber: string | undefined,
): ScanCandidate[] {
  if (!cardNumber) return candidates;
  const matching = candidates.filter(
    (candidate) => normalizeCardNumber(candidate.card_number) === cardNumber,
  );
  if (matching.length === 0) return candidates;
  const matchingRefs = new Set(matching.map((candidate) => candidate.card_ref));
  return [
    ...matching,
    ...candidates.filter((candidate) => !matchingRefs.has(candidate.card_ref)),
  ].map((candidate, index) => ({
    ...candidate,
    rank: index + 1,
    retrieval: matchingRefs.has(candidate.card_ref)
      ? `${candidate.retrieval}+card-number-ocr`
      : candidate.retrieval,
  }));
}

async function disambiguateByCardNumber(
  candidates: ScanCandidate[],
  cardNumber: string | undefined,
  adapter: Pick<DataSourceAdapter, "searchCards">,
): Promise<ScanCandidate[]> {
  const prioritized = prioritizeByCardNumber(candidates, cardNumber);
  if (
    !cardNumber ||
    prioritized.some(
      (candidate) => normalizeCardNumber(candidate.card_number) === cardNumber,
    )
  ) {
    return prioritized;
  }

  const searchedNames = new Set<string>();
  for (const source of candidates.slice(0, 5)) {
    const name = source.name?.trim();
    if (!name || searchedNames.has(name.toLowerCase())) continue;
    searchedNames.add(name.toLowerCase());
    try {
      const matches = await adapter.searchCards(`${name} ${cardNumber}`, {
        ...(source.game ? { game: source.game } : {}),
        page_size: 10,
      });
      const card = matches.find(
        (candidate) => normalizeCardNumber(candidate.card_number) === cardNumber,
      );
      const productId = Number(card?.card_ref);
      if (!card || !Number.isInteger(productId) || productId < 1) continue;
      const recovered = toCatalogCandidate(
        card,
        { productId, confidence: source.confidence ?? 0 },
        candidates.length,
      );
      return prioritizeByCardNumber([...candidates, recovered], cardNumber);
    } catch (error) {
      console.error("Failed to disambiguate scan by card number.", error);
    }
  }
  return candidates;
}

function normalizeCardNumber(value: string | null): string | null {
  return value?.toUpperCase().replace(/\s+/g, "") ?? null;
}

function readRecognitionCandidates(value: unknown): RecognitionCandidate[] | null {
  if (!Array.isArray(value)) return null;
  const candidates: RecognitionCandidate[] = [];
  const seen = new Set<number>();
  for (const item of value) {
    if (!isRecord(item)) return null;
    const productId = item.product_id;
    const confidence = item.confidence;
    if (
      typeof productId !== "number" || !Number.isInteger(productId) ||
      productId < 1 || productId > 4_294_967_295 ||
      typeof confidence !== "number" || !Number.isFinite(confidence) ||
      confidence < 0 || confidence > 100
    ) {
      return null;
    }
    if (!seen.has(productId)) {
      seen.add(productId);
      candidates.push({ productId, confidence });
    }
  }
  return candidates;
}

function scanImageKey(
  ownerType: string,
  ownerId: string,
  scanId: string,
  image: ValidatedScanImage,
  createdAt: Date,
): string {
  const year = createdAt.getUTCFullYear();
  const month = String(createdAt.getUTCMonth() + 1).padStart(2, "0");
  return `scans/${ownerType}/${encodeURIComponent(ownerId)}/${year}/${month}/${scanId}.${image.extension}`;
}

async function deleteUploadedImage(bucket: R2Bucket, key: string): Promise<void> {
  try {
    await bucket.delete(key);
  } catch (error) {
    console.error("Failed to compensate scan image upload.", { key, error });
  }
}

function isUniqueConstraintError(error: unknown): boolean {
  return error instanceof Error &&
    error.message.toLowerCase().includes("unique constraint");
}

function normalizeBaseUrl(value: string | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;
  return trimmed.replace(/\/+$/, "");
}

function readString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === "number") return String(value);
  return null;
}

function readUuid(value: unknown): string | null {
  const normalized = readString(value);
  return normalized &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(normalized)
    ? normalized
    : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
