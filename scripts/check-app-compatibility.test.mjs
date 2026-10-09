import assert from "node:assert/strict";
import test from "node:test";
import { validateBaselines } from "./check-app-compatibility.mjs";

const baseline = { version: "1.0.4", build: "161", tag: "v1.0.4", commit: "a".repeat(40) };
const valid = { schemaVersion: 1, evidence: "git-source-contracts-only", baselines: [baseline] };

test("source evidence cannot silently expand into production artifact acceptance", () => {
  assert.deepEqual(validateBaselines(valid), [baseline]);
  assert.throws(() => validateBaselines({ ...valid, evidence: "production-passed" }));
  assert.throws(() => validateBaselines({ ...valid, baselines: [] }));
});

test("marketing versions require pinned commits and cannot be duplicated for build-only changes", () => {
  for (const changed of [{ commit: "main" }, { tag: "dev" }, { version: "1.0.4+162" }, { build: "" }]) {
    assert.throws(() => validateBaselines({ ...valid, baselines: [{ ...baseline, ...changed }] }));
  }
  assert.throws(() => validateBaselines({ ...valid, baselines: [baseline, { ...baseline, build: "162" }] }));
});
