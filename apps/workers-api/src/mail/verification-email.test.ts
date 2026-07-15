import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import { sendZohoMail } from "./zoho-mail";
import { sendVerificationEmail } from "./verification-email";

vi.mock("./zoho-mail", () => ({
  sendZohoMail: vi.fn().mockResolvedValue("message-id"),
}));

const env = {} as Env;

describe("sendVerificationEmail", () => {
  beforeEach(() => {
    vi.mocked(sendZohoMail).mockClear();
  });

  it("renders the branded registration template because account creation codes must be recognizable and time bounded", async () => {
    await sendVerificationEmail(env, "collector@example.com", "081964", "register");

    expect(sendZohoMail).toHaveBeenCalledWith(
      env,
      expect.objectContaining({
        to: "collector@example.com",
        subject: "Kando - This Is Your Verification Code 081964",
        html: expect.stringContaining("Use this code to create your account."),
      }),
    );
    const message = vi.mocked(sendZohoMail).mock.calls[0]?.[1];
    expect(message?.html).toContain(">081964</td>");
    expect(message?.html).toContain("10 minutes");
    expect(message?.html).toContain("background-color:#10100b");
    expect(message?.html).not.toContain("Picks AI");
  });

  it("uses reset-specific copy because password recovery must not look like account registration", async () => {
    await sendVerificationEmail(
      env,
      "collector@example.com",
      "654321",
      "reset_password",
    );

    const message = vi.mocked(sendZohoMail).mock.calls[0]?.[1];
    expect(message?.html).toContain("Use this code to reset your password.");
    expect(message?.html).not.toContain("Use this code to create your account.");
  });
});
