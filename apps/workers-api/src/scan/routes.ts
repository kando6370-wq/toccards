import { Hono } from "hono";
import { collectionItemDraftFromBody } from "../collection-item";
import type { CardSearchResult } from "../data-source/adapter";
import { createLocalDbDataSourceAdapter } from "../data-source/local-db-adapter";
import type { Env } from "../env";
import { createId } from "../id";
import { authenticateOwner } from "../owner-auth";
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
  AND object_type = ? AND grader = ? AND condition IS ? AND grade IS ?
  AND language IS ? AND finish IS ?
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
`;

const UPDATE_SCAN_CONFIRMATION_SQL = `
UPDATE scan_record
SET user_confirmation_status = 'confirmed', modified_result = ?, user_result = ?
WHERE id = ? AND owner_type = ? AND owner_id = ?
  AND user_confirmation_status = 'pending'
`;

const PHASH_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export function createScanRoutes() {
  const routes = new Hono<ScanBindings>();

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
    const r = readPhash(body.get("r"));
    const g = readPhash(body.get("g"));
    const b = readPhash(body.get("b"));
    const gameId = readOptionalGameId(body.get("game_id"));
    const image = await validateScanImage(body.get("image"));
    if (!r || !g || !b || gameId === null || !image) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const outbound = {
      r,
      g,
      b,
      ...(gameId === undefined ? {} : { game_id: gameId }),
    };

    const scanId = createId();
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
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    if (upstreamFailed) {
      return c.json({ ...OCR_UNAVAILABLE_RESPONSE, scan_id: scanId }, 502);
    }

    return c.json({
      success: true,
      data: {
        scan_id: scanId,
        recognition_status: recognitionStatus,
        cards_detected: candidates.length > 0 ? 1 : 0,
        elapsed: (Date.now() - startedAt) / 1000,
        warnings: recognized?.length === candidates.length
          ? []
          : ["Some recognized cards are missing from the catalog."],
        results,
      },
    });
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
        draft.object_type,
        draft.grader,
        draft.condition,
        draft.grade,
        draft.language,
        draft.finish,
      )
      .first<{ id: string }>();
    if (duplicate) return c.json(CONFLICT_RESPONSE, 409);

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
    const results = await c.env.DB.batch([
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
      ),
      c.env.DB.prepare(UPDATE_SCAN_CONFIRMATION_SQL).bind(
        candidates[0]?.card_ref === draft.card_ref ? 0 : 1,
        userResult,
        scanId,
        auth.owner.owner_type,
        auth.owner.owner_id,
      ),
    ]);

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

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
