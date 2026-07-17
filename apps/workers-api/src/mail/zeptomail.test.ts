import { describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { sendZeptoMail } from "./zeptomail";

const env = {
  ZEPTOMAIL_TOKEN: "send-mail-token",
  ZEPTOMAIL_API_URL: "https://api.zeptomail.com/v1.1/email",
  MAIL_FROM_ADDRESS: "kando@tcgcard.fun",
  MAIL_FROM_NAME: "Kando",
} as Env;

describe("sendZeptoMail", () => {
  it("uses the verified domain and Send Mail token because verification emails must use the production agent", async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValue(Response.json({ request_id: "request-1" }));

    const requestId = await sendZeptoMail(
      env,
      {
        to: "person@example.com",
        subject: "Kando test",
        html: "<p>Connected</p>",
      },
      fetcher,
    );

    expect(requestId).toBe("request-1");
    expect(fetcher).toHaveBeenCalledOnce();
    const request = fetcher.mock.calls[0];
    expect(request?.[0]).toBe("https://api.zeptomail.com/v1.1/email");
    expect(request?.[1]?.headers).toEqual(
      expect.objectContaining({
        Authorization: "Zoho-enczapikey send-mail-token",
        Accept: "application/json",
      }),
    );
    expect(JSON.parse(request?.[1]?.body as string)).toEqual({
      from: { address: "kando@tcgcard.fun", name: "Kando" },
      to: [{ email_address: { address: "person@example.com" } }],
      subject: "Kando test",
      htmlbody: "<p>Connected</p>",
    });
  });

  it("fails loudly when the Send Mail token is missing", async () => {
    await expect(
      sendZeptoMail({ ...env, ZEPTOMAIL_TOKEN: undefined }, {
        to: "person@example.com",
        subject: "Kando test",
        html: "<p>Connected</p>",
      }),
    ).rejects.toThrow("ZEPTOMAIL_TOKEN is not configured.");
  });

  it("reports only safe delivery details when ZeptoMail rejects a request", async () => {
    const fetcher = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json(
        { request_id: "request-denied", message: "send-mail-token" },
        { status: 401 },
      ),
    );

    await expect(
      sendZeptoMail(
        env,
        {
          to: "person@example.com",
          subject: "Kando test",
          html: "<p>Connected</p>",
        },
        fetcher,
      ),
    ).rejects.toThrow(
      "ZeptoMail delivery request failed (HTTP 401, request request-denied).",
    );
  });
});
