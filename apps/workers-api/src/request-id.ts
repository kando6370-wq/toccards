import type { MiddlewareHandler } from "hono";
import { routePath } from "hono/route";

export const REQUEST_ID_HEADER = "X-Request-ID";

const REQUEST_ID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function apiRequestId(): MiddlewareHandler {
  return async (context, next) => {
    const supplied = context.req.header(REQUEST_ID_HEADER)?.trim();
    const requestId = supplied && REQUEST_ID_PATTERN.test(supplied)
      ? supplied
      : crypto.randomUUID();
    const startedAt = performance.now();
    let failed = false;

    try {
      await next();
    } catch (error) {
      failed = true;
      throw error;
    } finally {
      context.header(REQUEST_ID_HEADER, requestId);
      console.info("api_request", JSON.stringify({
        request_id: requestId,
        method: context.req.method,
        path: completionPath(context),
        status: failed ? 500 : context.res.status,
        duration_ms: Math.max(0, Math.round(performance.now() - startedAt)),
      }));
    }
  };
}

function completionPath(context: Parameters<MiddlewareHandler>[0]): string {
  const matchedPath = routePath(context, -1);
  return matchedPath && !matchedPath.endsWith("*")
    ? matchedPath
    : "/api/v1/*";
}
