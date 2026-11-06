import {
  ACCESS_TOKEN_EXPIRES_IN_SECONDS,
  createRefreshToken,
  hashRefreshToken,
  refreshTokenExpiresAt,
  signAccessToken,
} from "@kando/auth-core";
import { createId } from "../id";
import type { AuthPlatform } from "./platform-account";

export type CreatedUserSession = {
  sessionId: string;
  accessToken: string;
  refreshToken: string;
  hashedRefreshToken: string;
  expiresAt: string;
  expiresIn: number;
  userId: string;
  dataSpaceId: string;
  platform: AuthPlatform;
};

export async function createUserSessionValues(
  userId: string,
  dataSpaceId: string,
  platform: AuthPlatform,
  jwtSecret: string,
  now: Date,
): Promise<CreatedUserSession> {
  const sessionId = createId();
  const refreshToken = createRefreshToken();
  const hashedRefreshToken = await hashRefreshToken(refreshToken);
  const accessToken = await signAccessToken(
    { owner_type: "user", owner_id: dataSpaceId, session_id: sessionId },
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
    userId,
    dataSpaceId,
    platform,
  };
}
