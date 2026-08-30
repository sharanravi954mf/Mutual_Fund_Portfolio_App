import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createSyntheticDbf, inspectCamsDbf } from "./parser.ts";
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

const requiredTransactionFields = [
  { name: "PAN", type: "C", length: 10 },
  { name: "INV_NAME", type: "C", length: 24 },
  { name: "FOLIO_NO", type: "C", length: 16 },
  { name: "SCHEME_CD", type: "C", length: 12 },
  { name: "TRX_TYPE", type: "C", length: 32 },
  { name: "UNITS", type: "N", length: 14 },
  { name: "NAV", type: "N", length: 12 },
  { name: "AMOUNT", type: "N", length: 14 },
  { name: "TRX_DATE", type: "C", length: 8 },
];

Deno.test("diagnostic returns normalized aggregate labels without raw row values", () => {
  const diagnostic = inspectCamsDbf(createSyntheticDbf([
    {
      PAN: "ABCDE1234F",
      INV_NAME: "Synthetic Private Investor",
      FOLIO_NO: "FOLIO-DO-NOT-RETURN",
      SCHEME_CD: "PRIVATE-SCHEME",
      TRX_TYPE: "Other redacted event",
      UNITS: "-917.37",
      NAV: "19.27",
      AMOUNT: "-529.61",
      TRX_DATE: "20260830",
    },
    {
      PAN: "ABCDE1234F",
      INV_NAME: "Synthetic Private Investor",
      FOLIO_NO: "FOLIO-DO-NOT-RETURN",
      SCHEME_CD: "PRIVATE-SCHEME",
      TRX_TYPE: "Other redacted event",
      UNITS: "3",
      NAV: "19.27",
      AMOUNT: "57.81",
      TRX_DATE: "20260830",
    },
    {
      PAN: "ABCDE1234F",
      INV_NAME: "Synthetic Private Investor",
      FOLIO_NO: "FOLIO-DO-NOT-RETURN",
      SCHEME_CD: "PRIVATE-SCHEME",
      TRX_TYPE: "PURCHASE",
      UNITS: "-3",
      NAV: "19.27",
      AMOUNT: "57.81",
      TRX_DATE: "20260830",
    },
  ], requiredTransactionFields));

  assertEquals(diagnostic.schema_classification, "TRANSACTION_CAPABLE");
  assertEquals(diagnostic.unmapped_transaction_labels, {
    OTHER_REDACTED_EVENT: 2,
  });
  assertEquals(diagnostic.units_sign_failures_by_label, {
    OTHER_REDACTED_EVENT: 1,
    PURCHASE: 1,
  });
  assertEquals(diagnostic.amount_sign_failures_by_label, {
    OTHER_REDACTED_EVENT: 1,
  });
  assertEquals(diagnostic.validation_stages["alias resolution"], {
    pass: 9,
    fail: 0,
  });
  assertEquals(
    diagnostic.first_failing_validation_category,
    "transaction-code mapping",
  );

  const payload = JSON.stringify(diagnostic);
  for (
    const privateValue of [
      "ABCDE1234F",
      "Synthetic Private Investor",
      "FOLIO-DO-NOT-RETURN",
      "PRIVATE-SCHEME",
      "917.37",
      "529.61",
      "19.27",
    ]
  ) {
    assertEquals(payload.includes(privateValue), false);
  }
});

Deno.test("diagnostic treats optional aliases as report-only and required aliases as failures", () => {
  const optionalOnlyMissing = inspectCamsDbf(createSyntheticDbf([{
    PAN: "ABCDE1234F",
    INV_NAME: "Synthetic Investor",
    FOLIO_NO: "FOLIO-TEST",
    SCHEME_CD: "SCHEME",
    TRX_TYPE: "PURCHASE",
    UNITS: "2",
    NAV: "10",
    AMOUNT: "20",
    TRX_DATE: "20260830",
  }], requiredTransactionFields));
  assertEquals(optionalOnlyMissing.alias_resolution.schemeName, "MISSING");
  assertEquals(optionalOnlyMissing.alias_resolution.fundHouse, "MISSING");
  assertEquals(optionalOnlyMissing.alias_resolution.category, "MISSING");
  assertEquals(
    optionalOnlyMissing.alias_resolution.registrarTransactionId,
    "MISSING",
  );
  assertEquals(optionalOnlyMissing.validation_stages["alias resolution"], {
    pass: 9,
    fail: 0,
  });
  assertEquals(optionalOnlyMissing.first_failing_validation_category, null);

  const holdingSchema = inspectCamsDbf(createSyntheticDbf([{
    PAN: "ABCDE1234F",
    INV_NAME: "Synthetic Investor",
    FOLIO_NO: "FOLIO-TEST",
    SCHEME_CD: "SCHEME",
  }], requiredTransactionFields.slice(0, 4)));
  assertEquals(holdingSchema.schema_classification, "NON_TRANSACTION_SCHEMA");
  assertEquals(holdingSchema.validation_stages["alias resolution"], {
    pass: 4,
    fail: 5,
  });
  assertEquals(
    holdingSchema.first_failing_validation_category,
    "alias resolution",
  );
});
