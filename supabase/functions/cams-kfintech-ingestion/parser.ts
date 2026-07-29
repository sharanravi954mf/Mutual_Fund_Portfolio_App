import {
  type NormalizedTransaction,
  type Registrar,
  type StatementFileType,
} from "./types.ts";
import { IngestionError } from "./types.ts";

type DbfField = {
  name: string;
  type: string;
  length: number;
};

export type ParseInput = {
  registrar: Registrar;
  fileType: StatementFileType;
  filename: string;
  bytes: Uint8Array;
};

export interface StatementParser {
  readonly registrar: Registrar;
  parse(input: ParseInput): Promise<NormalizedTransaction[]>;
}

export interface PdfTextExtractor {
  extractText(bytes: Uint8Array, registrar: Registrar): Promise<string>;
}

function parseAmount(value: unknown): number {
  const raw = String(value ?? "").replace(/,/g, "").trim();
  if (!/^-?\d+(\.\d+)?$/.test(raw)) {
    throw new IngestionError("parse_failed");
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) {
    throw new IngestionError("parse_failed");
  }
  return Math.round(Math.abs(parsed) * 1000000) / 1000000;
}

function parseDate(value: unknown): string {
  const raw = String(value ?? "").trim();
  let date: Date;
  if (/^\d{8}$/.test(raw)) {
    date = new Date(Date.UTC(
      Number(raw.substring(0, 4)),
      Number(raw.substring(4, 6)) - 1,
      Number(raw.substring(6, 8)),
    ));
  } else if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    date = new Date(`${raw}T00:00:00Z`);
  } else {
    throw new IngestionError("parse_failed");
  }
  if (Number.isNaN(date.getTime())) {
    throw new IngestionError("parse_failed");
  }
  return date.toISOString().slice(0, 10);
}

function getValue(record: Record<string, unknown>, keys: string[]): unknown {
  for (const key of keys) {
    const foundKey = Object.keys(record).find((candidate) =>
      candidate.toUpperCase() === key.toUpperCase()
    );
    if (foundKey != null) return record[foundKey];
  }
  return undefined;
}

function normalizeTransaction(
  record: Record<string, unknown>,
  registrar: Registrar,
  sourceRowNumber: number,
): NormalizedTransaction {
  const rawType = String(
    getValue(record, ["TRX_TYPE", "TX_TYPE", "TYPE", "TR_TYPE"]) ?? "",
  )
    .toUpperCase();
  const transactionType = rawType.includes("SWITCH") || rawType.includes("SWI")
    ? "SWITCH"
    : rawType.includes("SELL") || rawType.includes("RED") ||
        rawType.includes("OUT")
    ? "SELL"
    : "BUY";

  const units = parseAmount(
    getValue(record, ["UNITS", "CLOS_BAL", "QTY", "UNIT_QTY"]),
  );
  const amount = parseAmount(
    getValue(record, ["AMOUNT", "RUPEE_BAL", "AMT", "TRX_AMT"]),
  );
  const nav = parseAmount(getValue(record, ["NAV", "PRICE", "RATE"]));
  const date = parseDate(
    getValue(record, ["TRX_DATE", "TX_DATE", "DATE", "REP_DATE"]),
  );
  const clientPan = String(
    getValue(record, ["PAN", "PAN_NO", "APPL_PAN"]) ?? "",
  ).toUpperCase().trim();
  const folioNumber = String(
    getValue(record, ["FOLIO_NO", "FOLIOCHK", "FOLIO"]) ?? "",
  ).trim();
  const schemeCode = String(
    getValue(record, ["SCHEME_CD", "PRODUCT", "SCH_CODE", "FM_CODE"]) ?? "",
  ).trim();
  const investorName = String(
    getValue(record, ["INV_NAME", "HOLDER_NAME", "NAME", "INV_NM"]) ?? "",
  ).trim();

  if (
    clientPan === "" || folioNumber === "" || schemeCode === "" ||
    investorName === "" ||
    units <= 0 || amount <= 0
  ) {
    throw new IngestionError("parse_failed");
  }

  return {
    registrar,
    clientPan,
    investorName,
    folioNumber,
    schemeCode,
    schemeName: String(
      getValue(record, ["SCHEME_NM", "SCH_NAME", "SCHEME_NAME"]) ?? schemeCode,
    ).trim(),
    fundHouse: String(
      getValue(record, ["FUND_HOUSE", "AMC", "AMC_NAME"]) ?? "Mutual Fund",
    ).trim(),
    category: String(
      getValue(record, ["CATEGORY", "SCHEME_CAT"]) ?? "Mutual Fund",
    ).trim(),
    transactionType,
    units,
    nav,
    amount,
    date,
    sourceRowNumber,
    registrarTransactionId:
      String(getValue(record, ["TRX_ID", "TRAN_ID", "REGISTRAR_TXN_ID"]) ?? "")
        .trim() ||
      undefined,
  };
}

function parseDbf(bytes: Uint8Array): Record<string, unknown>[] {
  if (bytes.byteLength < 33) {
    throw new IngestionError("unsupported_statement_format");
  }

  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const recordCount = view.getUint32(4, true);
  const headerLength = view.getUint16(8, true);
  const recordLength = view.getUint16(10, true);

  if (
    headerLength >= bytes.byteLength || bytes[headerLength - 1] !== 0x0d ||
    recordLength <= 1
  ) {
    throw new IngestionError("unsupported_statement_format");
  }

  const fields: DbfField[] = [];
  let offset = 32;
  while (offset + 32 <= headerLength - 1) {
    const nameBytes = bytes.subarray(offset, offset + 11);
    const zero = nameBytes.indexOf(0);
    const name = new TextDecoder().decode(
      zero === -1 ? nameBytes : nameBytes.subarray(0, zero),
    ).trim();
    const type = String.fromCharCode(bytes[offset + 11]);
    const length = bytes[offset + 16];
    if (name !== "" && length > 0) {
      fields.push({ name, type, length });
    }
    offset += 32;
  }

  if (fields.length === 0) {
    throw new IngestionError("unsupported_statement_format");
  }

  const records: Record<string, unknown>[] = [];
  let recordOffset = headerLength;
  const decoder = new TextDecoder();
  for (let index = 0; index < recordCount; index++) {
    if (recordOffset + recordLength > bytes.byteLength) {
      throw new IngestionError("unsupported_statement_format");
    }
    const deleted = bytes[recordOffset] === 0x2a;
    if (!deleted) {
      const record: Record<string, unknown> = {};
      let fieldOffset = recordOffset + 1;
      for (const field of fields) {
        const raw = decoder.decode(
          bytes.subarray(fieldOffset, fieldOffset + field.length),
        ).trim();
        record[field.name] = field.type === "N" || field.type === "F"
          ? raw
          : raw;
        fieldOffset += field.length;
      }
      records.push(record);
    }
    recordOffset += recordLength;
  }
  return records;
}

function parseDelimitedText(text: string): Record<string, unknown>[] {
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (lines.length < 2) {
    throw new IngestionError("parse_failed");
  }
  const delimiter = lines[0].includes("|") ? "|" : ",";
  const headers = lines[0].split(delimiter).map((header) => header.trim());
  return lines.slice(1).map((line) => {
    const values = line.split(delimiter).map((value) => value.trim());
    if (values.length !== headers.length) {
      throw new IngestionError("parse_failed");
    }
    const record: Record<string, unknown> = {};
    headers.forEach((header, index) => {
      record[header] = values[index];
    });
    return record;
  });
}

abstract class BaseRegistrarParser implements StatementParser {
  abstract readonly registrar: Registrar;

  constructor(private readonly pdfTextExtractor?: PdfTextExtractor) {}

  async parse(input: ParseInput): Promise<NormalizedTransaction[]> {
    if (input.registrar !== this.registrar) {
      throw new IngestionError("unsupported_registrar");
    }

    const records = input.fileType === "DBF"
      ? parseDbf(input.bytes)
      : parseDelimitedText(await this.extractPdfText(input.bytes));

    const parsed = records.map((record, index) =>
      normalizeTransaction(record, this.registrar, index + 1)
    );
    if (parsed.length === 0) {
      throw new IngestionError("parse_failed");
    }
    return parsed;
  }

  private async extractPdfText(bytes: Uint8Array): Promise<string> {
    if (this.pdfTextExtractor == null) {
      throw new IngestionError("unsupported_statement_format");
    }
    return await this.pdfTextExtractor.extractText(bytes, this.registrar);
  }
}

export class CamsParser extends BaseRegistrarParser {
  readonly registrar = "CAMS" as const;
}

export class KfintechParser extends BaseRegistrarParser {
  readonly registrar = "KFINTECH" as const;
}

export class ParserRegistry {
  private readonly parsers: Map<Registrar, StatementParser>;

  constructor(parsers: StatementParser[]) {
    this.parsers = new Map(parsers.map((parser) => [parser.registrar, parser]));
  }

  async parse(input: ParseInput): Promise<NormalizedTransaction[]> {
    const parser = this.parsers.get(input.registrar);
    if (parser == null) {
      throw new IngestionError("unsupported_registrar");
    }
    return await parser.parse(input);
  }
}

export function createSyntheticDbf(
  records: Record<string, string>[],
): Uint8Array {
  const fields = [
    { name: "PAN", type: "C", length: 10 },
    { name: "INV_NAME", type: "C", length: 24 },
    { name: "FOLIO_NO", type: "C", length: 16 },
    { name: "SCHEME_CD", type: "C", length: 12 },
    { name: "SCHEME_NM", type: "C", length: 32 },
    { name: "FUND_HOUSE", type: "C", length: 28 },
    { name: "CATEGORY", type: "C", length: 18 },
    { name: "TRX_TYPE", type: "C", length: 12 },
    { name: "UNITS", type: "N", length: 14 },
    { name: "NAV", type: "N", length: 12 },
    { name: "AMOUNT", type: "N", length: 14 },
    { name: "TRX_DATE", type: "C", length: 8 },
  ];
  const headerLength = 32 + fields.length * 32 + 1;
  const recordLength = 1 + fields.reduce((sum, field) => sum + field.length, 0);
  const bytes = new Uint8Array(headerLength + recordLength * records.length);
  const view = new DataView(bytes.buffer);
  bytes[0] = 0x03;
  view.setUint32(4, records.length, true);
  view.setUint16(8, headerLength, true);
  view.setUint16(10, recordLength, true);

  const encoder = new TextEncoder();
  let offset = 32;
  for (const field of fields) {
    bytes.set(encoder.encode(field.name).subarray(0, 11), offset);
    bytes[offset + 11] = field.type.charCodeAt(0);
    bytes[offset + 16] = field.length;
    offset += 32;
  }
  bytes[offset] = 0x0d;

  records.forEach((record, recordIndex) => {
    let recordOffset = headerLength + recordIndex * recordLength;
    bytes[recordOffset] = 0x20;
    recordOffset += 1;
    for (const field of fields) {
      const value = (record[field.name] ?? "").padEnd(field.length, " ").slice(
        0,
        field.length,
      );
      bytes.set(encoder.encode(value), recordOffset);
      recordOffset += field.length;
    }
  });

  return bytes;
}
