import { describe, expect, it } from "vitest";
import { createId } from "./id";

describe("createId", () => {
  it("creates ULID-shaped ids with WebCrypto randomness so Workers runtime never needs Node crypto", () => {
    const id = createId(new Date(0));

    expect(id).toMatch(/^[0-9A-HJKMNP-TV-Z]{26}$/);
    expect(id.startsWith("0000000000")).toBe(true);
  });
});
