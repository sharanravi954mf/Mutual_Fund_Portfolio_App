import {
  assert,
  assertEquals,
  assertMatch,
  assertNotEquals,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createNseEncryptedPassword } from "./nse_auth.ts";

const deterministicEntropy = {
  randomNumber: 1_234_567_890,
  ivHex: "000102030405060708090a0b0c0d0e0f",
  saltHex: "101112131415161718191a1b1c1d1e1f",
};

function decodePayload(encryptedPassword: string): string {
  return atob(encryptedPassword);
}

Deno.test("NSE encrypted password has the Postman iv::salt::ciphertext structure", async () => {
  const encryptedPassword = await createNseEncryptedPassword(
    "test-api-key-member",
    "test-api-secret-user",
    deterministicEntropy,
  );
  const payload = decodePayload(encryptedPassword);
  const parts = payload.split("::");

  assertEquals(parts.length, 3);
  assertMatch(parts[0], /^[0-9a-f]{32}$/);
  assertMatch(parts[1], /^[0-9a-f]{32}$/);
  assertEquals(parts[0].length, 32);
  assertEquals(parts[1].length, 32);
  assertMatch(parts[2], /^[A-Za-z0-9+/]+={0,2}$/);
  assert(atob(parts[2]).length > 0);
  assertEquals(btoa(payload), encryptedPassword);
});

Deno.test("NSE authentication matches the CryptoJS 3.3.0 deterministic vector", async () => {
  const encryptedPassword = await createNseEncryptedPassword(
    "test-api-key-member",
    "test-api-secret-user",
    deterministicEntropy,
  );

  assertEquals(
    encryptedPassword,
    "MDAwMTAyMDMwNDA1MDYwNzA4MDkwYTBiMGMwZDBlMGY6OjEwMTExMjEzMTQxNTE2MTcxODE5MWExYjFjMWQxZTFmOjpONUcycHFLNkxDQ0RUV1pMbE4rMFp4ZHdPNjdIdlpoWE5vc3NFaDlEZ1VZPQ==",
  );
});

Deno.test("NSE authentication changes between calls", async () => {
  const first = await createNseEncryptedPassword("test-key", "test-secret");
  const second = await createNseEncryptedPassword("test-key", "test-secret");

  assertNotEquals(first, second);
});
