import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { RtaFileParser } from "./parser.ts";
import * as zip from "npm:@zip.js/zip.js";

// Helper to construct a mock dBASE III DBF binary buffer
function createMockDbfBytes(): Uint8Array {
  // Define fields and their sizes
  const fields = [
    { name: "PAN", type: "C", length: 10 },
    { name: "INV_NAME", type: "C", length: 20 },
    { name: "FOLIO_NO", type: "C", length: 10 },
    { name: "SCHEME_CD", type: "C", length: 10 },
    { name: "SCHEME_NM", type: "C", length: 30 },
    { name: "FUND_HOUSE", type: "C", length: 30 },
    { name: "CATEGORY", type: "C", length: 20 },
    { name: "TRX_TYPE", type: "C", length: 10 },
    { name: "UNITS", type: "N", length: 12 },
    { name: "NAV", type: "N", length: 12 },
    { name: "AMOUNT", type: "N", length: 12 },
    { name: "TRX_DATE", type: "C", length: 8 }, // YYYYMMDD
  ];

  const headerLength = 32 + fields.length * 32 + 1; // 32 main + 12 fields * 32 + 1 terminator (0x0D) = 417 bytes
  const recordLength = 1 + fields.reduce((acc, f) => acc + f.length, 0); // 1 deletion flag + sum(lengths) = 1 + 176 = 177 bytes

  const bufferSize = headerLength + recordLength;
  const buffer = new Uint8Array(bufferSize);
  const view = new DataView(buffer.buffer);

  // 1. Write Header (32 bytes)
  buffer[0] = 0x03; // dBASE III version
  buffer[1] = 26;   // Last update Year (126 since 1900)
  buffer[2] = 7;    // Month
  buffer[3] = 18;   // Day
  view.setUint32(4, 1, true); // Number of records = 1
  view.setUint16(8, headerLength, true);
  view.setUint16(10, recordLength, true);

  // 2. Write Field Descriptors (32 bytes each)
  let offset = 32;
  for (const field of fields) {
    // Field name (up to 11 bytes, zero-padded)
    const nameBytes = new TextEncoder().encode(field.name);
    for (let i = 0; i < 11; i++) {
      buffer[offset + i] = i < nameBytes.length ? nameBytes[i] : 0;
    }
    buffer[offset + 11] = field.type.charCodeAt(0); // Field Type
    buffer[offset + 16] = field.length; // Field Length
    offset += 32;
  }

  // Header terminator
  buffer[offset] = 0x0D;

  // 3. Write Record 1 (177 bytes)
  let recOffset = headerLength;
  buffer[recOffset] = 0x20; // Deletion flag: space (active)
  recOffset += 1;

  // Record values mapping
  const recordValues = {
    PAN: "ABCDE1234F",
    INV_NAME: "Hariom Sharan",
    FOLIO_NO: "987654321",
    SCHEME_CD: "119551",
    SCHEME_NM: "Aditya Birla Multi-Cap Fund",
    FUND_HOUSE: "Aditya Birla Mutual Fund",
    CATEGORY: "Equity Scheme",
    TRX_TYPE: "BUY",
    UNITS: "123.4560",
    NAV: "15.7500",
    AMOUNT: "1944.43",
    TRX_DATE: "20260718",
  };

  const encoder = new TextEncoder();
  for (const field of fields) {
    const val = (recordValues as any)[field.name] || "";
    // Padded right with spaces
    const padded = val.padEnd(field.length, " ");
    const valBytes = encoder.encode(padded);
    for (let i = 0; i < field.length; i++) {
      buffer[recOffset + i] = valBytes[i];
    }
    recOffset += field.length;
  }

  return buffer;
}

// Helper to construct a password-protected zip file programmatically
async function createEncryptedZipBytes(filename: string, content: Uint8Array): Promise<Uint8Array> {
  const zipWriter = new zip.ZipWriter(new zip.Uint8ArrayWriter(), {
    password: "cams123",
    zipCrypto: true, // Use standard PKWARE zip encryption
  });
  
  await zipWriter.add(filename, new zip.Uint8ArrayReader(content));
  const zipData = await zipWriter.close();
  return zipData;
}

Deno.test("RTA Ingestion Ingests Password-Protected ZIP containing DBF Statement", async () => {
  const dbfContent = createMockDbfBytes();
  const zipContent = await createEncryptedZipBytes("17072026065215_208650458R9.dbf", dbfContent);

  const parser = new RtaFileParser();
  const parsedTransactions = [];

  // Parse using our updated stream parser
  const parsedStream = parser.parseFileStream("17072026065215_208650458R9.zip", zipContent);
  for await (const record of parsedStream) {
    parsedTransactions.push(record);
  }

  // Validate parsed record matches expectation
  assertEquals(parsedTransactions.length, 1);
  const tx = parsedTransactions[0];
  assertEquals(tx.clientPan, "ABCDE1234F");
  assertEquals(tx.investorName, "Hariom Sharan");
  assertEquals(tx.folioNumber, "987654321");
  assertEquals(tx.schemeCode, "119551");
  assertEquals(tx.schemeName, "Aditya Birla Multi-Cap Fund");
  assertEquals(tx.fundHouse, "Aditya Birla Mutual Fund");
  assertEquals(tx.category, "Equity Scheme");
  assertEquals(tx.transactionType, "BUY");
  assertEquals(tx.units, 123.4560);
  assertEquals(tx.nav, 15.7500);
  assertEquals(tx.amount, 1944.43);
  assertEquals(tx.date.getFullYear(), 2026);
  assertEquals(tx.date.getMonth(), 6); // July is 6 (0-indexed)
  assertEquals(tx.date.getDate(), 18);
});
