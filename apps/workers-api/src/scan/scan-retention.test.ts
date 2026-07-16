import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { purgeExpiredScanImages } from "./scan-retention";

type Row = { id: string; image_url: string; created_at: string };

class FakeDb {
  constructor(readonly rows: Row[]) {}

  prepare(sql: string): FakeStatement {
    return new FakeStatement(this, sql);
  }

  async batch(statements: FakeStatement[]): Promise<D1Result[]> {
    return Promise.all(statements.map((statement) => statement.run()));
  }
}

class FakeStatement {
  private values: unknown[] = [];

  constructor(private readonly db: FakeDb, private readonly sql: string) {}

  bind(...values: unknown[]): FakeStatement {
    this.values = values;
    return this;
  }

  async all<T>(): Promise<D1Result<T>> {
    const [cutoff] = this.values as [string];
    const results = this.db.rows
      .filter((row) => row.image_url && row.created_at < cutoff)
      .map(({ id, image_url }) => ({ id, image_url })) as T[];
    return result(results);
  }

  async run<T>(): Promise<D1Result<T>> {
    if (!this.sql.includes("UPDATE scan_record")) throw new Error("Unexpected SQL.");
    const [id, imageUrl] = this.values as [string, string];
    const row = this.db.rows.find(
      (candidate) => candidate.id === id && candidate.image_url === imageUrl,
    );
    if (row) row.image_url = "";
    return result<T>([], row ? 1 : 0);
  }
}

class FakeR2 {
  readonly deleted: string[] = [];

  async delete(keys: string | string[]): Promise<void> {
    this.deleted.push(...(Array.isArray(keys) ? keys : [keys]));
  }
}

describe("scan image retention", () => {
  it("deletes only images older than 30 days because the published privacy limit must be enforced", async () => {
    const db = new FakeDb([
      row("expired", "scans/expired.jpg", "2026-06-15T11:59:59.000Z"),
      row("boundary", "scans/boundary.jpg", "2026-06-16T12:00:00.000Z"),
      row("recent", "scans/recent.jpg", "2026-07-15T12:00:00.000Z"),
    ]);
    const bucket = new FakeR2();

    const purged = await purgeExpiredScanImages(
      env(db, bucket, "30"),
      new Date("2026-07-16T12:00:00.000Z"),
    );

    expect(purged).toBe(1);
    expect(bucket.deleted).toEqual(["scans/expired.jpg"]);
    expect(db.rows.find((item) => item.id === "expired")?.image_url).toBe("");
    expect(db.rows.find((item) => item.id === "boundary")?.image_url).toBe(
      "scans/boundary.jpg",
    );
  });

  it("fails loudly for an unapproved retention value because indefinite image storage must not resume silently", async () => {
    await expect(
      purgeExpiredScanImages(
        env(new FakeDb([]), new FakeR2(), "UNCONFIRMED"),
      ),
    ).rejects.toThrow("SCAN_IMAGE_RETENTION_DAYS");
  });
});

function row(id: string, imageUrl: string, createdAt: string): Row {
  return { id, image_url: imageUrl, created_at: createdAt };
}

function env(db: FakeDb, bucket: FakeR2, retentionDays: string): Env {
  return {
    DB: db as unknown as D1Database,
    CACHE_KV: {} as KVNamespace,
    SCAN_IMAGES: bucket as unknown as R2Bucket,
    JWT_SECRET: "test-secret-with-at-least-32-characters",
    SCAN_IMAGE_RETENTION_DAYS: retentionDays,
  };
}

function result<T>(results: T[] = [], changes = 0): D1Result<T> {
  return {
    results,
    success: true,
    meta: { changes } as D1Result<T>["meta"],
  };
}
