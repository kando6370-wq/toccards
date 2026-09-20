import { signAccessToken } from "@kando/auth-core";
import { describe, expect, it } from "vitest";
import { authenticateOwner } from "./owner-auth";

type SessionRow = {
  id: string;
  owner_type: "user";
  owner_id: string;
  expires_at: string;
  revoked_at: string | null;
};

class FakeD1 {
  sessions: SessionRow[] = [];
  users: string[] = [];
  preparedSql: string[] = [];

  prepare(sql: string): D1PreparedStatement {
    this.preparedSql.push(sql);
    return new FakeStatement(this, sql) as unknown as D1PreparedStatement;
  }
}

class FakeStatement {
  private values: unknown[] = [];

  constructor(
    private readonly db: FakeD1,
    private readonly sql: string,
  ) {}

  bind(...values: unknown[]): FakeStatement {
    this.values = values;
    return this;
  }

  async first<T>(): Promise<T | null> {
    if (this.sql.includes("FROM session")) {
      const [sessionId] = this.values as [string];
      const session = this.db.sessions.find((row) => row.id === sessionId) ?? null;
      if (
        session
        && this.sql.includes('JOIN "user"')
        && !this.db.users.includes(session.owner_id)
      ) {
        return null;
      }
      return session as T | null;
    }
    return null;
  }
}

describe("authenticateOwner session context", () => {
  it("returns the verified live session because Premium grants must not collapse to UID ownership", async () => {
    const db = new FakeD1();
    db.sessions.push({
      id: "session-a",
      owner_type: "user",
      owner_id: "100000",
      expires_at: "2099-01-01T00:00:00.000Z",
      revoked_at: null,
    });
    db.users.push("100000");
    const secret = "test-secret";
    const token = await signAccessToken(
      { owner_type: "user", owner_id: "100000", session_id: "session-a" },
      secret,
    );

    const result = await authenticateOwner(
      { DB: db as unknown as D1Database, JWT_SECRET: secret },
      `Bearer ${token}`,
    );

    expect(result).toEqual({
      status: "ok",
      owner: { owner_type: "user", owner_id: "100000", session_id: "session-a" },
    });
    expect(db.preparedSql).toHaveLength(1);
    expect(db.preparedSql[0]).toContain('JOIN "user"');
  });

  it("rejects a session whose owner was removed because one-round-trip authentication must preserve owner validation", async () => {
    const db = new FakeD1();
    db.sessions.push({
      id: "session-a",
      owner_type: "user",
      owner_id: "100000",
      expires_at: "2099-01-01T00:00:00.000Z",
      revoked_at: null,
    });
    const secret = "test-secret";
    const token = await signAccessToken(
      { owner_type: "user", owner_id: "100000", session_id: "session-a" },
      secret,
    );

    const result = await authenticateOwner(
      { DB: db as unknown as D1Database, JWT_SECRET: secret },
      `Bearer ${token}`,
    );

    expect(result).toEqual({ status: "unauthorized" });
  });

  it("rejects a revoked session because logout must invalidate its Premium proof", async () => {
    const db = new FakeD1();
    db.sessions.push({
      id: "session-a",
      owner_type: "user",
      owner_id: "100000",
      expires_at: "2099-01-01T00:00:00.000Z",
      revoked_at: "2026-08-12T00:00:00.000Z",
    });
    db.users.push("100000");
    const secret = "test-secret";
    const token = await signAccessToken(
      { owner_type: "user", owner_id: "100000", session_id: "session-a" },
      secret,
    );

    const result = await authenticateOwner(
      { DB: db as unknown as D1Database, JWT_SECRET: secret },
      `Bearer ${token}`,
    );

    expect(result).toEqual({ status: "unauthorized" });
  });
});
