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

export type AppleNotificationVerifierConfiguration = {
  environment: Environment;
  verifier: AppleNotificationVerifier;
};

export type AppleVerifierFactoryResult =
  | AppleVerifierConfiguration
  | readonly AppleVerifierConfiguration[]
  | null;

export type VerifiedAppleTransaction = {
  configuration: AppleVerifierConfiguration;
  transaction: JWSTransactionDecodedPayload;
};

const APPLE_VERIFICATION_STATUS_NAMES = [
  "OK",
  "VERIFICATION_FAILURE",
  "RETRYABLE_VERIFICATION_FAILURE",
  "INVALID_APP_IDENTIFIER",
  "INVALID_ENVIRONMENT",
  "INVALID_CHAIN_LENGTH",
  "INVALID_CERTIFICATE",
  "FAILURE",
] as const;

export type AppleVerificationFailure = {
  status: typeof APPLE_VERIFICATION_STATUS_NAMES[number];
  retryable: boolean;
};

export async function classifyAppleVerificationFailure(error: unknown): Promise<AppleVerificationFailure | null> {
  try {
    const { VerificationException, VerificationStatus } = await import("@apple/app-store-server-library");
    if (!(error instanceof VerificationException)) return null;
    const status = VerificationStatus[error.status];
    if (!isAppleVerificationStatusName(status)) return null;
    return {
      status,
      retryable: status === "RETRYABLE_VERIFICATION_FAILURE",
    };
  } catch {
    return null;
  }
}

export async function createAppleVerifier(
  env: Pick<
    Env,
    | "APP_ENVIRONMENT"
    | "APPLE_IAP_APP_ID"
    | "APPLE_IAP_BUNDLE_ID"
    | "APPLE_ROOT_CERTIFICATES_BASE64"
  >,
  environment = primaryAppleEnvironment(env),
): Promise<AppleVerifierConfiguration | null> {
  if (!appleVerifierEnvironments(env).includes(environment)) return null;
  return await createSignedDataVerifier(env, environment);
}

export async function createAppleNotificationVerifier(
  env: Pick<Env, "APP_ENVIRONMENT" | "APPLE_IAP_APP_ID" | "APPLE_IAP_BUNDLE_ID" | "APPLE_ROOT_CERTIFICATES_BASE64">,
  environment = primaryAppleEnvironment(env),
): Promise<AppleNotificationVerifierConfiguration | null> {
  if (!appleVerifierEnvironments(env).includes(environment)) return null;
  return await createSignedDataVerifier(env, environment);
}

export async function createAppleVerifiers(
  env: Pick<
    Env,
    | "APP_ENVIRONMENT"
    | "APPLE_IAP_APP_ID"
    | "APPLE_IAP_BUNDLE_ID"
    | "APPLE_ROOT_CERTIFICATES_BASE64"
  >,
): Promise<readonly AppleVerifierConfiguration[] | null> {
  const configurations: AppleVerifierConfiguration[] = [];
  for (const environment of appleVerifierEnvironments(env)) {
    const configuration = await createAppleVerifier(env, environment);
    if (!configuration) return null;
    configurations.push(configuration);
  }
  return configurations;
}

export function appleVerifierEnvironments(
  env: Pick<Env, "APP_ENVIRONMENT">,
): readonly Environment[] {
  return env.APP_ENVIRONMENT === "production"
    ? [Environment.PRODUCTION, Environment.SANDBOX]
    : [Environment.SANDBOX];
}

export function appleDatabaseEnvironments(
  env: Pick<Env, "APP_ENVIRONMENT">,
): readonly ("Production" | "Sandbox")[] {
  return appleVerifierEnvironments(env).map((environment) =>
    environment === Environment.PRODUCTION ? "Production" : "Sandbox"
  );
}

export function configuredProductIds(
  value: string | undefined,
): ReadonlySet<string> | null {
  if (!value) return null;
  const ids = value.split(",").map((item) => item.trim()).filter(Boolean);
  return ids.length > 0 ? new Set(ids) : null;
}

export function asVerifierConfigurations<T>(
  value: T | readonly T[] | null,
): readonly T[] {
  if (value === null) return [];
  return Array.isArray(value) ? value : [value as T];
}

export async function verifyAppleTransaction(
  configurations: readonly AppleVerifierConfiguration[],
  signedTransactionInfo: string,
): Promise<VerifiedAppleTransaction | null> {
  for (const configuration of configurations) {
    try {
      const transaction = await configuration.verifier
        .verifyAndDecodeTransaction(signedTransactionInfo);
      if (transaction.environment === configuration.environment) {
        return { configuration, transaction };
      }
    } catch {
      // A production bundle may carry either App Store or TestFlight evidence.
    }
  }
  return null;
}

export type { JWSRenewalInfoDecodedPayload, JWSTransactionDecodedPayload, ResponseBodyV2DecodedPayload };

async function createSignedDataVerifier(
  env: Pick<Env, "APP_ENVIRONMENT" | "APPLE_IAP_APP_ID" | "APPLE_IAP_BUNDLE_ID" | "APPLE_ROOT_CERTIFICATES_BASE64">,
  environment: Environment,
): Promise<{ environment: Environment; verifier: SignedDataVerifier } | null> {
  const bundleId = env.APPLE_IAP_BUNDLE_ID?.trim();
  const roots = parseRootCertificates(env.APPLE_ROOT_CERTIFICATES_BASE64);
  if (!bundleId || !roots) return null;
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

function primaryAppleEnvironment(
  env: Pick<Env, "APP_ENVIRONMENT">,
): Environment {
  return env.APP_ENVIRONMENT === "production"
    ? Environment.PRODUCTION
    : Environment.SANDBOX;
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

function isAppleVerificationStatusName(value: unknown): value is AppleVerificationFailure["status"] {
  return typeof value === "string" &&
    (APPLE_VERIFICATION_STATUS_NAMES as readonly string[]).includes(value);
}
