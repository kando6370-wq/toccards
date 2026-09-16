import { createServer, type RequestListener, type Server } from "node:http";
import { afterEach, describe, expect, it, vi } from "vitest";

import { createHttpVectorRecognition } from "./vector-recognition";

const bindingUrl = "https://recognize-vec.internal/recognize";
const request = {
  method: "POST",
  headers: { Accept: "application/json", "Content-Type": "application/json" },
  body: JSON.stringify({ vector: [1, ...Array(511).fill(0)] }),
};
const servers: Server[] = [];

describe("Linux HTTP vector recognition", () => {
  afterEach(async () => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    await Promise.all(servers.splice(0).map((server) => new Promise<void>((resolve) => {
      server.close(() => resolve());
      server.closeAllConnections();
    })));
  });

  it("sends the vector request to the configured recognition origin instead of the Workers-only binding address", async () => {
    const candidates = [{ product_id: "10738", confidence: 92.125 }];
    const upstream = vi.fn().mockResolvedValue(Response.json({ candidates }));
    vi.stubGlobal("fetch", upstream);

    const response = await createHttpVectorRecognition("https://recognize-vec.tcgcard.fun/")
      .fetch(bindingUrl, request);

    expect(upstream).toHaveBeenCalledExactlyOnceWith(
      "https://recognize-vec.tcgcard.fun/recognize",
      expect.objectContaining(request),
    );
    expect(await response.json()).toEqual({ candidates });
  });

  it.each([
    "not-a-url",
    "file:///recognize",
    "https://user:password@example.com",
    "https://example.com/api/v1/scan",
    "https://example.com?token=secret",
    "https://example.com#recognize",
  ])("rejects invalid service configuration %s before any request can go to the wrong endpoint", (baseUrl) => {
    expect(() => createHttpVectorRecognition(baseUrl))
      .toThrow("VECTOR_RECOGNITION_BASE_URL must be an HTTP(S) origin");
  });

  it("preserves an upstream error so the shared scan route can release the reservation", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(Response.json(
      { error: "recognition_unavailable" },
      { status: 503 },
    )));

    const response = await createHttpVectorRecognition("https://recognize-vec.tcgcard.fun")
      .fetch(bindingUrl, request);

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "recognition_unavailable" });
  });

  it("aborts a stalled HTTP request so a scan cannot hold its reservation indefinitely", async () => {
    const origin = await listen(() => {});
    const recognition = createHttpVectorRecognition(origin, 30);

    await expect(recognition.fetch(bindingUrl, request))
      .rejects.toMatchObject({ name: "TimeoutError" });
  });

  it("keeps the deadline attached after response headers so a stalled JSON body is also cancellable", async () => {
    const controller = new AbortController();
    const timeout = vi.spyOn(AbortSignal, "timeout").mockReturnValue(controller.signal);
    const origin = await listen((_request, response) => {
      response.setHeader("Content-Type", "application/json");
      response.flushHeaders();
    });

    const response = await createHttpVectorRecognition(origin).fetch(bindingUrl, request);
    const body = response.json();
    const rejectedBody = expect(body).rejects.toBeInstanceOf(Error);
    controller.abort(new DOMException("Recognition timed out", "TimeoutError"));

    await rejectedBody;
    expect(timeout).toHaveBeenCalledWith(10_000);
  });

  it("preserves caller cancellation instead of replacing it with only the transport deadline", async () => {
    const controller = new AbortController();
    const origin = await listen(() => {});
    const response = createHttpVectorRecognition(origin)
      .fetch(bindingUrl, { ...request, signal: controller.signal });
    const rejectedResponse = expect(response).rejects.toMatchObject({ name: "AbortError" });
    controller.abort();

    await rejectedResponse;
  });

  it("rejects redirects so recognition data cannot be forwarded to another endpoint", async () => {
    let redirectedRequests = 0;
    const origin = await listen((request, response) => {
      if (request.url === "/recognize") {
        response.writeHead(307, { Location: "/elsewhere" });
        response.end();
        return;
      }
      redirectedRequests += 1;
      response.end(JSON.stringify({ candidates: [] }));
    });

    await expect(createHttpVectorRecognition(origin).fetch(bindingUrl, request)).rejects.toThrow();
    expect(redirectedRequests).toBe(0);
  });
});

async function listen(handler: RequestListener): Promise<string> {
  const server = createServer(handler);
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("Expected a TCP server address");
  return `http://127.0.0.1:${address.port}`;
}
