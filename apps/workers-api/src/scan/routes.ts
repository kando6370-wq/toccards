import { Hono } from "hono";
import { collectionItemDraftFromBody } from "../collection-item";
import type { Env } from "../env";
import { createId } from "../id";
import { authenticateOwner } from "../owner-auth";

type ScanBindings = { Bindings: Env };

type ScanCandidate = {
  rank: number;
  card_ref: string;
  game: string | null;
  name: string;
  set_code: string | null;
  card_number: string | null;
  rarity: string | null;
  confidence: number | null;
  retrieval: string | null;
  distance: number | null;
};

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
   created_at, updated_at)
SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
WHERE EXISTS (
  SELECT 1 FROM scan_record
  WHERE id = ? AND owner_type = ? AND owner_id = ?
    AND user_confirmation_status = 'pending'
)
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

const PASSTHROUGH_FIELDS = [
  "threshold",
  "top",
  "save_crop",
  "no_detect",
  "retrieval",
  "crop_method",
  "conf",
  "multi",
  "no_refine",
  "ocr_rerank",
  "ocr_model",
  "ocr_auto_gap",
  "phash_cluster_gap",
  "vector_cluster_gap",
] as const;

export function createScanRoutes() {
  const routes = new Hono<ScanBindings>();

  routes.post("/scan/recognize", async (c) => {
    const auth = await authenticateOwner(c.env, c.req.header("Authorization"));
    if (auth.status === "unauthorized") return c.json(UNAUTHORIZED_RESPONSE, 401);
    if (auth.status === "internal_error") return c.json(INTERNAL_ERROR_RESPONSE, 500);

    const serviceBaseUrl = normalizeBaseUrl(c.env.OCR_SERVICE_BASE_URL);
    if (!serviceBaseUrl) return c.json(OCR_UNAVAILABLE_RESPONSE, 503);

    const form = await c.req.raw.formData();
    const image = form.get("image") as unknown;
    if (!isFileLike(image)) return c.json(VALIDATION_ERROR_RESPONSE, 422);

    const outbound = new FormData();
    outbound.set("image", image, image.name || "scan.jpg");
    for (const field of PASSTHROUGH_FIELDS) {
      const value = readFormString(form, field);
      if (value !== null) outbound.set(field, value);
    }
    if (!outbound.has("retrieval")) outbound.set("retrieval", "phash");
    if (!outbound.has("top")) outbound.set("top", "5");

    let ocrPayload: unknown;
    try {
      const response = await fetch(`${serviceBaseUrl}/recognize`, {
        method: "POST",
        body: outbound,
      });
      ocrPayload = await response.json();
      if (!response.ok) return c.json(OCR_UNAVAILABLE_RESPONSE, 502);
    } catch {
      return c.json(OCR_UNAVAILABLE_RESPONSE, 502);
    }

    const payload = isRecord(ocrPayload) ? ocrPayload : {};
    if (payload.ok !== true) return c.json(OCR_UNAVAILABLE_RESPONSE, 502);

    const scanId = createId();
    const createdAt = new Date().toISOString();
    const results = readScanResults(payload);
    const candidates = results.flatMap((result) => result.candidates);
    const recognitionStatus = candidates.length > 0 ? "success" : "no_match";
    const systemResult = buildSystemResult(recognitionStatus, candidates[0] ?? null);
    const userResult = {
      confirmation_status: "pending",
      final_card: null,
      modified_result: false,
      added_to_inventory: false,
      added_to_wishlist: false,
    };

    await c.env.DB.prepare(INSERT_SCAN_RECORD_SQL)
      .bind(
        scanId,
        auth.owner.owner_type,
        auth.owner.owner_id,
        readFormString(form, "image_url"),
        readString(payload.filename) ?? image.name ?? "scan.jpg",
        readFormString(form, "platform") ?? "iOS",
        readFormString(form, "app_version") ?? "unknown",
        readFormString(form, "device_model"),
        readFormString(form, "os_version"),
        recognitionStatus,
        "pending",
        JSON.stringify(systemResult),
        JSON.stringify(userResult),
        JSON.stringify(candidates),
        JSON.stringify(payload),
        createdAt,
      )
      .run();

    return c.json({
      success: true,
      data: {
        scan_id: scanId,
        recognition_status: recognitionStatus,
        cards_detected: readNumber(payload.cards_detected) ?? results.length,
        elapsed: readNumber(payload.elapsed),
        warnings: readStringArray(payload.warnings),
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
        scanId,
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

    if (results[0]?.meta.changes !== 1 || results[2]?.meta.changes !== 1) {
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

function readScanResults(payload: Record<string, unknown>): ScanResult[] {
  const results = Array.isArray(payload.results) ? payload.results : [];
  return results.map((item, itemIndex) => {
    const row = isRecord(item) ? item : {};
    const matches = Array.isArray(row.matches) ? row.matches : [];
    const candidates = matches
      .map((match, matchIndex) => toScanCandidate(match, matchIndex))
      .filter((candidate): candidate is ScanCandidate => candidate !== null);
    return {
      index: readNumber(row.index) ?? itemIndex + 1,
      matched: row.matched === true && candidates.length > 0,
      candidates,
    };
  });
}

async function readJson(request: { json(): Promise<unknown> }): Promise<unknown> {
  try {
    return await request.json();
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
  return isRecord(value) && readString(value.card_ref) !== null;
}

function toScanCandidate(value: unknown, index: number): ScanCandidate | null {
  if (!isRecord(value)) return null;
  const cardRef = readString(value.product_id);
  const name = readString(value.name);
  if (!cardRef || !name) return null;
  return {
    rank: index + 1,
    card_ref: cardRef,
    game: readString(value.game),
    name,
    set_code: readString(value.set),
    card_number: readString(value.number),
    rarity: readString(value.rarity),
    confidence: readNumber(value.confidence),
    retrieval: readString(value.retrieval),
    distance: readNumber(value.distance),
  };
}

function buildSystemResult(status: string, candidate: ScanCandidate | null) {
  return {
    status,
    name: candidate?.name ?? null,
    ip_game: candidate?.game ?? null,
    set: candidate?.set_code ?? null,
    number: candidate?.card_number ?? null,
    rarity: candidate?.rarity ?? null,
    confidence: candidate?.confidence ?? null,
    candidate_count: candidate ? 1 : 0,
  };
}

function normalizeBaseUrl(value: string | undefined): string | null {
  const trimmed = value?.trim();
  if (!trimmed) return null;
  return trimmed.replace(/\/+$/, "");
}

function readFormString(form: FormData, key: string): string | null {
  const value = form.get(key);
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function readString(value: unknown): string | null {
  if (typeof value === "string") {
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
  if (typeof value === "number") return String(value);
  return null;
}

function readNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function readStringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.map(String) : [];
}

function isFileLike(value: unknown): value is File {
  return typeof File !== "undefined" && value instanceof File;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
