import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
} from "@kando/auth-core";
import { ulid } from "ulid";

export type CreatedUserSession = {
  sessionId: string;
  accessToken: string;
  refreshToken: string;
  hashedRefreshToken: string;
  expiresAt: string;
  expiresIn: number;
};

export async function createUserSessionValues(
  userId: string,
  jwtSecret: string,
  now: Date,
): Promise<CreatedUserSession> {
  const sessionId = ulid();
  const refreshToken = createRefreshToken();
  const hashedRefreshToken = await hashRefreshToken(refreshToken);
  const accessToken = await signAccessToken(
    { owner_type: "user", owner_id: userId, session_id: sessionId },
    jwtSecret,
    now,
  );

  return {
    sessionId,
    accessToken,
    refreshToken,
    hashedRefreshToken,
    expiresAt: refreshTokenExpiresAt(now),
    expiresIn: ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  };
}
