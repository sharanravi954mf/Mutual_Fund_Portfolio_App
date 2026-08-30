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
  decimalCount?: number;
};

export type CamsDbfDiagnostic = {
  record_count: number;
  structural_decode: "PASS" | "FAIL";
  field_schema: {
    name: string;
    type: string;
    width: number;
    decimal_count: number;
  }[];
  alias_resolution: Record<string, "RESOLVED" | "MISSING">;
  transaction_description_labels: Record<string, number>;
  validation_stages: Record<string, { pass: number; fail: number }>;
  first_failing_validation_category: string | null;
  first_failing_source_row_number: number | null;
  required_fields: Record<string, { populated: number; blank: number }>;
};

export type ParseInput = {
  registrar: Registrar;
  fileType: StatementFileType;
  filename: string;
  bytes: Uint8Array;
};

export type PdfExtractionInput = ParseInput;

export interface StatementParser {
  readonly registrar: Registrar;
  parse(input: ParseInput): Promise<NormalizedTransaction[]>;
}

export interface PdfTextExtractor {
  extractRows(input: PdfExtractionInput): Promise<Record<string, unknown>[]>;
}

type FieldAliases = {
  transactionCode: string[];
  units: string[];
  amount: string[];
  nav: string[];
  date: string[];
  pan: string[];
  folioNumber: string[];
  schemeCode: string[];
  schemeName: string[];
  fundHouse: string[];
  category: string[];
  investorName: string[];
  registrarTransactionId: string[];
};

type TransactionCodeRule = {
  type: "BUY" | "SELL" | "SWITCH";
  sign: "positive" | "negative";
  direction: "INFLOW" | "OUTFLOW";
};

const panPattern = /^[A-Z]{5}[0-9]{4}[A-Z]$/;

const fieldAliases: Record<Registrar, FieldAliases> = {
  CAMS: {
    transactionCode: [
      "TRX_TYPE",
      "TRXN_TYPE",
      "TRDESC",
      "TRADESC",
      "TRXN_TYPE_",
      "TRXNTYPE",
    ],
    units: ["UNITS", "TRXN_UNITS", "UNIT_BAL"],
    amount: ["AMOUNT", "TRXN_AMOUNT", "AMT"],
    nav: ["NAV", "PURPRICE"],
    date: ["TRX_DATE", "TRXN_DATE", "POSTDATE"],
    pan: ["PAN", "INV_PAN", "APPL_PAN"],
    folioNumber: ["FOLIO_NO", "FOLIOCHK", "FOLIO"],
    schemeCode: ["SCHEME_CD", "PRODCODE", "PRODUCT"],
    schemeName: ["SCHEME_NM", "SCHEME_NAME"],
    fundHouse: ["FUND_HOUSE", "AMC_NAME"],
    category: ["CATEGORY", "SCHEME_CAT"],
    investorName: ["INV_NAME", "INVESTOR_NAME"],
    registrarTransactionId: ["TRX_ID", "TRXNNO", "REGISTRAR_TXN_ID"],
  },
  KFINTECH: {
    transactionCode: ["TD_TRTYPE", "TRTYPE", "TRDESC", "TRAN_TYPE"],
    units: ["TD_UNITS", "UNITS", "TR_UNITS"],
    amount: ["TD_AMT", "AMOUNT", "TR_AMT"],
    nav: ["TD_NAV", "NAV", "PRICE"],
    date: ["TD_TRDATE", "TR_DATE", "POST_DATE"],
    pan: ["PAN1", "PAN", "IHNO"],
    folioNumber: ["ACNO", "FOLIO_NO", "FOLIO"],
    schemeCode: ["FUNDCODE", "SCHEME", "SCH_CODE"],
    schemeName: ["FUND_DESC", "SCHEME_NAME", "SCH_NAME"],
    fundHouse: ["AMC_CODE", "AMC_NAME", "FUND_HOUSE"],
    category: ["ASSETTYPE", "CATEGORY", "SCHEME_CAT"],
    investorName: ["INVNAME", "INVESTOR_NAME", "NAME"],
    registrarTransactionId: ["TD_TRNO", "TRNO", "REGISTRAR_TXN_ID"],
  },
};

const transactionCodeRules: Record<
  Registrar,
  Record<string, TransactionCodeRule>
> = {
  CAMS: {
    BUY: { type: "BUY", sign: "positive", direction: "INFLOW" },
    PURCHASE: { type: "BUY", sign: "positive", direction: "INFLOW" },
    PUR: { type: "BUY", sign: "positive", direction: "INFLOW" },
    SIP: { type: "BUY", sign: "positive", direction: "INFLOW" },
    SELL: { type: "SELL", sign: "negative", direction: "OUTFLOW" },
    REDEMPTION: { type: "SELL", sign: "negative", direction: "OUTFLOW" },
    RED: { type: "SELL", sign: "negative", direction: "OUTFLOW" },
    SWITCHIN: { type: "SWITCH", sign: "positive", direction: "INFLOW" },
    SWITCH_IN: { type: "SWITCH", sign: "positive", direction: "INFLOW" },
    SWITCHOUT: { type: "SWITCH", sign: "negative", direction: "OUTFLOW" },
    SWITCH_OUT: { type: "SWITCH", sign: "negative", direction: "OUTFLOW" },
    ADDITIONAL_PURCHASE: {
      type: "BUY",
      sign: "positive",
      direction: "INFLOW",
    },
    ADDITIONAL_PURCHASE_SYSTEMATIC: {
      type: "BUY",
      sign: "positive",
      direction: "INFLOW",
    },
    FRESH_PURCHASE_SYSTEMATIC: {
      type: "BUY",
      sign: "positive",
      direction: "INFLOW",
    },
    NFO_FP: { type: "BUY", sign: "positive", direction: "INFLOW" },
    FULL_REDEMPTION: {
      type: "SELL",
      sign: "positive",
      direction: "OUTFLOW",
    },
    PARTIAL_SWITCH_OUT: {
      type: "SWITCH",
      sign: "positive",
      direction: "OUTFLOW",
    },
  },
  KFINTECH: {
    P: { type: "BUY", sign: "positive", direction: "INFLOW" },
    PURCHASE: { type: "BUY", sign: "positive", direction: "INFLOW" },
    ADDITIONAL_PURCHASE: {
      type: "BUY",
      sign: "positive",
      direction: "INFLOW",
    },
    SIP: { type: "BUY", sign: "positive", direction: "INFLOW" },
    R: { type: "SELL", sign: "negative", direction: "OUTFLOW" },
    REDEMPTION: { type: "SELL", sign: "negative", direction: "OUTFLOW" },
    FULL_REDEMPTION: {
      type: "SELL",
      sign: "negative",
      direction: "OUTFLOW",
    },
    SI: { type: "SWITCH", sign: "positive", direction: "INFLOW" },
    SWITCH_IN: { type: "SWITCH", sign: "positive", direction: "INFLOW" },
    SO: { type: "SWITCH", sign: "negative", direction: "OUTFLOW" },
    SWITCH_OUT: { type: "SWITCH", sign: "negative", direction: "OUTFLOW" },
  },
};

function parseDecimal(value: unknown, allowZero = false): number {
  const raw = String(value ?? "").replace(/,/g, "").trim();
  if (!/^-?\d+(\.\d+)?$/.test(raw)) {
    throw new IngestionError("parse_failed");
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed)) {
    throw new IngestionError("parse_failed");
  }
  if (allowZero ? parsed < 0 : parsed <= 0) {
    throw new IngestionError("parse_failed");
  }
  return Math.round(parsed * 1000000) / 1000000;
}

function parseSignedDecimal(value: unknown): number {
  const raw = String(value ?? "").replace(/,/g, "").trim();
  if (!/^-?\d+(\.\d+)?$/.test(raw)) {
    throw new IngestionError("parse_failed");
  }
  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed === 0) {
    throw new IngestionError("parse_failed");
  }
  return Math.round(parsed * 1000000) / 1000000;
}

function parseDate(value: unknown): string {
  const raw = String(value ?? "").trim();
  let year: number;
  let month: number;
  let day: number;
  if (/^\d{8}$/.test(raw)) {
    year = Number(raw.substring(0, 4));
    month = Number(raw.substring(4, 6));
    day = Number(raw.substring(6, 8));
  } else if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    year = Number(raw.substring(0, 4));
    month = Number(raw.substring(5, 7));
    day = Number(raw.substring(8, 10));
  } else {
    throw new IngestionError("parse_failed");
  }
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    Number.isNaN(date.getTime()) ||
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() + 1 !== month ||
    date.getUTCDate() !== day
  ) {
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

function normalizeCode(value: unknown): string {
  const code = String(value ?? "").trim().toUpperCase();
  if (code === "") throw new IngestionError("parse_failed");
  return code.replace(/[\s/-]+/g, "_").replace(/_+/g, "_");
}

function lookupTransactionRule(
  registrar: Registrar,
  value: unknown,
): { code: string; rule: TransactionCodeRule } {
  const code = normalizeCode(value);
  const rule = transactionCodeRules[registrar][code];
  if (rule == null) {
    throw new IngestionError("parse_failed");
  }
  return { code, rule };
}

function validateSignedMagnitude(
  value: number,
  rule: TransactionCodeRule,
): number {
  if (rule.sign === "positive" && value <= 0) {
    throw new IngestionError("parse_failed");
  }
  if (rule.sign === "negative" && value >= 0) {
    throw new IngestionError("parse_failed");
  }
  return Math.round(Math.abs(value) * 1000000) / 1000000;
}

function normalizedPan(value: unknown): string {
  const pan = String(value ?? "").toUpperCase().trim();
  if (!panPattern.test(pan)) {
    throw new IngestionError("parse_failed");
  }
  return pan;
}

function normalizeTransaction(
  record: Record<string, unknown>,
  registrar: Registrar,
  sourceRowNumber: number,
): NormalizedTransaction {
  const aliases = fieldAliases[registrar];
  const { code, rule } = lookupTransactionRule(
    registrar,
    getValue(record, aliases.transactionCode),
  );

  const units = validateSignedMagnitude(
    parseSignedDecimal(getValue(record, aliases.units)),
    rule,
  );
  const amount = validateSignedMagnitude(
    parseSignedDecimal(getValue(record, aliases.amount)),
    rule,
  );
  const nav = parseDecimal(getValue(record, aliases.nav));
  const date = parseDate(getValue(record, aliases.date));
  const clientPan = normalizedPan(getValue(record, aliases.pan));
  const folioNumber = String(
    getValue(record, aliases.folioNumber) ?? "",
  ).trim();
  const schemeCode = String(
    getValue(record, aliases.schemeCode) ?? "",
  ).trim();
  const investorName = String(
    getValue(record, aliases.investorName) ?? "",
  ).trim();

  if (
    folioNumber === "" || schemeCode === "" || investorName === "" ||
    sourceRowNumber <= 0 || !Number.isInteger(sourceRowNumber)
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
      getValue(record, aliases.schemeName) ?? schemeCode,
    ).trim(),
    fundHouse: String(
      getValue(record, aliases.fundHouse) ?? "Mutual Fund",
    ).trim(),
    category: String(
      getValue(record, aliases.category) ?? "Mutual Fund",
    ).trim(),
    transactionType: rule.type,
    transactionDirection: rule.direction,
    registrarTransactionCode: code,
    units,
    nav,
    amount,
    date,
    sourceRowNumber,
    registrarTransactionId:
      String(getValue(record, aliases.registrarTransactionId) ?? "")
        .trim() ||
      undefined,
  };
}

function decodeDbf(
  bytes: Uint8Array,
): {
  recordCount: number;
  fields: DbfField[];
  records: Record<string, unknown>[];
} {
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
      fields.push({ name, type, length, decimalCount: bytes[offset + 17] });
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
  return { recordCount, fields, records };
}

function parseDbf(bytes: Uint8Array): Record<string, unknown>[] {
  return decodeDbf(bytes).records;
}

const diagnosticStages = [
  "structural DBF decode",
  "alias resolution",
  "transaction-code mapping",
  "units/sign validation",
  "amount/sign validation",
  "NAV validation",
  "date validation",
  "PAN validation",
  "required folio",
  "required scheme",
  "required investor name",
  "other parser validation",
] as const;

function emptyStageCounts(): Record<string, { pass: number; fail: number }> {
  return Object.fromEntries(
    diagnosticStages.map((stage) => [stage, { pass: 0, fail: 0 }]),
  );
}

function isPopulated(value: unknown): boolean {
  return String(value ?? "").trim() !== "";
}

/** Temporary investigation-only aggregate view; decoded source values never escape. */
export function inspectCamsDbf(bytes: Uint8Array): CamsDbfDiagnostic {
  const validationStages = emptyStageCounts();
  const requiredFields = Object.fromEntries(
    [
      "transactionCode",
      "units",
      "amount",
      "nav",
      "date",
      "pan",
      "folioNumber",
      "schemeCode",
      "investorName",
    ].map((name) => [name, { populated: 0, blank: 0 }]),
  ) as CamsDbfDiagnostic["required_fields"];
  const aliases = fieldAliases.CAMS;
  let decoded: ReturnType<typeof decodeDbf>;
  try {
    decoded = decodeDbf(bytes);
  } catch (_error) {
    validationStages["structural DBF decode"].fail = 1;
    return {
      record_count: 0,
      structural_decode: "FAIL",
      field_schema: [],
      alias_resolution: Object.fromEntries(
        Object.keys(aliases).map((name) => [name, "MISSING"]),
      ),
      transaction_description_labels: {},
      validation_stages: validationStages,
      first_failing_validation_category: "structural DBF decode",
      first_failing_source_row_number: null,
      required_fields: requiredFields,
    };
  }
  validationStages["structural DBF decode"].pass = 1;
  const aliasResolution = Object.fromEntries(
    Object.entries(aliases).map(([logicalName, candidates]) => [
      logicalName,
      decoded.fields.some((field) =>
          candidates.some((candidate) =>
            candidate.toUpperCase() === field.name.toUpperCase()
          )
        )
        ? "RESOLVED"
        : "MISSING",
    ]),
  ) as CamsDbfDiagnostic["alias_resolution"];
  const aliasFailures =
    Object.values(aliasResolution).filter((value) => value === "MISSING")
      .length;
  validationStages["alias resolution"].pass =
    Object.keys(aliasResolution).length - aliasFailures;
  validationStages["alias resolution"].fail = aliasFailures;
  const labels: Record<string, number> = {};
  let firstCategory: string | null = aliasFailures > 0
    ? "alias resolution"
    : null;
  let firstRow: number | null = null;
  for (const [index, record] of decoded.records.entries()) {
    const row = index + 1;
    for (const logicalName of Object.keys(requiredFields)) {
      const value = getValue(
        record,
        aliases[logicalName as keyof FieldAliases],
      );
      if (isPopulated(value)) requiredFields[logicalName].populated += 1;
      else requiredFields[logicalName].blank += 1;
    }
    const check = (stage: string, fn: () => void): boolean => {
      try {
        fn();
        validationStages[stage].pass += 1;
        return true;
      } catch (_error) {
        validationStages[stage].fail += 1;
        if (firstCategory == null) {
          firstCategory = stage;
          firstRow = row;
        }
        return false;
      }
    };
    let rule: TransactionCodeRule | undefined;
    const codeValue = getValue(record, aliases.transactionCode);
    check("transaction-code mapping", () => {
      const resolved = lookupTransactionRule("CAMS", codeValue);
      rule = resolved.rule;
      labels[resolved.code] = (labels[resolved.code] ?? 0) + 1;
    });
    if (rule == null) labels.UNMAPPED = (labels.UNMAPPED ?? 0) + 1;
    const fallbackRule: TransactionCodeRule = {
      type: "BUY",
      sign: "positive",
      direction: "INFLOW",
    };
    check(
      "units/sign validation",
      () =>
        validateSignedMagnitude(
          parseSignedDecimal(getValue(record, aliases.units)),
          rule ?? fallbackRule,
        ),
    );
    check(
      "amount/sign validation",
      () =>
        validateSignedMagnitude(
          parseSignedDecimal(getValue(record, aliases.amount)),
          rule ?? fallbackRule,
        ),
    );
    check("NAV validation", () => parseDecimal(getValue(record, aliases.nav)));
    check("date validation", () => parseDate(getValue(record, aliases.date)));
    check("PAN validation", () => normalizedPan(getValue(record, aliases.pan)));
    check("required folio", () => {
      if (!isPopulated(getValue(record, aliases.folioNumber))) {
        throw new IngestionError("parse_failed");
      }
    });
    check("required scheme", () => {
      if (!isPopulated(getValue(record, aliases.schemeCode))) {
        throw new IngestionError("parse_failed");
      }
    });
    check("required investor name", () => {
      if (!isPopulated(getValue(record, aliases.investorName))) {
        throw new IngestionError("parse_failed");
      }
    });
  }
  return {
    record_count: decoded.recordCount,
    structural_decode: "PASS",
    field_schema: decoded.fields.map((field) => ({
      name: field.name,
      type: field.type,
      width: field.length,
      decimal_count: field.decimalCount ?? 0,
    })),
    alias_resolution: aliasResolution,
    transaction_description_labels: labels,
    validation_stages: validationStages,
    first_failing_validation_category: firstCategory,
    first_failing_source_row_number: firstRow,
    required_fields: requiredFields,
  };
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
      : await this.extractPdfRows(input);

    const parsed = records.map((record, index) =>
      normalizeTransaction(record, this.registrar, index + 1)
    );
    if (parsed.length === 0) {
      throw new IngestionError("parse_failed");
    }
    return parsed;
  }

  private async extractPdfRows(
    input: ParseInput,
  ): Promise<Record<string, unknown>[]> {
    if (this.pdfTextExtractor == null) {
      throw new IngestionError("unsupported_statement_format");
    }
    return await this.pdfTextExtractor.extractRows(input);
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
  fields?: DbfField[],
): Uint8Array {
  const dbfFields = fields ?? [
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
  const headerLength = 32 + dbfFields.length * 32 + 1;
  const recordLength = 1 +
    dbfFields.reduce((sum, field) => sum + field.length, 0);
  const bytes = new Uint8Array(headerLength + recordLength * records.length);
  const view = new DataView(bytes.buffer);
  bytes[0] = 0x03;
  view.setUint32(4, records.length, true);
  view.setUint16(8, headerLength, true);
  view.setUint16(10, recordLength, true);

  const encoder = new TextEncoder();
  let offset = 32;
  for (const field of dbfFields) {
    bytes.set(encoder.encode(field.name).subarray(0, 11), offset);
    bytes[offset + 11] = field.type.charCodeAt(0);
    bytes[offset + 16] = field.length;
    bytes[offset + 17] = field.decimalCount ?? 0;
    offset += 32;
  }
  bytes[offset] = 0x0d;

  records.forEach((record, recordIndex) => {
    let recordOffset = headerLength + recordIndex * recordLength;
    bytes[recordOffset] = 0x20;
    recordOffset += 1;
    for (const field of dbfFields) {
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
