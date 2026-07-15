import { describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { sendZohoMail } from "./zoho-mail";

const env = {
  ZOHO_CLIENT_ID: "client-id",
  ZOHO_CLIENT_SECRET: "client-secret",
  ZOHO_REFRESH_TOKEN: "refresh-token",
  ZOHO_ACCOUNT_ID: "account-id",
  ZOHO_FROM_ADDRESS: "kando@tcgcard.fun",
} as Env;

describe("sendZohoMail", () => {
  it("refreshes OAuth and sends through the configured mailbox", async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        Response.json({ access_token: "access-token", expires_in: 3600 }),
      )
      .mockResolvedValueOnce(
        Response.json({
          status: { code: 200, description: "success" },
          data: { messageId: "message-1" },
        }),
      );

    const messageId = await sendZohoMail(
      env,
      {
        to: "person@example.com",
        subject: "Kando test",
        html: "<p>Connected</p>",
      },
      fetcher,
    );

    expect(messageId).toBe("message-1");
    expect(fetcher).toHaveBeenCalledTimes(2);
    const tokenRequest = fetcher.mock.calls[0];
    expect(tokenRequest?.[0]).toBe(
      "https://accounts.zoho.com/oauth/v2/token",
    );
    expect(tokenRequest?.[1]?.body?.toString()).toContain(
      "grant_type=refresh_token",
    );
    const sendRequest = fetcher.mock.calls[1];
    expect(sendRequest?.[0]).toBe(
      "https://mail.zoho.com/api/accounts/account-id/messages",
    );
    expect(sendRequest?.[1]?.headers).toEqual(
      expect.objectContaining({ Authorization: "Zoho-oauthtoken access-token" }),
    );
    expect(JSON.parse(sendRequest?.[1]?.body as string)).toEqual({
      fromAddress: "kando@tcgcard.fun",
      toAddress: "person@example.com",
      subject: "Kando test",
      content: "<p>Connected</p>",
      mailFormat: "html",
    });
  });

  it("fails loudly when a required secret is missing", async () => {
    await expect(
      sendZohoMail({ ...env, ZOHO_REFRESH_TOKEN: undefined }, {
        to: "person@example.com",
        subject: "Kando test",
        html: "<p>Connected</p>",
      }),
    ).rejects.toThrow("ZOHO_REFRESH_TOKEN is not configured.");
  });

  it("does not send when refreshing OAuth fails", async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValue(Response.json({ error: "invalid_code" }, { status: 400 }));

    await expect(
      sendZohoMail(env, {
        to: "person@example.com",
        subject: "Kando test",
        html: "<p>Connected</p>",
      }, fetcher),
    ).rejects.toThrow("Zoho access token refresh failed.");
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it("reports Zoho delivery details because production failures must be diagnosable without exposing secrets", async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json({ access_token: "access-token" }))
      .mockResolvedValueOnce(
        Response.json(
          { status: { code: 401, description: "Invalid OAuth scope" } },
          { status: 401 },
        ),
      );

    await expect(
      sendZohoMail(
        env,
        {
          to: "person@example.com",
          subject: "Kando test",
          html: "<p>Connected</p>",
        },
        fetcher,
      ),
    ).rejects.toThrow(
      "Zoho email delivery request failed (HTTP 401, Zoho 401: Invalid OAuth scope).",
    );
  });
});
