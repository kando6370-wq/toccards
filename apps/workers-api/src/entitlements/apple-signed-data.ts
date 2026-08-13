import {
  Environment,
  SignedDataVerifier,
  type JWSRenewalInfoDecodedPayload,
  type ResponseBodyV2DecodedPayload,
  type JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import type { Env } from "../env";

export type AppleTransactionVerifier = Pick<SignedDataVerifier, "verifyAndDecodeTransaction">;
export type AppleNotificationVerifier = Pick<
  SignedDataVerifier,
  "verifyAndDecodeNotification" | "verifyAndDecodeTransaction" | "verifyAndDecodeRenewalInfo"
>;

export type AppleVerifierConfiguration = {
  environment: Environment;
  verifier: AppleTransactionVerifier;
};

export function createAppleVerifier(
  env: Pick<
    Env,
    | "APP_ENVIRONMENT"
    | "APPLE_IAP_APP_ID"
    | "APPLE_IAP_BUNDLE_ID"
    | "APPLE_ROOT_CERTIFICATES_BASE64"
  >,
): AppleVerifierConfiguration | null {
  return createSignedDataVerifier(env);
}

export function createAppleNotificationVerifier(
  env: Pick<Env, "APP_ENVIRONMENT" | "APPLE_IAP_APP_ID" | "APPLE_IAP_BUNDLE_ID" | "APPLE_ROOT_CERTIFICATES_BASE64">,
): { environment: Environment; verifier: AppleNotificationVerifier } | null {
  return createSignedDataVerifier(env);
}

export { Environment };
export type { JWSRenewalInfoDecodedPayload, JWSTransactionDecodedPayload, ResponseBodyV2DecodedPayload };

function createSignedDataVerifier(
  env: Pick<Env, "APP_ENVIRONMENT" | "APPLE_IAP_APP_ID" | "APPLE_IAP_BUNDLE_ID" | "APPLE_ROOT_CERTIFICATES_BASE64">,
): { environment: Environment; verifier: SignedDataVerifier } | null {
  const bundleId = env.APPLE_IAP_BUNDLE_ID?.trim();
  const roots = parseRootCertificates(env.APPLE_ROOT_CERTIFICATES_BASE64);
  if (!bundleId || !roots) return null;
  const environment = env.APP_ENVIRONMENT === "production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appAppleId = environment === Environment.PRODUCTION ? parseAppleId(env.APPLE_IAP_APP_ID) : undefined;
  if (environment === Environment.PRODUCTION && appAppleId === null) return null;
  try {
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
