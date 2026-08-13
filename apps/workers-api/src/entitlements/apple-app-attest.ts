import {
  verifyAssertion,
  verifyAttestation,
} from "@bradford-tech/supabase-integrity-attest";

export type AppleAppAttestVerifier = {
  verifyAttestation(input: {
    appId: string;
    developmentEnvironment: boolean;
    keyId: string;
    clientDataHash: Uint8Array;
    attestation: string;
  }): Promise<{ publicKeyPem: string; receiptBase64: string; signCount: number }>;
  verifyAssertion(input: {
    appId: string;
    assertion: string;
    clientData: string;
    publicKeyPem: string;
    previousSignCount: number;
  }): Promise<{ signCount: number }>;
};

export const appleAppAttestVerifier: AppleAppAttestVerifier = {
  async verifyAttestation(input) {
    const result = await verifyAttestation(
      { appId: input.appId, developmentEnv: input.developmentEnvironment },
      input.keyId,
      input.clientDataHash,
      input.attestation,
    );
    return {
      publicKeyPem: result.publicKeyPem,
      receiptBase64: bytesToBase64(result.receipt),
      signCount: result.signCount,
    };
  },
  verifyAssertion(input) {
    return verifyAssertion(
      { appId: input.appId },
      input.assertion,
      input.clientData,
      input.publicKeyPem,
      input.previousSignCount,
    );
  },
};

export async function sha256Bytes(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
  );
}

function bytesToBase64(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary);
}
