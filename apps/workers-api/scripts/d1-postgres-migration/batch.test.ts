import { describe, expect, it } from "vitest";

import {
  MAX_BATCH_BYTES,
  canonicalRow,
  encodedRowBytes,
  takeBoundedRows,
} from "./batch";
import type { MigrationTable } from "./tables";

const table: MigrationTable = {
  name: "example",
  cursor: "id",
  cursorType: "text",
  columns: ["id", "amount_micros", "payload"],
  bigintColumns: ["amount_micros"],
};

describe("D1 to PostgreSQL migration batches", () => {
  it("normalizes bigint fields before source and target digests are compared", () => {
    expect(canonicalRow({ id: "1", amount_micros: 42, payload: null }, table))
      .toBe('["1","42",null]');
  });

  it("keeps only the largest prefix below the Hyperdrive payload cap", () => {
    const first = { id: "1", amount_micros: 1, payload: "a".repeat(300_000) };
    const second = { id: "2", amount_micros: 2, payload: "b".repeat(300_000) };

    const result = takeBoundedRows([first, second], table);

    expect(result.rows).toEqual([first]);
    expect(result.payloadBytes).toBe(encodedRowBytes(first, table));
    expect(result.payloadBytes).toBeLessThanOrEqual(MAX_BATCH_BYTES);
  });

  it("fails loudly instead of sending one oversized row", () => {
    const oversized = {
      id: "1",
      amount_micros: 1,
      payload: "x".repeat(MAX_BATCH_BYTES),
    };

    expect(() => takeBoundedRows([oversized], table))
      .toThrow(`Source row exceeds ${MAX_BATCH_BYTES} byte limit in example`);
  });
});
