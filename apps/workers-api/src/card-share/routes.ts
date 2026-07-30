import { Hono } from "hono";
import type { Env } from "../env";
import type { CardSearchResult } from "../data-source/adapter";
import {
  createDefaultAdapter,
  resolveCard,
  withCardImageUrl,
} from "../data-source/routes";

type CardShareLoader = (
  env: Env,
  cardRef: string,
) => Promise<CardSearchResult | null>;

type CardShareRoutesOptions = {
  loadCard?: CardShareLoader;
  loadStoreUrls?: (env: Env) => Promise<StoreUrls>;
};

type StoreUrls = {
  ios: string | null;
  android: string | null;
};

type AppConfigRow = { key: string; value: string };

const SHARE_HEADERS = {
  "Cache-Control": "public, max-age=300",
  "Content-Security-Policy":
    "default-src 'none'; img-src https://image.tcgcard.fun; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
  "X-Frame-Options": "DENY",
} as const;

export function createCardShareRoutes(
  options: CardShareRoutesOptions = {},
): Hono<{ Bindings: Env }> {
  const routes = new Hono<{ Bindings: Env }>();
  const loadCard = options.loadCard ?? loadShareCard;
  const loadStoreUrls = options.loadStoreUrls ?? loadConfiguredStoreUrls;

  routes.get("/share/cards/:card_ref", async (c) => {
    const cardRef = decodeCardRef(c.req.param("card_ref"));
    const card = await loadCard(c.env, cardRef);
    if (!card) {
      return c.html(notFoundPage(), 404, {
        ...SHARE_HEADERS,
        "X-Robots-Tag": "noindex",
      });
    }

    const requestUrl = new URL(c.req.url);
    const canonicalUrl = new URL(
      `/share/cards/${encodeURIComponent(card.card_ref)}`,
      requestUrl.origin,
    ).toString();
    const storeUrls = await loadStoreUrls(c.env);
    return c.html(
      cardSharePage(card, canonicalUrl, storeUrls),
      200,
      SHARE_HEADERS,
    );
  });

  return routes;
}

async function loadShareCard(
  env: Env,
  cardRef: string,
): Promise<CardSearchResult | null> {
  const card = await resolveCard(env.DB, createDefaultAdapter(env), cardRef);
  return card ? withCardImageUrl(card, "detail") : null;
}

function cardSharePage(
  card: CardSearchResult,
  canonicalUrl: string,
  storeUrls: StoreUrls,
): string {
  const name = escapeHtml(card.name);
  const setName = escapeHtml(card.set_name);
  const imageUrl = escapeHtml(card.image_url ?? "");
  const price = formatPrice(card.price_usd);
  const description = escapeHtml(
    [card.set_name, price && `Market price: ${price}`]
      .filter(Boolean)
      .join(" · "),
  );
  const safeCanonicalUrl = escapeHtml(canonicalUrl);
  const appUrl = escapeHtml(
    `kando://app/cards/${encodeURIComponent(card.card_ref)}`,
  );
  const iosStoreUrl = escapeHtml(storeUrls.ios ?? "");
  const androidStoreUrl = escapeHtml(storeUrls.android ?? "");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${name} | Kando</title>
  <link rel="canonical" href="${safeCanonicalUrl}">
  <meta name="description" content="${description}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Kando">
  <meta property="og:title" content="${name}">
  <meta property="og:description" content="${description}">
  <meta property="og:image" content="${imageUrl}">
  <meta property="og:url" content="${safeCanonicalUrl}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${name}">
  <meta name="twitter:description" content="${description}">
  <meta name="twitter:image" content="${imageUrl}">
  <style>
    :root { color-scheme: dark; font-family: Inter, Arial, sans-serif; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px; background: #0d0f09; color: #f4f5ed; }
    main { width: min(420px, 100%); }
    .brand { margin-bottom: 18px; color: #efff68; font-size: 15px; font-weight: 700; }
    article { display: grid; grid-template-columns: minmax(120px, 42%) 1fr; gap: 20px; align-items: center; border: 1px solid #34372d; padding: 18px; background: #1b1e18; border-radius: 8px; }
    img { display: block; width: 100%; aspect-ratio: 745 / 1043; object-fit: contain; border-radius: 6px; background: #10120d; }
    h1 { margin: 0 0 10px; font-size: 22px; line-height: 1.2; }
    p { margin: 5px 0; color: #bdc1b5; font-size: 14px; line-height: 1.45; }
    .price { color: #efff68; font-size: 18px; font-weight: 700; }
    button { width: 100%; min-height: 48px; margin-top: 16px; border: 0; border-radius: 8px; background: #efff68; color: #11140d; font: inherit; font-weight: 700; cursor: pointer; }
    button[hidden] { display: none; }
  </style>
</head>
<body>
  <main>
    <div class="brand">KANDO</div>
    <article>
      <img src="${imageUrl}" alt="${name}">
      <div><h1>${name}</h1><p>${setName}</p>${price ? `<p class="price">${escapeHtml(price)}</p>` : ""}</div>
    </article>
    <button id="open-app" data-app-url="${appUrl}" data-ios-store="${iosStoreUrl}" data-android-store="${androidStoreUrl}">Open in Kando</button>
  </main>
  <script>
    (() => {
      const button = document.getElementById('open-app');
      const userAgent = navigator.userAgent || '';
      const storeUrl = /android/i.test(userAgent)
        ? button.dataset.androidStore
        : /iPad|iPhone|iPod/i.test(userAgent)
          ? button.dataset.iosStore
          : '';
      if (!storeUrl) button.hidden = true;
      button.addEventListener('click', () => {
        let leftPage = false;
        const markLeft = () => { if (document.hidden) leftPage = true; };
        document.addEventListener('visibilitychange', markLeft, { once: true });
        window.location.href = button.dataset.appUrl;
        window.setTimeout(() => {
          if (!leftPage && !document.hidden) window.location.href = storeUrl;
        }, 1500);
      });
    })();
  </script>
</body>
</html>`;
}

async function loadConfiguredStoreUrls(env: Env): Promise<StoreUrls> {
  try {
    const { results = [] } = await env.DB.prepare(
      "SELECT key, value FROM app_config WHERE key IN ('admin.app_version.ios', 'admin.app_version.google', 'app_store_url')",
    ).all<AppConfigRow>();
    const configs = new Map(results.map((row) => [row.key, row.value]));
    const fallback = validWebUrl(configs.get("app_store_url"));
    return {
      ios: adminStoreUrl(configs.get("admin.app_version.ios")) ?? fallback,
      android:
        adminStoreUrl(configs.get("admin.app_version.google")) ?? fallback,
    };
  } catch {
    return { ios: null, android: null };
  }
}

function adminStoreUrl(value: string | undefined): string | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(value) as unknown;
    if (!isRecord(parsed)) return null;
    return validWebUrl(parsed.store_url);
  } catch {
    return null;
  }
}

function validWebUrl(value: unknown): string | null {
  if (typeof value !== "string") return null;
  try {
    const url = new URL(value.trim());
    return url.protocol === "https:" || url.protocol === "http:"
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function notFoundPage(): string {
  return "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"robots\" content=\"noindex\"><title>Card not found | Kando</title></head><body><h1>Card not found</h1></body></html>";
}

function formatPrice(value: number | undefined): string | null {
  return typeof value === "number" && Number.isFinite(value)
    ? new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
      }).format(value)
    : null;
}

function decodeCardRef(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => {
    return {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[character]!;
  });
}
