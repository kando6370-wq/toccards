import { Hono } from "hono";

import { getBearerToken } from "../auth/http-auth";
import { createDefaultAdapter, resolveCard, withCardImageUrl, type CardResponse } from "../data-source/routes";
import type { Env } from "../env";
import { readRecognitionCandidates } from "../scan/routes";

const MAX_REQUEST_BYTES = 32 * 1024;
const EMBEDDING_DIMENSIONS = 512;

export function createExtensionRoutes(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();

  routes.post("/extension/recognize", async (c) => {
    c.header("Cache-Control", "no-store");
    const fail = (code: string, message: string, status: 401 | 413 | 422 | 429 | 500 | 502 | 503 | 504) =>
      c.json({ success: false, error: { code, message } }, status);
    const key = c.env.EXTENSION_RECOGNITION_KEY?.trim();
    if (!key) return fail("EXTENSION_RECOGNITION_UNAVAILABLE", "Extension recognition is unavailable.", 503);
    if (getBearerToken(c.req.header("Authorization")) !== key) {
      return fail("UNAUTHORIZED", "Unauthorized.", 401);
    }
    const limiter = c.env.EXTENSION_RECOGNITION_RATE_LIMITER;
    const clientIp = c.env.EXTENSION_CLIENT_IP;
    const recognition = c.env.VECTOR_RECOGNITION;
    if (!limiter || !clientIp || !recognition) {
      return fail("EXTENSION_RECOGNITION_UNAVAILABLE", "Extension recognition is unavailable.", 503);
    }
    try {
      if (!(await limiter.limit({ key: clientIp })).success) {
        c.header("Retry-After", "60");
        return fail("RATE_LIMITED", "Too many requests. Please try again later.", 429);
      }
    } catch {
      console.error("Extension recognition rate limiter unavailable.");
      return fail("EXTENSION_RECOGNITION_UNAVAILABLE", "Extension recognition is unavailable.", 503);
    }

    let input: { vector: number[]; card_type: 0 | 1 } | null = null;
    try {
      if (c.req.header("Content-Type")?.split(";")[0].trim().toLowerCase() !== "application/json") {
        return fail("VALIDATION_ERROR", "Invalid request.", 422);
      }
      const body = await readBoundedBody(c.req.raw);
      if (body === null) return fail("PAYLOAD_TOO_LARGE", "Request body is too large.", 413);
      input = recognitionInput(JSON.parse(body));
    } catch {
      return fail("VALIDATION_ERROR", "Invalid request.", 422);
    }
    if (!input) return fail("VALIDATION_ERROR", "Invalid request.", 422);

    let recognized: ReturnType<typeof readRecognitionCandidates> = null;
    const signal = AbortSignal.any([c.req.raw.signal, AbortSignal.timeout(10_000)]);
    try {
      const response = await recognition.fetch("https://recognize-vec.internal/recognize", {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify(input),
        signal,
        redirect: "error",
      });
      const payload = await response.json();
      if (!response.ok) {
        return fail("VECTOR_RECOGNITION_UNAVAILABLE", "Recognition service is unavailable.", 502);
      }
      recognized = readRecognitionCandidates(
        payload && typeof payload === "object" ? (payload as Record<string, unknown>).candidates : undefined,
      );
      if (!recognized) {
        return fail("VECTOR_RECOGNITION_UNAVAILABLE", "Recognition service is unavailable.", 502);
      }
    } catch (error) {
      if (signal.aborted || (error instanceof Error && error.name === "TimeoutError")) {
        return fail("VECTOR_RECOGNITION_TIMEOUT", "Recognition service timed out.", 504);
      }
      console.error("Extension recognition upstream request failed.");
      return fail("VECTOR_RECOGNITION_UNAVAILABLE", "Recognition service is unavailable.", 502);
    }

    if (recognized.length === 0) return c.json({ candidates: [] });
    try {
      const adapter = createDefaultAdapter(c.env);
      const candidates: Array<CardResponse & { product_id: string; confidence: number }> = [];
      for (const candidate of recognized) {
        const card = await resolveCard(c.env.DB, adapter, candidate.productId);
        if (card) {
          candidates.push({
            ...withCardImageUrl(card, "detail"),
            product_id: candidate.productId,
            confidence: candidate.confidence,
          });
        }
      }
      return c.json({ candidates });
    } catch {
      console.error("Failed to resolve extension card details.");
      return fail("INTERNAL_ERROR", "Something went wrong. Please try again.", 500);
    }
  });

  return routes;
}

function recognitionInput(value: unknown): { vector: number[]; card_type: 0 | 1 } | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const { vector, card_type = 0 } = value as Record<string, unknown>;
  if (
    !Array.isArray(vector) || vector.length !== EMBEDDING_DIMENSIONS ||
    !vector.every((item) => typeof item === "number" && Number.isFinite(item)) ||
    !vector.some((item) => item !== 0) ||
    (card_type !== 0 && card_type !== 1)
  ) return null;
  return { vector, card_type };
}

async function readBoundedBody(request: Request): Promise<string | null> {
  const reader = request.body?.getReader();
  if (!reader) return "";
  const decoder = new TextDecoder();
  let bytes = 0;
  let body = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) return body + decoder.decode();
      bytes += value.byteLength;
      if (bytes > MAX_REQUEST_BYTES) {
        await reader.cancel();
        return null;
      }
      body += decoder.decode(value, { stream: true });
    }
  } finally {
    reader.releaseLock();
  }
}
