import type { Env } from "../env";

export type MailMessage = {
  to: string;
  subject: string;
  html: string;
};

type ZohoTokenResponse = {
  access_token?: unknown;
};

type ZohoSendResponse = {
  status?: { code?: unknown; description?: unknown };
  data?: { messageId?: unknown };
};

export async function sendZohoMail(
  env: Env,
  message: MailMessage,
  fetcher: typeof fetch = fetch,
): Promise<string> {
  const clientId = requiredConfig(env.ZOHO_CLIENT_ID, "ZOHO_CLIENT_ID");
  const clientSecret = requiredConfig(
    env.ZOHO_CLIENT_SECRET,
    "ZOHO_CLIENT_SECRET",
  );
  const refreshToken = requiredConfig(
    env.ZOHO_REFRESH_TOKEN,
    "ZOHO_REFRESH_TOKEN",
  );
  const accountId = requiredConfig(env.ZOHO_ACCOUNT_ID, "ZOHO_ACCOUNT_ID");
  const fromAddress = requiredConfig(
    env.ZOHO_FROM_ADDRESS,
    "ZOHO_FROM_ADDRESS",
  );

  const tokenResponse = await fetcher(
    "https://accounts.zoho.com/oauth/v2/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: "refresh_token",
      }),
    },
  );
  const tokenBody = (await tokenResponse.json()) as ZohoTokenResponse;
  const accessToken = stringValue(tokenBody.access_token);
  if (!tokenResponse.ok || !accessToken) {
    throw new Error("Zoho access token refresh failed.");
  }

  const sendResponse = await fetcher(
    `https://mail.zoho.com/api/accounts/${encodeURIComponent(accountId)}/messages`,
    {
      method: "POST",
      headers: {
        Authorization: `Zoho-oauthtoken ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fromAddress,
        toAddress: message.to,
        subject: message.subject,
        content: message.html,
        mailFormat: "html",
      }),
    },
  );
  const sendBody = (await sendResponse.json()) as ZohoSendResponse;
  const messageId = stringValue(sendBody.data?.messageId);
  if (!sendResponse.ok || sendBody.status?.code !== 200 || !messageId) {
    throw new Error("Zoho email delivery request failed.");
  }

  return messageId;
}

function requiredConfig(value: unknown, name: string): string {
  const configured = stringValue(value);
  if (!configured) throw new Error(`${name} is not configured.`);
  return configured;
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}
