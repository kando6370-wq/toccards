import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const CALLBACK_PATH = "/api/v1/apple/notifications/v2/sandbox";
const MAX_BODY_BYTES = 200_000;

export function createCallbackGateway({ origin = "http://127.0.0.1:8080", timeoutMs = 8_000 } = {}) {
  const upstream = new URL(origin);
  if (upstream.protocol !== "http:" || upstream.username || upstream.password ||
      upstream.pathname !== "/" || upstream.search || upstream.hash) {
    throw new Error("Callback upstream must be a fixed HTTP origin");
  }

  return http.createServer((request, response) => {
    void handleRequest(request, response, upstream, timeoutMs).catch((error) => {
      console.error("Callback gateway upstream failed", { name: error.name });
      if (!response.headersSent) reply(response, 502, "CALLBACK_UPSTREAM_UNAVAILABLE");
      else response.destroy();
    });
  });
}

async function handleRequest(request, response, origin, timeoutMs) {
  if (request.url !== CALLBACK_PATH) return reply(response, 404, "NOT_FOUND");
  if (request.method !== "POST") return reply(response, 405, "METHOD_NOT_ALLOWED", { Allow: "POST" });

  if (Number(request.headers["content-length"]) > MAX_BODY_BYTES) {
    return reply(response, 413, "PAYLOAD_TOO_LARGE");
  }
  const chunks = [];
  let size = 0;
  try {
    for await (const chunk of request) {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) return reply(response, 413, "PAYLOAD_TOO_LARGE");
      chunks.push(chunk);
    }
  } catch {
    return reply(response, 400, "INVALID_REQUEST");
  }

  const result = await fetch(new URL(CALLBACK_PATH, origin), {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: Buffer.concat(chunks, size),
    redirect: "manual",
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (result.status >= 300 && result.status < 400) {
    await result.body?.cancel();
    return reply(response, 502, "CALLBACK_UPSTREAM_UNAVAILABLE");
  }
  const body = Buffer.from(await result.arrayBuffer());
  response.writeHead(result.status, {
    "Content-Type": result.headers.get("Content-Type") || "application/json",
    "Cache-Control": "no-store",
  });
  response.end(body);
}

function reply(response, status, error, headers = {}) {
  response.writeHead(status, { ...headers, "Content-Type": "application/json", "Cache-Control": "no-store" });
  response.end(JSON.stringify({ error }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.CALLBACK_GATEWAY_PORT ?? "8081");
  if (!Number.isSafeInteger(port) || port < 1 || port > 65535) throw new Error("Invalid callback gateway port");
  createCallbackGateway().listen(port, "0.0.0.0", () => {
    console.log(`Callback-only gateway listening on port ${port}`);
  });
}
