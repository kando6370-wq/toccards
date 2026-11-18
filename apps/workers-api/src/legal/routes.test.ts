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
    expect(html).toContain("Version date: November 17, 2026");
    expect(html).toContain("By using Card AI");
    expect(html).toContain("separate platform accounts and personal data spaces");
    expect(html).toContain("We do not use your uploaded images or scan records for model training");
    expect(html).toContain("maximum of 10 cards in a scan batch");
    expect(html).toContain("current Android release provides its available features without subscriptions");
    expect(html).toContain("All billing, refunds, cancellations, and payment issues for App Store purchases are handled by Apple");
    expect(html).toContain("23.OPEN SOURCE AND MODEL LICENSES");
    expect(html).toContain("Apache License");
    expect(html).toContain("Microsoft ONNX Runtime 1.23.0");
    expect(html).toContain("support@tcgcard.fun");
    expect(html).not.toContain("kando@tcgcard.fun");
  });

  it("discloses actual scan and collection processing because consent links must describe the production data flow", async () => {
    const response = await app.request("/api/v1/legal/privacy");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>Privacy Policy | Card AI</title>");
    expect(html).toContain("Version date: November 17, 2026");
    expect(html).toContain("iOS and Android applications");
    expect(html).toContain("the image is uploaded to our server for identification");
    expect(html).toContain("do not use your uploaded images or scan records to train machine-learning or AI models");
    expect(html).toContain("do not request or collect precise GPS location");
    expect(html).toContain("current Android release has no subscriptions or in-app purchases");
    expect(html).toContain("separate platform accounts and personal data spaces");
    expect(html).toContain("does not automatically or immediately erase records already held in Firebase");
    expect(html).toContain("must register again");
    expect(html).toContain("does not cancel an Apple subscription");
    expect(html).toContain("<table>");
    expect(html).toContain("support@tcgcard.fun");
    expect(html).not.toContain("kando@tcgcard.fun");
  });

  it("serves public support instructions because store review needs a working support URL", async () => {
    const response = await app.request("/api/v1/legal/support");
    const html = await response.text();

    expect(response.status).toBe(200);
    expect(html).toContain("<title>Support | Card AI</title>");
    expect(html).toContain("Effective date: July 15, 2026");
    expect(html).toContain("Profile &gt; Account &gt; Delete account");
    expect(html).toContain("kando@tcgcard.fun");
    expect(html).toContain('/api/v1/legal/privacy');
  });
});
