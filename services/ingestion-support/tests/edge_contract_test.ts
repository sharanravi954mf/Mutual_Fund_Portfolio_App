import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  HttpMalwareScanner,
  RemotePdfTextExtractor,
} from "../../../supabase/functions/cams-kfintech-ingestion/adapters.ts";
import {
  CamsParser,
  KfintechParser,
} from "../../../supabase/functions/cams-kfintech-ingestion/parser.ts";
import { IngestionError } from "../../../supabase/functions/cams-kfintech-ingestion/types.ts";

function env(name: string): string {
  const value = Deno.env.get(name);
  if (value == null || value === "") throw new Error(`missing ${name}`);
  return value;
}

function escapePdfText(value: string): string {
  return value.replaceAll("\\", "\\\\").replaceAll("(", "\\(").replaceAll(")", "\\)");
}

function syntheticPdf(lines: string[]): Uint8Array {
  const stream = lines.map((line, index) =>
    `BT /F1 6 Tf 20 ${760 - index * 20} Td (${escapePdfText(line)}) Tj ET\n`
  ).join("");
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
    `<< /Length ${new TextEncoder().encode(stream).byteLength} >>\nstream\n${stream}endstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let pdf = "%PDF-1.4\n";
  const offsets = [0];
  objects.forEach((object, index) => {
    offsets.push(new TextEncoder().encode(pdf).byteLength);
    pdf += `${index + 1} 0 obj\n${object}\nendobj\n`;
  });
  const xref = new TextEncoder().encode(pdf).byteLength;
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets.slice(1)) {
    pdf += `${String(offset).padStart(10, "0")} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return new TextEncoder().encode(pdf);
}

Deno.test("live PDF endpoint feeds the existing CAMS and KFintech parsers", async () => {
  const baseUrl = env("INGESTION_SUPPORT_BASE_URL");
  const token = env("PDF_TEXT_EXTRACTOR_SERVICE_TOKEN");
  const extractor = new RemotePdfTextExtractor(
    `${baseUrl}/pdf/extract`,
    token,
    10_000,
    1_048_576,
    true,
  );
  const camsPdf = syntheticPdf([
    "MONEYBOWL_CAMS_CAS_V1",
    "PAN|INV_NAME|FOLIO_NO|SCHEME_CD|SCHEME_NM|FUND_HOUSE|CATEGORY|TRX_TYPE|UNITS|NAV|AMOUNT|TRX_DATE|TRX_ID",
    "ABCDE1234F|Synthetic Investor|FOLIO1001|CAMS001|Synthetic Equity Fund|Synthetic AMC|Equity|BUY|12.5000|20.0000|250.00|20260729|CAMS-SYNTH-1",
  ]);
  const [cams] = await new CamsParser(extractor).parse({
    registrar: "CAMS",
    fileType: "CAS_PDF",
    filename: "synthetic-cams.pdf",
    bytes: camsPdf,
  });
  assertEquals(cams.schemeCode, "CAMS001");
  assertEquals(cams.amount, 250);

  const kfinPdf = syntheticPdf([
    "MONEYBOWL_KFINTECH_CAS_V1",
    "PAN1|INVNAME|ACNO|FUNDCODE|FUND_DESC|AMC_NAME|ASSETTYPE|TD_TRTYPE|TD_UNITS|TD_NAV|TD_AMT|TD_TRDATE|TD_TRNO",
    "FGHIJ5678K|Synthetic KFin Investor|KFOLIO1001|KFIN001|Synthetic Debt Fund|Synthetic KFin AMC|Debt|R|-5.0000|10.0000|-50.00|20260729|KFIN-SYNTH-1",
  ]);
  const [kfin] = await new KfintechParser(extractor).parse({
    registrar: "KFINTECH",
    fileType: "CAS_PDF",
    filename: "synthetic-kfintech.pdf",
    bytes: kfinPdf,
  });
  assertEquals(kfin.schemeCode, "KFIN001");
  assertEquals(kfin.transactionDirection, "OUTFLOW");
});

Deno.test("live malware endpoint satisfies the existing scanner contract", async () => {
  const baseUrl = env("INGESTION_SUPPORT_BASE_URL");
  const scanner = new HttpMalwareScanner(
    `${baseUrl}/malware/scan`,
    env("MALWARE_SCANNER_SERVICE_TOKEN"),
    10_000,
    4096,
    true,
  );
  const clean = new TextEncoder().encode("synthetic clean content");
  const cleanDigest = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", clean)),
  ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  assertEquals(
    await scanner.scan(clean, { sha256Hex: cleanDigest, filename: "clean.bin" }),
    "clean",
  );

  const eicar = new TextEncoder().encode(
    "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-" +
      "STANDARD-ANTIVIRUS-TEST-FILE!$H+H*",
  );
  const eicarDigest = Array.from(
    new Uint8Array(await crypto.subtle.digest("SHA-256", eicar)),
  ).map((byte) => byte.toString(16).padStart(2, "0")).join("");
  await assertRejects(
    () => scanner.scan(eicar, { sha256Hex: eicarDigest, filename: "eicar.txt" }),
    IngestionError,
    "malware_detected",
  );
});
