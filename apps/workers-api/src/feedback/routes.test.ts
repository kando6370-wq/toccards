import { signAccessToken } from "@kando/auth-core";
import { describe, expect, it } from "vitest";
import app, { type Env } from "../index";

type SessionRow = {
  id: string;
  owner_type: "anonymous";
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

type FeedbackRow = {
  id: string;
  email: string;
  types: string;
  functions: string;
  message: string;
  status: string;
};

class FakeD1 {
  sessions: SessionRow[] = [];
  anonymousAccounts: string[] = [];
  feedback: FeedbackRow[] = [];

  prepare(sql: string): FakeD1Statement {
    return new FakeD1Statement(this, sql);
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

  async first<T>(): Promise<T | null> {
    const sql = normalizeSql(this.sql);
    if (sql.includes("FROM session")) {
      const [id] = this.values as [string];
      return (this.db.sessions.find((row) => row.id === id) ?? null) as T | null;
    }
    if (sql.includes("FROM anonymous_account")) {
      const [id] = this.values as [string];
      return (this.db.anonymousAccounts.includes(id) ? { id } : null) as T | null;
    }
    return null;
  }

  async run<T>(): Promise<D1Result<T>> {
    const sql = normalizeSql(this.sql);
    if (!sql.startsWith("INSERT INTO feedback_ticket")) {
      throw new Error(`Unsupported run SQL: ${sql}`);
    }

    const [id, email, types, functions, message] = this.values as string[];
    this.db.feedback.push({
      id,
      email,
      types,
      functions,
      message,
      status: "open",
    });
    return okResult<T>();
  }
}

describe("feedback routes", () => {
  it("persists authenticated feedback because support submissions must reach the operations queue", async () => {
    const { env, token } = await authenticatedEnv();
    const response = await app.request(
      "/api/v1/feedback",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          email: " Person@Example.com ",
          types: ["Bug Report"],
          functions: ["Price Data"],
          message: " Prices are stale. ",
        }),
      },
      env,
    );

    expect(response.status).toBe(201);
    expect(await response.json()).toEqual({
      success: true,
      data: {
        id: expect.any(String),
        status: "open",
        created_at: expect.any(String),
      },
    });
    expect(env.DB.feedback).toEqual([
      {
        id: expect.any(String),
        email: "person@example.com",
        types: '["Bug Report"]',
        functions: '["Price Data"]',
        message: "Prices are stale.",
        status: "open",
      },
    ]);
  });

  it("defaults empty classifications to Other because PRD makes both selectors optional", async () => {
    const { env, token } = await authenticatedEnv();
    const response = await submit(env, token, {
      email: "guest@example.com",
      types: [],
      message: "General feedback",
    });

    expect(response.status).toBe(201);
    expect(env.DB.feedback[0]).toMatchObject({
      types: '["Other"]',
      functions: '["Other"]',
    });
  });

  it("rejects invalid content because the database must not rely on client-side validation", async () => {
    const { env, token } = await authenticatedEnv();
    const invalidBodies = [
      { email: "invalid", message: "Feedback" },
      { email: "guest@example.com", types: ["Subscription"], message: "Feedback" },
      { email: "guest@example.com", message: "x".repeat(1001) },
    ];

    for (const body of invalidBodies) {
      const response = await submit(env, token, body);
      expect(response.status).toBe(422);
    }
    expect(env.DB.feedback).toEqual([]);
  });

  it("rejects missing authentication because feedback is submitted from an active app session", async () => {
    const env = testEnv(new FakeD1());
    const response = await app.request(
      "/api/v1/feedback",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: "guest@example.com", message: "Feedback" }),
      },
      env,
    );

    expect(response.status).toBe(401);
    expect(env.DB.feedback).toEqual([]);
  });
});

async function authenticatedEnv() {
  const db = new FakeD1();
  db.sessions.push({
    id: "session-1",
    owner_type: "anonymous",
    owner_id: "anon-1",
    expires_at: "2099-01-01T00:00:00.000Z",
    revoked_at: null,
  });
  db.anonymousAccounts.push("anon-1");
  const env = testEnv(db);
  const token = await signAccessToken(
    { owner_type: "anonymous", owner_id: "anon-1", session_id: "session-1" },
    env.JWT_SECRET,
  );
  return { env, token };
}

async function submit(env: TestEnv, token: string, body: object): Promise<Response> {
  return await app.request(
    "/api/v1/feedback",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    },
    env,
  );
}

type TestEnv = Omit<Env, "DB"> & { DB: FakeD1; JWT_SECRET: string };

function testEnv(db: FakeD1): TestEnv {
  return {
    DB: db,
    CACHE_KV: {} as KVNamespace,
    JWT_SECRET: "test-secret",
  };
}

function normalizeSql(sql: string): string {
  return sql.replace(/\s+/g, " ").trim();
}

function okResult<T>(): D1Result<T> {
  return {
    success: true,
    results: [],
    meta: {
      duration: 0,
      size_after: 0,
      rows_read: 0,
      rows_written: 1,
      last_row_id: 0,
      changed_db: true,
      changes: 1,
    },
  };
}
