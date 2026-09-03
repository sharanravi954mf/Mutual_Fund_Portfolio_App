import type { NseConfig } from "./nse_types.ts";

const encoder = new TextEncoder();
const hex128Pattern = /^[0-9a-f]{32}$/i;

export type NseAuthEntropy = {
  randomNumber?: number;
  ivHex?: string;
  saltHex?: string;
};

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function utf8ToBase64(value: string): string {
  return bytesToBase64(encoder.encode(value));
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

function randomHex128(): string {
  return bytesToHex(crypto.getRandomValues(new Uint8Array(16)));
}

function hexToBytes(value: string): Uint8Array {
  if (!hex128Pattern.test(value)) {
    throw new Error("nse_auth_entropy_invalid");
  }

  const bytes = new Uint8Array(16);
  for (let offset = 0; offset < value.length; offset += 2) {
    bytes[offset / 2] = Number.parseInt(value.slice(offset, offset + 2), 16);
  }
  return bytes;
}

function resolveRandomNumber(value?: number): number {
  const resolved = value ?? Math.floor((Math.random() * 10_000_000_000) + 1);
  if (
    !Number.isInteger(resolved) || resolved < 1 || resolved > 10_000_000_000
  ) {
    throw new Error("nse_auth_entropy_invalid");
  }
  return resolved;
}

export async function createNseEncryptedPassword(
  apiKeyMember: string,
  apiSecretUser: string,
  entropy: NseAuthEntropy = {},
): Promise<string> {
  const randomNumber = resolveRandomNumber(entropy.randomNumber);
  const ivHex = (entropy.ivHex ?? randomHex128()).toLowerCase();
  const saltHex = (entropy.saltHex ?? randomHex128()).toLowerCase();
  const iv = hexToBytes(ivHex);
  const salt = hexToBytes(saltHex);

  const keyMaterial = await crypto.subtle.importKey(
    "raw",
    encoder.encode(apiKeyMember),
    "PBKDF2",
    false,
    ["deriveKey"],
  );
  const key = await crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      hash: "SHA-1",
      salt: salt.buffer as ArrayBuffer,
      iterations: 1000,
    },
    keyMaterial,
    { name: "AES-CBC", length: 128 },
    false,
    ["encrypt"],
  );
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-CBC", iv: iv.buffer as ArrayBuffer },
      key,
      encoder.encode(`${apiSecretUser}|${randomNumber}`),
    ),
  );
  const innerPayload = `${ivHex}::${saltHex}::${bytesToBase64(ciphertext)}`;
  return utf8ToBase64(innerPayload);
}

export async function createNseBasicAuthorization(
  config: Pick<NseConfig, "loginUserId" | "apiKeyMember" | "apiSecretUser">,
): Promise<string> {
  const encryptedPassword = await createNseEncryptedPassword(
    config.apiKeyMember,
    config.apiSecretUser,
  );
  return `Basic ${utf8ToBase64(`${config.loginUserId}:${encryptedPassword}`)}`;
}
