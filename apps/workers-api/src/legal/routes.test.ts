import { describe, expect, it } from "vitest";
import app from "../index";

describe("public legal routes", () => {
  it("serves Terms without authentication because app review and sign-in disclosures need a public URL", async () => {
    const response = await app.request("/api/v1/legal/terms");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toContain("text/html");
    expect(response.headers.get("x-frame-options")).toBe("DENY");
    expect(html).toContain("<title>Terms of Use | Card AI</title>");
    expect(html).toContain("CARD AI");
    expect(html).toContain("By using Card AI");
    expect(html).toContain("not financial, investment, appraisal, tax, or legal advice");
    expect(html).toContain("kando@tcgcard.fun");
  });

  it("discloses actual scan and collection processing because consent links must describe the production data flow", async () => {
    const response = await app.request("/api/v1/legal/privacy");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>Privacy Policy | Card AI</title>");
    expect(html).toContain("explains how Card AI handles information");
    expect(html).toContain("card images submitted for recognition");
    expect(html).toContain("Portfolio folders");
    expect(html).toContain("Cloudflare");
    expect(html).toContain("request account deletion");
  });
});
