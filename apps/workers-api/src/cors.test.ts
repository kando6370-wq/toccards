import { describe, expect, it } from "vitest";
import app from "./index";

describe("API CORS", () => {
  it("allows preflight requests from the production admin domain", async () => {
    const response = await app.request("/api/v1/health", {
      method: "OPTIONS",
      headers: {
        Origin: "https://admin.tcgcard.fun",
        "Access-Control-Request-Method": "GET",
        "Access-Control-Request-Headers": "authorization,content-type",
      },
    });

    expect(response.status).toBe(204);
    expect(response.headers.get("access-control-allow-origin")).toBe("https://admin.tcgcard.fun");
    expect(response.headers.get("access-control-allow-headers")).toContain("Authorization");
  });

  it("does not allow unrelated origins", async () => {
    const response = await app.request("/api/v1/health", {
      headers: { Origin: "https://example.com" },
    });

    expect(response.headers.get("access-control-allow-origin")).not.toBe("https://example.com");
  });
});
