import type { Hono } from "hono";
import type { Env } from "../env";
import {
  completeOAuthAccountFlow,
  isGuestAccountUnavailableError,
  isOAuthAuthorizationFailedError,
} from "./account-flow";
import { hasSigningSecret } from "./http-auth";
import {
  resolveAppleIdentity,
  resolveGoogleIdentity,
} from "./oauth-provider";

type GoogleOAuthCallbackInput = {
  code: string | null;
  redirectUri: string | null;
  anonymousId: string | null;
};

type AppleOAuthCallbackInput = {
  code: string | null;
  idToken: string | null;
  anonymousId: string | null;
};

const AUTHORIZATION_FAILED_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Authorization failed. Please try again.",
  },
} as const;

const INTERNAL_ERROR_RESPONSE = {
  success: false,
  error: {
    code: "INTERNAL_ERROR",
    message: "Something went wrong. Please try again.",
  },
} as const;

const STALE_ANONYMOUS_ACCOUNT_RESPONSE = {
  success: false,
  error: {
    code: "VALIDATION_ERROR",
    message: "Guest account is no longer available.",
  },
} as const;

export function registerOAuthRoutes(routes: Hono<{ Bindings: Env }>): void {
  routes.post("/oauth/google/callback", async (c) => {
    const input = await readGoogleOAuthCallbackInput(c.req);
    const identity = await resolveGoogleIdentity(
      { code: input.code, redirectUri: input.redirectUri },
      c.env.GOOGLE_CLIENT_ID,
    );

    if (!identity) {
      return c.json(AUTHORIZATION_FAILED_RESPONSE, 422);
    }

    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const result = await completeOAuthAccountFlow(
        c.env.DB,
        identity,
        c.env.JWT_SECRET,
        input.anonymousId,
        c.req.header("Authorization"),
        new Date(),
      );

      return c.json({
        success: true,
        data: {
          user_id: result.userId,
          email: identity.email,
          login_method: identity.provider,
          access_token: result.session.accessToken,
          refresh_token: result.session.refreshToken,
          expires_in: result.session.expiresIn,
          is_new_user: result.isNewUser,
          migrated: result.migrated,
        },
      });
    } catch (error) {
      if (isOAuthAuthorizationFailedError(error)) {
        return c.json(AUTHORIZATION_FAILED_RESPONSE, 422);
      }

      if (isGuestAccountUnavailableError(error)) {
        return c.json(STALE_ANONYMOUS_ACCOUNT_RESPONSE, 422);
      }

      console.error("Failed to complete Google OAuth callback.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });

  routes.post("/oauth/apple/callback", async (c) => {
    const input = await readAppleOAuthCallbackInput(c.req);
    const identity = await resolveAppleIdentity(
      { code: input.code, idToken: input.idToken },
      c.env.APPLE_CLIENT_ID,
    );

    if (!identity) {
      return c.json(AUTHORIZATION_FAILED_RESPONSE, 422);
    }

    if (!hasSigningSecret(c.env.JWT_SECRET)) {
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }

    try {
      const result = await completeOAuthAccountFlow(
        c.env.DB,
        identity,
        c.env.JWT_SECRET,
        input.anonymousId,
        c.req.header("Authorization"),
        new Date(),
      );

      return c.json({
        success: true,
        data: {
          user_id: result.userId,
          email: identity.email,
          login_method: identity.provider,
          access_token: result.session.accessToken,
          refresh_token: result.session.refreshToken,
          expires_in: result.session.expiresIn,
          is_new_user: result.isNewUser,
          migrated: result.migrated,
        },
      });
    } catch (error) {
      if (isOAuthAuthorizationFailedError(error)) {
        return c.json(AUTHORIZATION_FAILED_RESPONSE, 422);
      }

      if (isGuestAccountUnavailableError(error)) {
        return c.json(STALE_ANONYMOUS_ACCOUNT_RESPONSE, 422);
      }

      console.error("Failed to complete Apple OAuth callback.", error);
      return c.json(INTERNAL_ERROR_RESPONSE, 500);
    }
  });
}

async function readGoogleOAuthCallbackInput(request: {
  json(): Promise<unknown>;
}): Promise<GoogleOAuthCallbackInput> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { code: null, redirectUri: null, anonymousId: null };
  }

  const rawCode =
    body && typeof body === "object"
      ? (body as { code?: unknown }).code
      : undefined;
  const rawRedirectUri =
    body && typeof body === "object"
      ? (body as { redirect_uri?: unknown }).redirect_uri
      : undefined;
  const rawAnonymousId =
    body && typeof body === "object"
      ? (body as { anonymous_id?: unknown }).anonymous_id
      : undefined;

  return {
    code: trimString(rawCode),
    redirectUri: trimString(rawRedirectUri),
    anonymousId: trimString(rawAnonymousId),
  };
}

async function readAppleOAuthCallbackInput(request: {
  json(): Promise<unknown>;
}): Promise<AppleOAuthCallbackInput> {
  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return { code: null, idToken: null, anonymousId: null };
  }

  const rawCode =
    body && typeof body === "object"
      ? (body as { code?: unknown }).code
      : undefined;
  const rawIdToken =
    body && typeof body === "object"
      ? (body as { id_token?: unknown }).id_token
      : undefined;
  const rawAnonymousId =
    body && typeof body === "object"
      ? (body as { anonymous_id?: unknown }).anonymous_id
      : undefined;

  return {
    code: trimString(rawCode),
    idToken: trimString(rawIdToken),
    anonymousId: trimString(rawAnonymousId),
  };
}

function trimString(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const trimmed = value.trim();

  return trimmed.length > 0 ? trimmed : null;
}
