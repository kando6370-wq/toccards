import { describe, expect, it } from "vitest";
import { cardImageUrl } from "./card-image-url";

describe("cardImageUrl", () => {
  it("uses transformed R2 variants for display and the unmodified master for exact image work", () => {
    expect(cardImageUrl("93", "thumbnail")).toContain(
      "/cdn-cgi/image/width=160,height=224,fit=scale-down,quality=60,format=auto,dpr=2/cards/93.jpg",
    );
    expect(cardImageUrl("93", "list")).toContain(
      "/cdn-cgi/image/width=360,height=504,fit=scale-down,quality=75,format=auto/cards/93.jpg",
    );
    expect(cardImageUrl("93", "detail")).toContain(
      "/cdn-cgi/image/width=600,height=800,fit=scale-down,quality=85,format=auto,sharpen=1/cards/93.jpg",
    );
    expect(cardImageUrl("93", "preview")).toContain(
      "/cdn-cgi/image/width=1600,fit=scale-down,quality=92,format=auto/cards/93.jpg",
    );
    expect(cardImageUrl("93", "master")).toBe(
      "https://image.tcgcard.fun/cards/93.jpg",
    );
  });
});
