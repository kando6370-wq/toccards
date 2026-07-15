import type { Env } from "../env";
import { sendZohoMail } from "./zoho-mail";

export function sendVerificationEmail(
  env: Env,
  email: string,
  code: string,
  purpose: "register" | "reset_password",
): Promise<string> {
  const action =
    purpose === "register" ? "create your account" : "reset your password";
  return sendZohoMail(env, {
    to: email,
    subject: `Kando - This Is Your Verification Code ${code}`,
    html: verificationEmailHtml(code, action),
  });
}

function verificationEmailHtml(code: string, action: string): string {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="dark">
  <meta name="supported-color-schemes" content="dark">
  <title>Kando verification code</title>
</head>
<body style="margin:0;padding:0;background-color:#10100b;color:#eeecd8;font-family:Arial,Helvetica,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">Use ${code} to ${action}. This code expires in 10 minutes.</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background-color:#10100b;">
    <tr>
      <td align="center" style="padding:28px 16px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;background-color:#1a1c14;border:1px solid #464835;border-radius:12px;">
          <tr>
            <td align="center" style="padding:30px 32px 16px;">
              <div style="font-family:Georgia,'Times New Roman',serif;font-size:30px;line-height:36px;font-weight:700;color:#eeecd8;">Kando</div>
              <div style="padding-top:6px;font-size:14px;line-height:20px;color:#c7c8b0;">Your TCG collection companion</div>
            </td>
          </tr>
          <tr>
            <td style="padding:18px 32px 32px;">
              <h1 style="margin:0 0 8px;font-size:22px;line-height:28px;font-weight:700;color:#eeecd8;">Your verification code</h1>
              <p style="margin:0 0 24px;font-size:15px;line-height:22px;color:#c7c8b0;">Use this code to ${action}.</p>
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background-color:#10100b;border:1px solid #464835;border-radius:10px;">
                <tr>
                  <td align="center" style="padding:24px 12px;font-size:34px;line-height:40px;font-weight:700;letter-spacing:8px;color:#f0fe6f;">${code}</td>
                </tr>
              </table>
              <p style="margin:18px 0 0;font-size:14px;line-height:22px;color:#eeecd8;">This code will be valid for the next <strong style="color:#f0fe6f;">10 minutes</strong>. If you didn't request this code, you can safely ignore this email.</p>
              <div style="height:1px;margin:22px 0 18px;background-color:#464835;"></div>
              <p style="margin:0 0 6px;font-size:12px;line-height:18px;color:#c7c8b0;">&bull; This verification code works only for your current request.</p>
              <p style="margin:0 0 6px;font-size:12px;line-height:18px;color:#c7c8b0;">&bull; Do not share this code with anyone.</p>
              <p style="margin:0;font-size:12px;line-height:18px;color:#c7c8b0;">&bull; You received this email because your address was used in Kando.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}
