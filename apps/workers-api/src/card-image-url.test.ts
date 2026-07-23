import { describe, expect, it } from "vitest";
import { cardImageUrl } from "./card-image-url";

describe("cardImageUrl", () => {
  it("uses the canonical card image URL for every display context", () => {
    for (const variant of ["thumbnail", "list", "detail", "preview", "master"] as const) {
      expect(cardImageUrl("93", variant)).toBe("https://image.tcgcard.fun/cards/93.jpg");
    }
  });
});
