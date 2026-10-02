import {
  NSE_MASTER_MAX_BYTES,
  NseMasterError,
  nseMasterSha256,
} from "./nse_master_download.ts";

// WebfileStructure pp79–83. These are explicit document profiles, not observed API aliases.
// Raw mode/status/frequency/dates codes have no commissioned eligibility interpretation.
export const NSE_SYSTEMATIC_PARSER_VERSION = "nse-systematic-web-v1";
export type NseSystematicVariant = "SIP" | "STP" | "SWP";
export const NSE_SYSTEMATIC_MAX_ROWS = 100000;
export type NseProductLineage = Readonly<
  { sourceLine: number; sourceRowSha256: string }
>;
export type NseSystematicParse<V extends NseSystematicVariant, R> = Readonly<{
  fileType: V;
  parserVersion: typeof NSE_SYSTEMATIC_PARSER_VERSION;
  layoutId: string;
  sourceSha256: string;
  sourceBytes: number;
  authority: "REFERENCE_ONLY";
  rows: readonly R[];
}>;
function invalid(code: string): never {
  throw new NseMasterError("nse_systematic_" + code);
}
function field(value: string, max: number): string {
  if (
    !value || [...value].length > max || value !== value.replace(/^ +| +$/g, "")
  ) {
    invalid("field_invalid");
  }
  return value;
}
function integer(value: string, digits: number): number {
  if (!new RegExp(`^[0-9]{1,${digits}}$`).test(value)) {
    invalid("number_invalid");
  }
  return Number(value);
}
// Fixed-scale decimal strings avoid binary floating-point amounts/units.
function decimal(value: string, scale: number): string {
  if (
    !new RegExp(`^[0-9]{1,${12 - scale}}(\\.[0-9]{1,${scale}})?$`).test(value)
  ) invalid("number_invalid");
  const [whole, fraction = ""] = value.split(".");
  return BigInt(whole).toString() + "." + fraction.padEnd(scale, "0");
}
function blank(value: string): "" {
  if (value !== "") invalid("reserved_field");
  return "";
}
function pause(value: string): "N" {
  if (value !== "N") invalid("pause_uncharacterized");
  return "N";
}
async function parse<V extends NseSystematicVariant, R>(
  bytes: Uint8Array,
  fileType: V,
  headers: readonly string[],
  row: (cells: string[], lineage: NseProductLineage) => R,
): Promise<NseSystematicParse<V, R>> {
  // Own the bytes before the first await: a caller cannot race the digest and parser.
  if (bytes.length === 0 || bytes.length > NSE_MASTER_MAX_BYTES) {
    invalid("size_invalid");
  }
  const source = bytes.slice();
  let body: string;
  try {
    body = new TextDecoder("utf-8", { fatal: true }).decode(source);
  } catch {
    return invalid("encoding_invalid");
  }
  body = body.replaceAll("\r\n", "\n");
  if (/[\x00-\x09\x0b-\x1f\x7f\ufeff]/u.test(body)) invalid("framing_invalid");
  if (body.endsWith("\n")) body = body.slice(0, -1);
  const lines = body.split("\n");
  if (lines[0] !== headers.join("|")) invalid("layout_unknown");
  if (lines.length < 2 || lines.length - 1 > NSE_SYSTEMATIC_MAX_ROWS) {
    invalid("row_count_invalid");
  }
  const rows: R[] = [];
  const seen = new Set<string>();
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (!line || [...line].length > 4096) invalid("row_invalid");
    const cells = line.split("|");
    if (cells.length !== headers.length) invalid("column_count");
    if (seen.has(line)) invalid("duplicate_row");
    seen.add(line);
    const lineage = Object.freeze({
      sourceLine: i + 1,
      sourceRowSha256: await nseMasterSha256(new TextEncoder().encode(line)),
    });
    rows.push(Object.freeze(row(cells, lineage)));
  }
  return Object.freeze({
    fileType,
    parserVersion: NSE_SYSTEMATIC_PARSER_VERSION,
    layoutId: "NSE_WEB_" + fileType + "_V1",
    sourceSha256: await nseMasterSha256(source),
    sourceBytes: source.length,
    authority: "REFERENCE_ONLY",
    rows: Object.freeze(rows),
  });
}

export const NSE_SIP_MASTER_HEADERS = Object.freeze([
  "AMC CODE",
  "AMC NAME",
  "SCHEME CODE",
  "SCHEME NAME",
  "SIP TRANSACTION MODE",
  "SIP FREQUENCY",
  "SIP DATES",
  "SIP MINIMUM GAP",
  "SIP MAXIMUM GAP",
  "SIP INSTALLMENT GAP",
  "SIP STATUS",
  "SIP MINIMUM INSTALLMENT AMOUNT",
  "SIP MAXIMUM INSTALLMENT AMOUNT",
  "SIP MULTIPLIER AMOUNT",
  "SIP MINIMUM INSTALLMENT NUMBERS",
  "SIP MAXIMUM INSTALLMENT NUMBERS",
  "SCHEME ISIN",
  "SCHEME TYPE",
  "PAUSE FLAG",
  "PAUSE MINIMUM INSTALLMENTS",
  "PAUSE MAXIMUM INSTALLMENTS",
  "PAUSE MODIFICATION COUNT",
  "FILLER 1",
  "FILLER 2",
  "FILLER 3",
  "FILLER 4",
  "FILLER 5",
]);
export type NseSipProduct =
  & NseProductLineage
  & Readonly<{
    amcCode: string;
    amcName: string;
    schemeCode: string;
    schemeName: string;
    transactionMode: string;
    frequency: string;
    dates: string;
    minimumGap: number;
    maximumGap: number;
    installmentGap: number;
    status: string;
    minimumInstallmentAmount: string;
    maximumInstallmentAmount: string;
    multiplierAmount: number;
    minimumInstallments: number;
    maximumInstallments: number;
    schemeIsin: string;
    schemeType: string;
    pauseFlag: "N";
    pauseMinimumInstallments: "";
    pauseMaximumInstallments: "";
    pauseModificationCount: "";
    filler1: "";
    filler2: "";
    filler3: "";
    filler4: "";
    filler5: "";
  }>;
export function parseNseSipMaster(
  bytes: Uint8Array,
): Promise<NseSystematicParse<"SIP", NseSipProduct>> {
  return parse(bytes, "SIP", NSE_SIP_MASTER_HEADERS, (c, lineage) => ({
    ...lineage,
    amcCode: field(c[0], 100),
    amcName: field(c[1], 255),
    schemeCode: field(c[2], 30),
    schemeName: field(c[3], 200),
    transactionMode: field(c[4], 1),
    frequency: field(c[5], 15),
    dates: field(c[6], 100),
    minimumGap: integer(c[7], 5),
    maximumGap: integer(c[8], 5),
    installmentGap: integer(c[9], 5),
    status: field(c[10], 1),
    minimumInstallmentAmount: decimal(c[11], 2),
    maximumInstallmentAmount: decimal(c[12], 2),
    multiplierAmount: integer(c[13], 5),
    minimumInstallments: integer(c[14], 5),
    maximumInstallments: integer(c[15], 5),
    schemeIsin: field(c[16], 12),
    schemeType: field(c[17], 25),
    pauseFlag: pause(c[18]),
    pauseMinimumInstallments: blank(c[19]),
    pauseMaximumInstallments: blank(c[20]),
    pauseModificationCount: blank(c[21]),
    filler1: blank(c[22]),
    filler2: blank(c[23]),
    filler3: blank(c[24]),
    filler4: blank(c[25]),
    filler5: blank(c[26]),
  }));
}

export const NSE_STP_MASTER_HEADERS = Object.freeze([
  "AMC CODE",
  "AMC NAME",
  "NSE SCHEME CODE",
  "SCHEME NAME",
  "SCHEME ISIN",
  "SCHEME TYPE",
  "ASTP TRANSACTION MODE",
  "ASTP IN MINIMUM INSTALLMENT AMOUNT",
  "ASTP IN MAXIMUM INSTALLMENT AMOUNT",
  "ASTP IN MULTIPLIER AMOUNT",
  "ASTP OUT MINIMUM INSTALLMENT AMOUNT",
  "ASTP OUT MAXIMUM INSTALLMENT AMOUNT",
  "ASTP OUT MULTIPLIER AMOUNT",
  "ASTP MINIMUM INSTALLMENT UNITS",
  "ASTP MAXIMUM INSTALLMENT UNITS",
  "ASTP MULTIPLIER UNITS",
  "ASTP MINIMUM INSTALLMENT NUMBERS",
  "ASTP MAXIMUM INSTALLMENT NUMBERS",
  "ASTP REG IN",
  "ASTP REG OUT",
  "ASTP FREQUENCY",
  "ASTP DATES",
  "ASTP MINIMUM GAP",
  "ASTP MAXIMUM GAP",
  "ASTP INSTALLMENT GAP",
  "ASTP STATUS",
]);
export type NseStpProduct =
  & NseProductLineage
  & Readonly<{
    amcCode: string;
    amcName: string;
    schemeCode: string;
    schemeName: string;
    schemeIsin: string;
    schemeType: string;
    transactionMode: string;
    inMinimumInstallmentAmount: string;
    inMaximumInstallmentAmount: string;
    inMultiplierAmount: number;
    outMinimumInstallmentAmount: string;
    outMaximumInstallmentAmount: string;
    outMultiplierAmount: number;
    minimumInstallmentUnits: string;
    maximumInstallmentUnits: string;
    multiplierUnits: number;
    minimumInstallments: number;
    maximumInstallments: number;
    registrationIn: number;
    registrationOut: number;
    frequency: string;
    dates: string;
    minimumGap: number;
    maximumGap: number;
    installmentGap: number;
    status: string;
  }>;
export function parseNseStpMaster(
  bytes: Uint8Array,
): Promise<NseSystematicParse<"STP", NseStpProduct>> {
  return parse(bytes, "STP", NSE_STP_MASTER_HEADERS, (c, lineage) => ({
    ...lineage,
    amcCode: field(c[0], 100),
    amcName: field(c[1], 255),
    schemeCode: field(c[2], 30),
    schemeName: field(c[3], 200),
    schemeIsin: field(c[4], 12),
    schemeType: field(c[5], 25),
    transactionMode: field(c[6], 2),
    inMinimumInstallmentAmount: decimal(c[7], 2),
    inMaximumInstallmentAmount: decimal(c[8], 2),
    inMultiplierAmount: integer(c[9], 5),
    outMinimumInstallmentAmount: decimal(c[10], 2),
    outMaximumInstallmentAmount: decimal(c[11], 2),
    outMultiplierAmount: integer(c[12], 5),
    minimumInstallmentUnits: decimal(c[13], 2),
    maximumInstallmentUnits: decimal(c[14], 2),
    multiplierUnits: integer(c[15], 5),
    minimumInstallments: integer(c[16], 5),
    maximumInstallments: integer(c[17], 5),
    registrationIn: integer(c[18], 1),
    registrationOut: integer(c[19], 1),
    frequency: field(c[20], 15),
    dates: field(c[21], 100),
    minimumGap: integer(c[22], 5),
    maximumGap: integer(c[23], 5),
    installmentGap: integer(c[24], 5),
    status: field(c[25], 1),
  }));
}

export const NSE_SWP_MASTER_HEADERS = Object.freeze([
  "AMC CODE",
  "AMC NAME",
  "NSE SCHEME CODE",
  "SCHEME NAME",
  "SCHEME ISIN",
  "SCHEME TYPE",
  "SWP TRANSACTION MODE",
  "SWP MINIMUM INSTALLMENT AMOUNT",
  "SWP MAXIMUM INSTALLMENT AMOUNT",
  "SWP MULTIPLIER AMOUNT",
  "SWP MINIMUM INSTALLMENT UNITS",
  "SWP MAXIMUM INSTALLMENT UNITS",
  "SWP MULTIPLIER UNITS",
  "SWP MINIMUM INSTALLMENT NUMBERS",
  "SWP MAXIMUM INSTALLMENT NUMBERS",
  "SWP FREQUENCY",
  "SWP DATES",
  "SWP MINIMUM GAP",
  "SWP MAXIMUM GAP",
  "SWP INSTALLMENT GAP",
  "SWP STATUS",
]);
export type NseSwpProduct =
  & NseProductLineage
  & Readonly<{
    amcCode: string;
    amcName: string;
    schemeCode: string;
    schemeName: string;
    schemeIsin: string;
    schemeType: string;
    transactionMode: string;
    minimumInstallmentAmount: string;
    maximumInstallmentAmount: string;
    multiplierAmount: number;
    minimumInstallmentUnits: string;
    maximumInstallmentUnits: string;
    multiplierUnits: number;
    minimumInstallments: number;
    maximumInstallments: number;
    frequency: string;
    dates: string;
    minimumGap: number;
    maximumGap: number;
    installmentGap: number;
    status: string;
  }>;
export function parseNseSwpMaster(
  bytes: Uint8Array,
): Promise<NseSystematicParse<"SWP", NseSwpProduct>> {
  return parse(bytes, "SWP", NSE_SWP_MASTER_HEADERS, (c, lineage) => ({
    ...lineage,
    amcCode: field(c[0], 100),
    amcName: field(c[1], 255),
    schemeCode: field(c[2], 30),
    schemeName: field(c[3], 200),
    schemeIsin: field(c[4], 12),
    schemeType: field(c[5], 25),
    transactionMode: field(c[6], 2),
    minimumInstallmentAmount: decimal(c[7], 2),
    maximumInstallmentAmount: decimal(c[8], 2),
    multiplierAmount: integer(c[9], 5),
    minimumInstallmentUnits: decimal(c[10], 3),
    maximumInstallmentUnits: decimal(c[11], 3),
    multiplierUnits: integer(c[12], 5),
    minimumInstallments: integer(c[13], 5),
    maximumInstallments: integer(c[14], 5),
    frequency: field(c[15], 15),
    dates: field(c[16], 100),
    minimumGap: integer(c[17], 5),
    maximumGap: integer(c[18], 5),
    installmentGap: integer(c[19], 5),
    status: field(c[20], 1),
  }));
}

export type NseParsedSystematicMaster =
  | NseSystematicParse<"SIP", NseSipProduct>
  | NseSystematicParse<"STP", NseStpProduct>
  | NseSystematicParse<"SWP", NseSwpProduct>;
export function parseNseSystematicMaster(
  fileType: NseSystematicVariant,
  bytes: Uint8Array,
): Promise<NseParsedSystematicMaster> {
  switch (fileType) {
    case "SIP":
      return parseNseSipMaster(bytes);
    case "STP":
      return parseNseStpMaster(bytes);
    case "SWP":
      return parseNseSwpMaster(bytes);
    default:
      return invalid("variant_invalid");
  }
}
