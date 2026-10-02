import { matchNseResponseDiagnostic } from "./nse_response_diagnostics.ts";
/** B01 supported slices; handbook v1.9.7 pp141–150,157–160,162–164,192–193.
 * No caller PAN/UCC/product selectors. Database-owned source only.
 */
export const READINESS_ENDPOINTS = {
  CLIENT_AUTHORIZATION: "/nsemfdesk/api/v2/reports/client_authorization",
  CLIENT_DETAIL: "/nsemfdesk/api/v2/reports/CLIENT_DETAIL_REPORT",
  TWO_FA: "/nsemfdesk/api/v2/reports/2fa",
  CLIENT_KYC_REPORT: "/nsemfdesk/api/v2/reports/CLIENT_KYC_REPORT",
  FATCA_REPORT: "/nsemfdesk/api/v2/reports/FATCA_REPORT",
  ELOG_REPORT: "/nsemfdesk/api/v2/reports/ELOG_UPLOAD_REPORT",
} as const;
export type ReadinessApi = keyof typeof READINESS_ENDPOINTS;
type Dates = { from_date: string; to_date: string };
type Authorization = Dates & {
  client_code: string;
  auth_status?: "PENDING" | "AUTHORIZE" | "REVIEW";
  date_type: "AUTH_SENT_DATE" | "AUTH_DONE_DATE";
};
type Detail = Omit<Authorization, "date_type"> & {
  date_type: Authorization["date_type"] | "MODIFIED_DATE";
};
export type ReadinessRequest =
  | Authorization
  | Detail
  | (Dates & { client_code: string })
  | { pan_no: string }
  | { pan_pkern_no: string }
  | { client_code: string };
export type ReadinessSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  api: ReadinessApi;
  client_code: string;
  pan: string;
  request: ReadinessRequest;
};
export type ReadinessObservation = {
  nativeStatus: "S" | "F" | null;
  nativeRemarkCategory: string;
  success: boolean;
  recordCount: number;
};
function invalid(): never {
  throw new Error("client_readiness_request_invalid");
}
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function code(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9_-]{1,20}$/.test(value);
}
function date(value: unknown): number {
  if (typeof value !== "string" || !/^\d{2}-\d{2}-\d{4}$/.test(value)) {
    return invalid();
  }
  const iso = value.slice(6) + "-" + value.slice(3, 5) + "-" +
    value.slice(0, 2);
  const n = Date.parse(iso + "T00:00:00Z");
  if (
    !Number.isFinite(n) || iso.startsWith("0000") ||
    new Date(n).toISOString().slice(0, 10) !== iso
  ) return invalid();
  return n;
}
function keys(
  r: Record<string, unknown>,
  required: string[],
  optional: string[] = [],
) {
  if (
    required.some((k) => typeof r[k] !== "string") ||
    Object.keys(r).some((k) => !required.includes(k) && !optional.includes(k))
  ) invalid();
}
export function buildNseClientReadinessRequest(
  source: ReadinessSource,
): ReadinessRequest {
  if (
    !object(source) || !Object.hasOwn(READINESS_ENDPOINTS, source.api) ||
    !code(source.client_code) || typeof source.pan !== "string" ||
    !/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(source.pan) ||
    !object(source.request)
  ) return invalid();
  const r: Record<string, unknown> = source.request;
  switch (source.api) {
    case "CLIENT_AUTHORIZATION":
    case "CLIENT_DETAIL": {
      keys(r, ["from_date", "to_date", "client_code", "date_type"], [
        "auth_status",
      ]);
      const allowed = source.api === "CLIENT_DETAIL"
        ? ["AUTH_SENT_DATE", "AUTH_DONE_DATE", "MODIFIED_DATE"]
        : ["AUTH_SENT_DATE", "AUTH_DONE_DATE"];
      if (
        !allowed.includes(String(r.date_type)) ||
        (Object.hasOwn(r, "auth_status") &&
          (typeof r.auth_status !== "string" ||
            !["PENDING", "AUTHORIZE", "REVIEW"].includes(r.auth_status)))
      ) invalid();
      break;
    }
    case "TWO_FA":
      // product_type requires owned product_id. No durable product lineage yet;
      // client + dates is a separate documented path, not a blank-ID product query.
      keys(r, ["from_date", "to_date", "client_code"]);
      break;
    case "CLIENT_KYC_REPORT":
      keys(r, ["pan_no"]);
      if (r.pan_no !== source.pan) invalid();
      break;
    case "FATCA_REPORT":
      keys(r, ["pan_pkern_no"]);
      if (r.pan_pkern_no !== source.pan) invalid();
      break;
    case "ELOG_REPORT":
      keys(r, ["client_code"]);
      break;
  }
  if ("client_code" in r && r.client_code !== source.client_code) invalid();
  if ("from_date" in r) {
    // These three sections say seven-day GAP and show Jan 21–28, unlike p78.
    const days = (date(r.to_date) - date(r.from_date)) / 86400000;
    if (days < 0 || days > 7) invalid();
  }
  return { ...source.request };
}

// Each row schema below is separately transcribed from its handbook sample.
// Samples do not establish requiredness for every field. Scope/status columns
// below are the minimum supported interpretation; present fields must be strings.
// Unknown string columns stay evidence-only. No statuses are promoted to consent.
function stringRow(
  row: unknown,
  required: string[],
): row is Record<string, string> {
  return object(row) && required.every((k) => typeof row[k] === "string") &&
    Object.values(row).every((v) => typeof v === "string");
}
function ownedClient(
  row: Record<string, string>,
  source: ReadinessSource,
): boolean {
  return row.client_code === source.client_code;
}
function authorization(row: unknown, source: ReadinessSource): boolean {
  return stringRow(row, [
    "client_code",
    "primary_holder_pan",
    "auth_status",
    "first_holder_auth_status",
  ]) && ownedClient(row, source) && row.primary_holder_pan === source.pan;
}
function detail(row: unknown, source: ReadinessSource): boolean {
  return stringRow(row, [
    "client_code",
    "primary_holder_pan",
    "auth_status",
    "ucc_status",
    "primary_holder_kyc_checked",
    "primary_holder_kyc_status",
  ]) && ownedClient(row, source) && row.primary_holder_pan === source.pan;
}
function twoFa(row: unknown, source: ReadinessSource): boolean {
  return stringRow(row, [
    "client_code",
    "product_type",
    "product_id",
    "primary_holder_authentication_status",
  ]) && ownedClient(row, source) &&
    ["PUR", "RED", "SWITCH", "SIP", "STP", "SWP"].includes(row.product_type) &&
    /^[A-Za-z0-9_-]+$/.test(row.product_id);
}
function kyc(row: unknown, source: ReadinessSource): boolean {
  return stringRow(row, [
    "client_code",
    "client_pan",
    "holding_type",
    "holder_name",
    "holder_dob",
    "kyc_status",
    "status_remark",
  ]) && ownedClient(row, source) &&
    row.client_pan === (source.request as { pan_no: string }).pan_no;
}
function fatca(row: unknown, source: ReadinessSource): boolean {
  return stringRow(row, [
    "pan_rp",
    "pekrn",
    "camsuploadstatus",
    "camsresponsestatus",
    "kfinuploadstatus",
    "kfinresponsestatus",
  ]) &&
    row.pan_rp === (source.request as { pan_pkern_no: string }).pan_pkern_no;
}
function elog(row: unknown, source: ReadinessSource): boolean {
  return stringRow(row, [
    "client_code",
    "pan",
    "pan_type",
    "elog_type",
    "cams_status",
    "kfin_status",
  ]) && ownedClient(row, source) && row.pan === source.pan;
}
// The evidence classifier also runs in PostgreSQL. JSON with decoded NUL or
// lone UTF-16 surrogates cannot be represented in jsonb; reject it consistently.
function databaseJsonCompatible(value: unknown): boolean {
  const pending: unknown[] = [value];
  while (pending.length) {
    const item = pending.pop();
    if (typeof item === "number" && !Number.isFinite(item)) return false;
    if (
      typeof item === "string" &&
      /\u0000|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/
        .test(item)
    ) return false;
    if (item && typeof item === "object") {
      for (const [key, child] of Object.entries(item)) pending.push(key, child);
    }
  }
  return true;
}

export function parseNseClientReadinessResponse(
  raw: string,
  source: ReadinessSource,
): ReadinessObservation {
  let nativeStatus: "S" | "F" | null = null;
  const fail = (
    category = "client_readiness_response_invalid",
  ): ReadinessObservation => ({
    nativeStatus,
    nativeRemarkCategory: category,
    success: false,
    recordCount: 0,
  });
  try {
    buildNseClientReadinessRequest(source);
    const envelope: unknown = JSON.parse(raw);
    if (!object(envelope) || !databaseJsonCompatible(envelope)) return fail();
    if (envelope.response_status !== "S" && envelope.response_status !== "F") {
      return fail();
    }
    nativeStatus = envelope.response_status;
    // No B01 section defines a complete failure schema. F is terminal and
    // never yields a trusted row, even if accompanied by unexpected data.
    if (nativeStatus === "F") return fail("client_readiness_business_failed");
    const hasRemark = Object.hasOwn(envelope, "error_remark");
    const requiresRemark = ["CLIENT_AUTHORIZATION", "CLIENT_DETAIL", "TWO_FA"]
      .includes(source.api);
    if (
      (requiresRemark && !hasRemark) ||
      (hasRemark && source.api === "ELOG_REPORT" &&
        typeof envelope.error_remark !== "string") ||
      (hasRemark && source.api !== "ELOG_REPORT" &&
        source.api !== "CLIENT_KYC_REPORT" &&
        envelope.error_remark !== "")
    ) return fail();
    const total = envelope.report_data_total;
    if (
      !((typeof total === "number" && Number.isSafeInteger(total) &&
        total >= 0) || (typeof total === "string" && /^\d+$/.test(total)))
    ) return fail();
    if (
      !Array.isArray(envelope.report_data) ||
      Number(total) !== envelope.report_data.length ||
      envelope.report_data.length > 10000
    ) return fail();
    const rows = envelope.report_data;
    if (
      source.api === "CLIENT_KYC_REPORT" && hasRemark &&
      envelope.error_remark !== "" &&
      matchNseResponseDiagnostic(
          "NSE_CLIENT_KYC_REPORT",
          nativeStatus,
          envelope.error_remark,
          Number(total),
          rows,
        )?.outcome !== "SUCCESS"
    ) return fail();
    let validate: (r: unknown, s: ReadinessSource) => boolean;
    switch (source.api) {
      case "CLIENT_AUTHORIZATION":
        validate = authorization;
        break;
      case "CLIENT_DETAIL":
        validate = detail;
        break;
      case "TWO_FA":
        validate = twoFa;
        break;
      case "CLIENT_KYC_REPORT":
        validate = kyc;
        break;
      case "FATCA_REPORT":
        validate = fatca;
        break;
      case "ELOG_REPORT":
        validate = elog;
        break;
    }
    const seen = new Set<string>();
    for (const row of rows) {
      if (!validate(row, source)) {
        return fail("client_readiness_row_scope_invalid");
      }
      const r = row as Record<string, string>;
      // Natural row identity where documented; full row identity for upload
      // history avoids inventing a uniqueness rule for successive uploads.
      const identity = source.api === "TWO_FA"
        ? JSON.stringify([r.product_type, r.product_id])
        : ["CLIENT_AUTHORIZATION", "CLIENT_DETAIL", "CLIENT_KYC_REPORT"]
            .includes(source.api)
        ? r.client_code
        : JSON.stringify(Object.keys(r).sort().map((k) => [k, r[k]]));
      if (seen.has(identity)) return fail("client_readiness_duplicate_rows");
      seen.add(identity);
    }
    return {
      nativeStatus,
      nativeRemarkCategory: "client_readiness_report_received",
      success: true,
      recordCount: rows.length,
    };
  } catch {
    return fail();
  }
}
