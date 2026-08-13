import type {
  Environment as AppleEnvironment,
  SignedDataVerifier,
  JWSRenewalInfoDecodedPayload,
  ResponseBodyV2DecodedPayload,
  JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import type { Env } from "../env";

export const Environment = {
  SANDBOX: "Sandbox" as AppleEnvironment,
  PRODUCTION: "Production" as AppleEnvironment,
  XCODE: "Xcode" as AppleEnvironment,
  LOCAL_TESTING: "LocalTesting" as AppleEnvironment,
} as const;

export type Environment = AppleEnvironment;

export type AppleTransactionVerifier = Pick<SignedDataVerifier, "verifyAndDecodeTransaction">;
export type AppleNotificationVerifier = Pick<
  SignedDataVerifier,
  "verifyAndDecodeNotification" | "verifyAndDecodeTransaction" | "verifyAndDecodeRenewalInfo"
>;

export type AppleVerifierConfiguration = {
  environment: Environment;
  verifier: AppleTransactionVerifier;
};

export async function createAppleVerifier(
  env: Pick<
    Env,
    | "APP_ENVIRONMENT"
    | "APPLE_IAP_APP_ID"
    | "APPLE_IAP_BUNDLE_ID"
    | "APPLE_ROOT_CERTIFICATES_BASE64"
  >,
): Promise<AppleVerifierConfiguration | null> {
  return await createSignedDataVerifier(env);
}

export async function createAppleNotificationVerifier(
  env: Pick<Env, "APP_ENVIRONMENT" | "APPLE_IAP_APP_ID" | "APPLE_IAP_BUNDLE_ID" | "APPLE_ROOT_CERTIFICATES_BASE64">,
): Promise<{ environment: Environment; verifier: AppleNotificationVerifier } | null> {
  return await createSignedDataVerifier(env);
}

export type { JWSRenewalInfoDecodedPayload, JWSTransactionDecodedPayload, ResponseBodyV2DecodedPayload };

async function createSignedDataVerifier(
  env: Pick<Env, "APP_ENVIRONMENT" | "APPLE_IAP_APP_ID" | "APPLE_IAP_BUNDLE_ID" | "APPLE_ROOT_CERTIFICATES_BASE64">,
): Promise<{ environment: Environment; verifier: SignedDataVerifier } | null> {
  const bundleId = env.APPLE_IAP_BUNDLE_ID?.trim();
  const roots = parseRootCertificates(env.APPLE_ROOT_CERTIFICATES_BASE64);
  if (!bundleId || !roots) return null;
  const environment = env.APP_ENVIRONMENT === "production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appAppleId = environment === Environment.PRODUCTION ? parseAppleId(env.APPLE_IAP_APP_ID) : undefined;
  if (environment === Environment.PRODUCTION && appAppleId === null) return null;
  try {
    const { SignedDataVerifier } = await import("@apple/app-store-server-library");
    return {
      environment,
      verifier: new SignedDataVerifier(roots, true, environment, bundleId, appAppleId ?? undefined),
    };
  } catch {
    return null;
  }
}

function parseRootCertificates(value: string | undefined): Buffer[] | null {
  if (!value) return null;
  const certificates = value.split(",").map((item) => item.trim()).filter(Boolean);
  if (certificates.length === 0) return null;
  try {
    const roots = certificates.map((certificate) => Buffer.from(certificate, "base64"));
    return roots.every((root) => root.length > 0) ? roots : null;
  } catch {
    return null;
  }
}

function parseAppleId(value: string | undefined): number | null {
  if (!value || !/^\d+$/.test(value)) return null;
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : null;
}
