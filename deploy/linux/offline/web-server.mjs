import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import http from "node:http";
import path from "node:path";

const webRoot = path.resolve(process.env.WEB_ROOT || "/srv");
const webPort = positiveInteger(process.env.WEB_PORT, 80);
const apiOrigin = new URL(process.env.API_ORIGIN || "http://api:3000");

const contentTypes = new Map([
  [".css", "text/css; charset=utf-8"],
  [".html", "text/html; charset=utf-8"],
  [".ico", "image/x-icon"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".map", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
  [".webp", "image/webp"],
  [".woff", "font/woff"],
  [".woff2", "font/woff2"],
]);

const server = http.createServer((request, response) => {
  void handleRequest(request, response).catch((error) => {
    console.error("Offline web request failed.", error);
    if (!response.headersSent) response.writeHead(500);
    response.end("Internal Server Error");
  });
});

server.listen(webPort, "0.0.0.0", () => {
  console.log(`Offline Linux web listening on http://0.0.0.0:${webPort}`);
});

async function handleRequest(request, response) {
  const requestUrl = new URL(request.url || "/", "http://localhost");
  if (isApiPath(requestUrl.pathname)) {
    proxyRequest(request, response);
    return;
  }

  if (request.method !== "GET" && request.method !== "HEAD") {
    response.writeHead(405, { Allow: "GET, HEAD" });
    response.end();
    return;
  }

  const requestedPath = safePath(requestUrl.pathname);
  const filePath = await regularFile(requestedPath)
    ? requestedPath
    : path.join(webRoot, "index.html");
  const fileStat = await stat(filePath);
  const headers = {
    "Content-Length": fileStat.size,
    "Content-Type": contentTypes.get(path.extname(filePath)) || "application/octet-stream",
  };

  response.writeHead(200, headers);
  if (request.method === "HEAD") {
    response.end();
    return;
  }
  createReadStream(filePath).pipe(response);
}

function proxyRequest(request, response) {
  const upstream = http.request(
    {
      hostname: apiOrigin.hostname,
      port: apiOrigin.port || 80,
      method: request.method,
      path: request.url,
      headers: { ...request.headers, host: apiOrigin.host },
    },
    (upstreamResponse) => {
      response.writeHead(upstreamResponse.statusCode || 502, upstreamResponse.headers);
      upstreamResponse.pipe(response);
    },
  );
  upstream.on("error", (error) => {
    console.error("Offline web proxy failed.", error);
    if (!response.headersSent) response.writeHead(502);
    response.end("Bad Gateway");
  });
  request.pipe(upstream);
}

function isApiPath(pathname) {
  return pathname === "/api" || pathname.startsWith("/api/")
    || pathname === "/share" || pathname.startsWith("/share/");
}

function safePath(pathname) {
  const decodedPath = decodeURIComponent(pathname);
  const resolvedPath = path.resolve(webRoot, `.${decodedPath}`);
  if (resolvedPath !== webRoot && !resolvedPath.startsWith(`${webRoot}${path.sep}`)) {
    throw new Error("Requested path escapes the web root");
  }
  return resolvedPath;
}

async function regularFile(filePath) {
  try {
    return (await stat(filePath)).isFile();
  } catch (error) {
    if (error?.code === "ENOENT" || error?.code === "ENOTDIR") return false;
    throw error;
  }
}

function positiveInteger(value, fallback) {
  if (!value) return fallback;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error("WEB_PORT must be a positive integer");
  }
  return parsed;
}
