import type { Env } from "../env";

export type MailMessage = {
  to: string;
  subject: string;
  html: string;
};

type ZeptoMailResponse = {
  request_id?: unknown;
};

export async function sendZeptoMail(
  env: Env,
  message: MailMessage,
  fetcher: typeof fetch = fetch,
): Promise<string> {
  const token = requiredConfig(env.ZEPTOMAIL_TOKEN, "ZEPTOMAIL_TOKEN");
  const apiUrl = requiredConfig(env.ZEPTOMAIL_API_URL, "ZEPTOMAIL_API_URL");
  const fromAddress = requiredConfig(
    env.MAIL_FROM_ADDRESS,
    "MAIL_FROM_ADDRESS",
  );
  const fromName = requiredConfig(env.MAIL_FROM_NAME, "MAIL_FROM_NAME");

  const response = await fetcher(apiUrl, {
    method: "POST",
    headers: {
      Authorization: `Zoho-enczapikey ${token}`,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: { address: fromAddress, name: fromName },
      to: [{ email_address: { address: message.to } }],
      subject: message.subject,
      htmlbody: message.html,
    }),
    signal: AbortSignal.timeout(8_000),
  });

  const body = (await response.json()) as ZeptoMailResponse;
  const requestId = stringValue(body.request_id);
  if (!response.ok || !requestId) {
    throw new Error(
      `ZeptoMail delivery request failed (HTTP ${response.status}, request ${requestId ?? "unknown"}).`,
    );
  }

  return requestId;
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
