const crawlerUserAgent = /chatgpt-user|oai-searchbot|gptbot|perplexity-user|perplexitybot|claude-user|claude-searchbot|claudebot|bingbot|googlebot|applebot|duckduckbot|duckassistbot|yandexbot|meta-externalagent|bytespider/i;
const excludedPath = /^\/(?:(?:api|site-api|assets)(?:\/|$)|_)/;
const assetExtension = /\.(?!(?:html?|txt|xml|md)$)[a-z0-9]{1,8}$/i;

export type CrawlerReportingEnv = {
  PUBLIC_ORIGIN: string;
  PVUV_SITE?: string;
  PVUV_INGEST_TOKEN?: string;
};

type CrawlerHit = { ua: string; path: string; ip?: string; status: number; ts: number };

export function scheduleCrawlerHit(
  request: Request,
  status: number,
  { PUBLIC_ORIGIN, PVUV_SITE, PVUV_INGEST_TOKEN }: CrawlerReportingEnv,
  context: ExecutionContext,
): void {
  if (!PVUV_SITE || !PVUV_INGEST_TOKEN) return;
  if (request.method !== 'GET' && request.method !== 'HEAD') return;
  const userAgent = request.headers.get('User-Agent');
  if (!userAgent || !crawlerUserAgent.test(userAgent)) return;

  const url = new URL(request.url);
  if (url.origin !== PUBLIC_ORIGIN) return;
  let path: string;
  try {
    path = decodeURI(url.pathname);
  } catch {
    return;
  }
  if (excludedPath.test(path) || assetExtension.test(path)) return;

  context.waitUntil(reportCrawlerHit(PVUV_SITE, PVUV_INGEST_TOKEN, {
    ua: userAgent,
    path: url.pathname,
    ip: request.headers.get('CF-Connecting-IP') ?? undefined,
    status,
    ts: Date.now(),
  }));
}

async function reportCrawlerHit(site: string, token: string, hit: CrawlerHit): Promise<void> {
  try {
    const response = await fetch(`https://api.pvuv.ai/v1/sites/${encodeURIComponent(site)}/crawler_hits`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ hits: [hit] }),
      redirect: 'manual',
      signal: AbortSignal.timeout(3000),
    });
    await response.body?.cancel();
    if (!response.ok) console.warn({ event: 'pvuv_crawler_report_failed', status: response.status });
  } catch {
    console.warn({ event: 'pvuv_crawler_report_failed' });
  }
}
