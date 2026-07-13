import { Hono } from "hono";
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

const INSERT_SCAN_RECORD_SQL = `
INSERT INTO scan_record
  (id, owner_type, owner_id, image_url, filename, platform, app_version,
   device_model, os_version, recognition_status, user_confirmation_status,
   system_result, user_result, candidates, raw_response, created_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
