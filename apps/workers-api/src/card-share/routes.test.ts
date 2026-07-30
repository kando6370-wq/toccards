import { Hono } from "hono";
import { describe, expect, it } from "vitest";
import type { Env } from "../env";
import { createCardShareRoutes } from "./routes";

describe("card share routes", () => {
  it("serves escaped Open Graph card metadata because social apps need a public HTML preview", async () => {
    const app = new Hono<{ Bindings: Env }>();
    app.route(
      "/",
      createCardShareRoutes({
        loadCard: async (_env, cardRef) => ({
          card_ref: cardRef,
          name: 'Switch <Rare> "Card"',
          set_name: "Deck & Exclusives",
          set_code: "PR",
          card_number: "92/109",
          finish: "Normal",
          language: "English",
          object_type: "tcg",
          image_url: "https://image.tcgcard.fun/cards/560537.jpg",
          rarity: "Common",
          price_usd: 0.27,
        }),
        loadStoreUrls: async () => ({
          ios: "https://apps.apple.com/app/kando/id123",
          android:
            "https://play.google.com/store/apps/details?id=com.kando.kandoApp.beta",
        }),
      }),
    );

    const response = await app.request(
      "https://api-dev.tcgcard.fun/share/cards/pokemon%3Asv3%3A125",
      {},
      {} as Env,
    );
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html");
    expect(response.headers.get("cache-control")).toBe("public, max-age=300");
    expect(html).toContain('<meta property="og:title" content="Switch &lt;Rare&gt; &quot;Card&quot;">');
    expect(html).toContain('<meta property="og:description" content="Deck &amp; Exclusives · Market price: $0.27">');
    expect(html).toContain('<meta property="og:image" content="https://image.tcgcard.fun/cards/560537.jpg">');
    expect(html).toContain("/share/cards/pokemon%3Asv3%3A125");
    expect(html).toContain("kando://app/cards/pokemon%3Asv3%3A125");
    expect(html).toContain("https://apps.apple.com/app/kando/id123");
    expect(html).toContain(
      "https://play.google.com/store/apps/details?id=com.kando.kandoApp.beta",
    );
    expect(html).not.toContain("Switch <Rare>");
  });

  it("returns an HTML 404 without indexing because missing cards must not create broken previews", async () => {
    const app = new Hono<{ Bindings: Env }>();
    app.route(
      "/",
      createCardShareRoutes({ loadCard: async () => null }),
    );

    const response = await app.request(
      "https://api-dev.tcgcard.fun/share/cards/missing",
      {},
      {} as Env,
    );

    expect(response.status).toBe(404);
    expect(response.headers.get("content-type")).toContain("text/html");
    expect(response.headers.get("x-robots-tag")).toBe("noindex");
  });
});
