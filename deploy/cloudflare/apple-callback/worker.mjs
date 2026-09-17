const CALLBACK_PATH = "/api/v1/apple/notifications/v2/sandbox";
const MAX_BODY_BYTES = 200_000;

export async function handleCallback(request, env, fetcher = fetch, timeoutMs = 10_000) {
  const url = new URL(request.url);
  if (url.pathname !== CALLBACK_PATH || url.search) return reply("NOT_FOUND", 404);
  if (request.method !== "POST") return reply("METHOD_NOT_ALLOWED", 405, { Allow: "POST" });

  let origin;
  try {
    origin = new URL(env.LINUX_CALLBACK_ORIGIN);
    if (!["http:", "https:"].includes(origin.protocol) || origin.username || origin.password ||
        origin.pathname !== "/" || origin.search || origin.hash) throw new Error("Invalid origin");
  } catch {
    return reply("CALLBACK_ORIGIN_NOT_CONFIGURED", 503);
  }

  if (Number(request.headers.get("Content-Length")) > MAX_BODY_BYTES) return reply("PAYLOAD_TOO_LARGE", 413);
  const chunks = [];
  let size = 0;
  const reader = request.body?.getReader();
  if (reader) {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_BODY_BYTES) {
          await reader.cancel();
          return reply("PAYLOAD_TOO_LARGE", 413);
        }
        chunks.push(value);
      }
    } catch {
      return reply("INVALID_REQUEST", 400);
    } finally {
      reader.releaseLock();
    }
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    const response = await fetcher(new URL(CALLBACK_PATH, origin).toString(), {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body,
      redirect: "manual",
      signal: AbortSignal.any([request.signal, AbortSignal.timeout(timeoutMs)]),
    });
    if (response.status >= 300 && response.status < 400) {
      await response.body?.cancel();
      return reply("CALLBACK_UPSTREAM_UNAVAILABLE", 502);
    }
    // Preserve Linux acknowledgement/failure so Apple can retry a failed delivery.
    const responseBody = await response.arrayBuffer();
    return new Response(responseBody.byteLength ? responseBody : null, {
      status: response.status,
      headers: { "Content-Type": response.headers.get("Content-Type") || "application/json", "Cache-Control": "no-store" },
    });
  } catch (error) {
    console.error("Apple callback upstream request failed", {
      name: error?.name,
      message: error?.message,
    });
    return reply("CALLBACK_UPSTREAM_UNAVAILABLE", 502);
  }
}

function reply(error, status, headers = {}) {
  return Response.json({ error }, { status, headers: { ...headers, "Cache-Control": "no-store" } });
}

export default { fetch: (request, env) => handleCallback(request, env) };
