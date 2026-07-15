import { Hono } from "hono";
import type { Env } from "../env";
import { createId } from "../id";
import { authenticateOwner } from "../owner-auth";

const FEEDBACK_TYPES = new Set([
  "Bug Report",
  "Feature Request",
  "Improvement",
  "Other",
]);
const FEEDBACK_FUNCTIONS = new Set([
  "Scan",
  "Search",
  "Collection",
  "Portfolio",
  "Wishlist",
  "Account",
  "Price Data",
  "Other",
]);

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

const INSERT_FEEDBACK_SQL = `
INSERT INTO feedback_ticket
  (id, email, types, functions, message, status, created_at, updated_at)
VALUES (?, ?, ?, ?, ?, 'open', ?, ?)
`;

type FeedbackDraft = {
  email: string;
  types: string[];
  functions: string[];
  message: string;
};

export function createFeedbackRoutes(): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();

  routes.post("/feedback", async (c) => {
    const auth = await authenticateOwner(
      c.env,
      c.req.header("Authorization"),
    );

    if (auth.status === "internal_error") {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
    if (auth.status === "unauthorized") {
      return c.json(UNAUTHORIZED_RESPONSE, 401);
    }

    const draft = feedbackDraftFromBody(await readJson(c.req));
    if (!draft) {
      return c.json(VALIDATION_ERROR_RESPONSE, 422);
    }

    const id = createId();
    const now = new Date().toISOString();
    try {
      await c.env.DB.prepare(INSERT_FEEDBACK_SQL)
        .bind(
          id,
          draft.email,
          JSON.stringify(draft.types),
          JSON.stringify(draft.functions),
          draft.message,
          now,
          now,
        )
        .run();
    } catch {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    return c.json(
      {
        success: true,
        data: { id, status: "open", created_at: now },
      },
      201,
    );
  });

  return routes;
}

async function readJson(request: { json(): Promise<unknown> }): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function feedbackDraftFromBody(body: unknown): FeedbackDraft | null {
  if (!isRecord(body)) return null;

  const email = normalizedEmail(body.email);
  const types = feedbackSelections(body.types, FEEDBACK_TYPES);
  const functions = feedbackSelections(body.functions, FEEDBACK_FUNCTIONS);
  const message = typeof body.message === "string" ? body.message.trim() : "";

  if (
    !email ||
    !types ||
    !functions ||
    message.length < 1 ||
    message.length > 1000
  ) {
    return null;
  }

  return { email, types, functions, message };
}

function normalizedEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;

  const email = value.trim().toLowerCase();
  if (email.length < 1 || email.length > 254 || /\s/.test(email)) return null;

  const parts = email.split("@");
  if (parts.length !== 2 || !parts[0] || !parts[1]?.includes(".")) return null;

  return parts[1].split(".").every((label) => label.length > 0) ? email : null;
}

function feedbackSelections(
  value: unknown,
  allowed: ReadonlySet<string>,
): string[] | null {
  if (value === undefined || (Array.isArray(value) && value.length === 0)) {
    return ["Other"];
  }
  if (!Array.isArray(value)) return null;

  const selections: string[] = [];
  for (const item of value) {
    if (
      typeof item !== "string" ||
      !allowed.has(item) ||
      selections.includes(item)
    ) {
      return null;
    }
    selections.push(item);
  }
  return selections.length > 0 ? selections : ["Other"];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
