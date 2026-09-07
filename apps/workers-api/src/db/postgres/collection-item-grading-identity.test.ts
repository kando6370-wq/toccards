import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const testDirectory = dirname(fileURLToPath(import.meta.url));
const migration = readFileSync(
  join(testDirectory, "migrations/0008_collection_item_grading_identity.sql"),
  "utf8",
).replace(/\s+/g, " ").trim();

describe("PostgreSQL collection item grading identity migration", () => {
  it("makes the complete grading state part of database duplicate protection", () => {
    expect(migration).toBe([
      "DROP INDEX uq_collection_item_folder_card_finish_language;",
      "CREATE UNIQUE INDEX uq_collection_item_folder_card_variant ON collection_item",
      "( owner_type, owner_id, folder_id, card_ref, COALESCE(finish, ''),",
      "COALESCE(language, ''), grader, COALESCE(condition, ''),",
      "COALESCE(grade, '-1'::double precision) );",
    ].join(" "));
  });
});
