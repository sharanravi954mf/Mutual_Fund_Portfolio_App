import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createSyntheticDbf } from "./parser.ts";
import { createHostedDevCamsDbfDiagnosticHandler } from "./hosted_dev_diagnostic.ts";
import { sha256Hex } from "./security.ts";

const internalToken = "synthetic-internal-token";
const hostedDevUrl = "https://rskryngwzyuzmiwtriyy.supabase.co";

function syntheticBytes(): Uint8Array {
  return createSyntheticDbf([{
    PAN: "ABCDE1234F",
    INV_NAME: "Synthetic Test Person",
    FOLIO_NO: "FOLIO-TEST",
    SCHEME_CD: "SYNTH",
    SCHEME_NM: "Synthetic",
    FUND_HOUSE: "Test Fund",
    CATEGORY: "Test",
    TRX_TYPE: "PURCHASE",
    UNITS: "2",
    NAV: "10",
    AMOUNT: "20",
    TRX_DATE: "20260830",
  }]);
}

async function handlerFor(bytes = syntheticBytes(), projectUrl = hostedDevUrl) {
  const sha256 = await sha256Hex(bytes);
  let reads = 0;
  const handler = createHostedDevCamsDbfDiagnosticHandler({
    internalToken,
    projectUrl,
    targets: new Map([[sha256, {
      size: bytes.byteLength,
      path: "synthetic/private/object",
    }]]),
    readOriginal: () => {
      reads += 1;
      return Promise.resolve(bytes);
    },
  });
  return { handler, sha256, reads: () => reads };
}

function request(sha256: string, token = internalToken): Request {
  return new Request("http://localhost/diagnostics/cams-dbf", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ sha256 }),
  });
}

Deno.test("diagnostic is available only in Hosted Dev", async () => {
  const { handler, sha256, reads } = await handlerFor(
    syntheticBytes(),
    "https://production.example.supabase.co",
  );
  const response = await handler(request(sha256));
  assertEquals(response.status, 403);
  assertEquals(reads(), 0);
});

Deno.test("diagnostic requires the internal token and exact SHA allowlist", async () => {
  const { handler, sha256, reads } = await handlerFor();
  assertEquals((await handler(request(sha256, "not-the-token"))).status, 403);
  assertEquals((await handler(request("0".repeat(64)))).status, 403);
  assertEquals(reads(), 0);
});

Deno.test("diagnostic refuses a stored object whose bytes do not match the allowlisted SHA", async () => {
  const expected = syntheticBytes();
  const sha256 = await sha256Hex(expected);
  let reads = 0;
  const handler = createHostedDevCamsDbfDiagnosticHandler({
    internalToken,
    projectUrl: hostedDevUrl,
    targets: new Map([[sha256, {
      size: expected.byteLength,
      path: "synthetic/private/object",
    }]]),
    readOriginal: () => {
      reads += 1;
      return Promise.resolve(new Uint8Array(expected.byteLength));
    },
  });

  const response = await handler(request(sha256));
  assertEquals(response.status, 403);
  assertEquals(reads, 1);
});

Deno.test("diagnostic response is aggregate-only and has no normal-ingestion side effects", async () => {
  const { handler, sha256, reads } = await handlerFor();
  const response = await handler(request(sha256));
  const text = await response.text();
  assertEquals(response.status, 200);
  assertEquals(reads(), 1);
  assertStringIncludes(text, '"record_count":1');
  assertStringIncludes(text, '"PURCHASE":1');
  assertEquals(text.includes("ABCDE1234F"), false);
  assertEquals(text.includes("Synthetic Test Person"), false);
  assertEquals(text.includes("FOLIO-TEST"), false);
  assertEquals(text.includes("synthetic/private/object"), false);
});
