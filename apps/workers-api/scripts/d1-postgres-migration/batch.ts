import type { MigrationTable } from "./tables";

export type MigrationRow = Record<string, string | number | null>;

export const MAX_BATCH_ROWS = 500;
export const MAX_BATCH_BYTES = 512 * 1024;

export function takeBoundedRows(rows: MigrationRow[], table: MigrationTable) {
  const selected: MigrationRow[] = [];
  let payloadBytes = 0;

  for (const row of rows) {
    const rowBytes = encodedRowBytes(row, table);
    if (selected.length > 0 && payloadBytes + rowBytes > MAX_BATCH_BYTES) {
      break;
    }
    if (selected.length === 0 && rowBytes > MAX_BATCH_BYTES) {
      throw new Error(`Source row exceeds ${MAX_BATCH_BYTES} byte limit in ${table.name}`);
    }
    selected.push(row);
    payloadBytes += rowBytes;
  }

  return { rows: selected, payloadBytes };
}

export function encodedRowBytes(row: MigrationRow, table: MigrationTable) {
  return new TextEncoder().encode(canonicalRow(row, table)).byteLength;
}

export async function digestRows(rows: MigrationRow[], table: MigrationTable) {
  return sha256Hex(rows.map((row) => canonicalRow(row, table)).join("\n"));
}

export function canonicalRow(row: MigrationRow, table: MigrationTable) {
  const bigintColumns = new Set(table.bigintColumns ?? []);
  return JSON.stringify(
    table.columns.map((column) => {
      const value = row[column];
      if (value === null || value === undefined) {
        return null;
      }
      if (bigintColumns.has(column)) {
        return String(value);
      }
      return value;
    }),
  );
}

export async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function canonicalMigrationSql(value: string): string {
  return value.replace(/\r\n?/g, "\n");
}
