import { afterEach, describe, expect, it, vi } from "vitest";
import { Hono } from "hono";
import app, { type Env } from "./index";
import { apiRequestId } from "./request-id";

const REQUEST_ID_HEADER = "X-Request-ID";
const REQUEST_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const CLIENT_REQUEST_ID = "123E4567-E89B-42D3-A456-426614174000";

describe("API request correlation", () => {
  afterEach(() => vi.restoreAllMocks());

  it("preserves a valid caller id in the response and structured completion log", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});

    const response = await app.request(
      "/api/v1/health?probe=correlation",
      { headers: { [REQUEST_ID_HEADER]: CLIENT_REQUEST_ID } },
      {} as Env,
    );

    expect(response.status).toBe(200);
    expect(response.headers.get(REQUEST_ID_HEADER)).toBe(CLIENT_REQUEST_ID);
    const entry = logs.mock.calls.find(([event]) => event === "api_request");
    expect(entry).toBeDefined();
    expect(JSON.parse(String(entry?.[1]))).toMatchObject({
      request_id: CLIENT_REQUEST_ID,
      method: "GET",
      path: "/api/v1/health",
      status: 200,
    });
    expect(JSON.parse(String(entry?.[1])).duration_ms).toEqual(expect.any(Number));
  });

  it("generates distinct UUID v4 ids when the caller id is missing or invalid", async () => {
    vi.spyOn(console, "info").mockImplementation(() => {});

    const missing = await app.request("/api/v1/health", {}, {} as Env);
    const invalid = await app.request(
      "/api/v1/health",
      { headers: { [REQUEST_ID_HEADER]: "not-a-uuid" } },
      {} as Env,
    );
    const notFound = await app.request("/api/v1/not-found", {}, {} as Env);
    const missingId = missing.headers.get(REQUEST_ID_HEADER) ?? "";
    const invalidId = invalid.headers.get(REQUEST_ID_HEADER) ?? "";

    expect(missingId).toMatch(REQUEST_ID_PATTERN);
    expect(invalidId).toMatch(REQUEST_ID_PATTERN);
    expect(invalidId).not.toBe(missingId);
    expect(notFound.status).toBe(404);
    expect(notFound.headers.get(REQUEST_ID_HEADER)).toMatch(REQUEST_ID_PATTERN);
  });

  it("allows and exposes the request id header for Admin browser requests", async () => {
    vi.spyOn(console, "info").mockImplementation(() => {});
    const origin = "http://localhost:3000";

    const preflight = await app.request(
      "/api/v1/health",
      {
        method: "OPTIONS",
        headers: {
          Origin: origin,
          "Access-Control-Request-Method": "GET",
          "Access-Control-Request-Headers": "authorization,x-request-id",
        },
      },
      {} as Env,
    );
    const response = await app.request(
      "/api/v1/health",
      { headers: { Origin: origin } },
      {} as Env,
    );

    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("Access-Control-Allow-Headers")).toContain(REQUEST_ID_HEADER);
    expect(response.headers.get("Access-Control-Expose-Headers")).toContain(REQUEST_ID_HEADER);
  });

  it("returns the request id on error responses so failed requests remain traceable", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});
    const failingApp = new Hono();
    failingApp.use("/api/v1/*", apiRequestId());
    failingApp.get("/api/v1/failure", () => {
      throw new Error("expected failure");
    });
    failingApp.onError((_error, context) => context.json({ error: "FAILED" }, 500));

    const response = await failingApp.request("/api/v1/failure");

    expect(response.status).toBe(500);
    expect(response.headers.get(REQUEST_ID_HEADER)).toMatch(REQUEST_ID_PATTERN);
    const entry = logs.mock.calls.find(([event]) => event === "api_request");
    expect(JSON.parse(String(entry?.[1]))).toMatchObject({ status: 500 });
  });

  it("logs the route template instead of user identifiers from path parameters", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});
    const tracedApp = new Hono();
    tracedApp.use("/api/v1/*", apiRequestId());
    tracedApp.get("/api/v1/admin/users/:uid", (context) => context.json({ ok: true }));

    await tracedApp.request("/api/v1/admin/users/sensitive-user-id?include=orders");

    const entry = logs.mock.calls.find(([event]) => event === "api_request");
    const completion = JSON.parse(String(entry?.[1]));
    expect(completion.path).toBe("/api/v1/admin/users/:uid");
    expect(String(entry?.[1])).not.toContain("sensitive-user-id");
    expect(String(entry?.[1])).not.toContain("include=orders");
  });

  it("does not add request correlation outside the business API", async () => {
    const logs = vi.spyOn(console, "info").mockImplementation(() => {});

    const response = await app.request("/not-an-api-route", {}, {} as Env);

    expect(response.status).toBe(404);
    expect(response.headers.has(REQUEST_ID_HEADER)).toBe(false);
    expect(logs).not.toHaveBeenCalledWith("api_request", expect.anything());
  });
});
