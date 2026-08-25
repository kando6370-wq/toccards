import { beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../env";
import {
  createAppleVerifier,
  createAppleVerifiers,
  Environment,
  type AppleVerifierConfiguration,
  verifyAppleTransaction,
} from "./apple-signed-data";

const mock = vi.hoisted(() => ({ environments: [] as string[] }));

vi.mock("@apple/app-store-server-library", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@apple/app-store-server-library")>();
  return {
    ...actual,
    SignedDataVerifier: class {
      constructor(
        _roots: Buffer[],
        _onlineChecks: boolean,
        environment: string,
      ) {
        mock.environments.push(environment);
      }
    },
  };
});

describe("Apple verifier environment configuration", () => {
  beforeEach(() => {
    mock.environments.length = 0;
  });

  it("creates a Sandbox verifier for the production bundle because TestFlight JWS is Sandbox evidence", async () => {
    const createForEnvironment = createAppleVerifier as unknown as (
      env: Env,
      environment: Environment,
    ) => Promise<AppleVerifierConfiguration | null>;

    const configured = await createForEnvironment({
      APP_ENVIRONMENT: "production",
      APPLE_IAP_APP_ID: "6793017224",
      APPLE_IAP_BUNDLE_ID: "com.cardai.tcg",
      APPLE_ROOT_CERTIFICATES_BASE64: "AQ==",
    } as Env, Environment.SANDBOX);

    expect(configured?.environment).toBe(Environment.SANDBOX);
    expect(mock.environments).toContain(Environment.SANDBOX);
  });

  it("requires both App Store and TestFlight verifiers for production purchase handling", async () => {
    const configured = await createAppleVerifiers({
      APP_ENVIRONMENT: "production",
      APPLE_IAP_APP_ID: "6793017224",
      APPLE_IAP_BUNDLE_ID: "com.cardai.tcg",
      APPLE_ROOT_CERTIFICATES_BASE64: "AQ==",
    });

    expect(configured?.map((item) => item.environment)).toEqual([
      Environment.PRODUCTION,
      Environment.SANDBOX,
    ]);
  });

  it("falls through Production verification to signed TestFlight Sandbox evidence", async () => {
    const verified = await verifyAppleTransaction([
      {
        environment: Environment.PRODUCTION,
        verifier: {
          async verifyAndDecodeTransaction() {
            throw new Error("not Production evidence");
          },
        },
      },
      {
        environment: Environment.SANDBOX,
        verifier: {
          async verifyAndDecodeTransaction() {
            return { environment: Environment.SANDBOX };
          },
        },
      },
    ], "testflight.jws");

    expect(verified?.configuration.environment).toBe(Environment.SANDBOX);
    expect(verified?.transaction.environment).toBe(Environment.SANDBOX);
  });
});
