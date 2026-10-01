/** B04, NNF 1.9.7 pp164–180. Observations only; no schedule projection. */
export const SIP_XSIP_REPORTS_ENDPOINTS = {
  SIP_REG_REPORT: "/nsemfdesk/api/v2/reports/SIP_REG_REPORT",
  SIP_CAN_REPORT: "/nsemfdesk/api/v2/reports/SIP_CAN_REPORT",
  SIP_INST_DUE_REPORT: "/nsemfdesk/api/v2/reports/SIP_INST_DUE_REPORT",
  SIP_TOPUP_REPORT: "/nsemfdesk/api/v2/reports/SIP_TOPUP_REPORT",
  STEPUP_REG_REPORT: "/nsemfdesk/api/v2/reports/STEPUP_REG_REPORT",
  XSIP_REG_REPORT: "/nsemfdesk/api/v2/reports/XSIP_REG_REPORT",
  XSIP_CAN_REPORT: "/nsemfdesk/api/v2/reports/XSIP_CAN_REPORT",
  XSIP_INST_DUE_REPORT: "/nsemfdesk/api/v2/reports/XSIP_INST_DUE_REPORT",
  XSIP_TOPUP_REPORT: "/nsemfdesk/api/v2/reports/XSIP_TOPUP_REPORT",
} as const;
export type SipXsipReportsApi = keyof typeof SIP_XSIP_REPORTS_ENDPOINTS;
export type OwnedRegistration = Record<string, string>;
export type SipXsipReportsSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  api: SipXsipReportsApi;
  client_code: string;
  pan: string;
  today: string;
  selectors: { mode: "client" | "member"; rows: OwnedRegistration[] };
  request: Record<string, string>;
};
export type SipXsipReportsObservation = {
  nativeStatus: "S" | "F" | null;
  nativeRemarkCategory: string;
  success: boolean;
  recordCount: number;
};
function object(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}
function invalid(): never {
  throw new Error("sip_xsip_reports_request_invalid");
}
function date(v: unknown): string {
  if (typeof v !== "string" || !/^\d{2}-\d{2}-\d{4}$/.test(v)) invalid();
  const iso = v.slice(6) + "-" + v.slice(3, 5) + "-" + v.slice(0, 2);
  const n = Date.parse(iso + "T00:00:00Z");
  if (
    !Number.isFinite(n) || iso.startsWith("0000") ||
    new Date(n).toISOString().slice(0, 10) !== iso
  ) invalid();
  return iso;
}
/** Explicit India market day; tests supply deterministic time. */
export function nseReportToday(now: Date): string {
  return new Date(now.getTime() + 19800000).toISOString().slice(0, 10);
}
function dates(
  request: Record<string, string>,
  days: number,
  nonPast: boolean,
  today: string,
  required: boolean,
) {
  const hasFrom = Object.hasOwn(request, "from_date"),
    hasTo = Object.hasOwn(request, "to_date");
  if (!hasFrom && !hasTo && !required) return;
  const from = date(request.from_date), to = date(request.to_date);
  const gap = (Date.parse(to) - Date.parse(from)) / 86400000;
  if (gap <= 0 || gap > days || (nonPast && from < today)) invalid();
}
const registrationBusinessFields = [
  "member_unique_id",
  "member_code",
  "rta_scheme_code",
  "frequency_type",
  "start_date",
  "end_date",
  "installments_amount",
];
function registrationFields(api: SipXsipReportsApi) {
  if (api === "SIP_REG_REPORT") {
    return ["sip_reg_number", "sip_reg_date", ...registrationBusinessFields];
  }
  if (api === "XSIP_REG_REPORT") {
    return [
      "xsip_registration_no",
      "xsip_registration_date",
      ...registrationBusinessFields,
    ];
  }
  return invalid();
}
function requestFor(
  s: SipXsipReportsSource,
  api: SipXsipReportsApi,
  days: number,
  nonPast: boolean,
  members: boolean,
): Record<string, string> {
  if (
    !object(s) || s.api !== api || typeof s.client_code !== "string" ||
    !/^[A-Za-z0-9_-]{1,20}$/.test(s.client_code) ||
    typeof s.today !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(s.today) ||
    !object(s.request) || !object(s.selectors) ||
    !Array.isArray(s.selectors.rows) ||
    Object.keys(s.selectors).some((k) => !["mode", "rows"].includes(k))
  ) invalid();
  const r = s.request;
  let expected: string, field: string;
  if (s.selectors.mode === "client" && s.selectors.rows.length === 0) {
    field = "client_code";
    expected = s.client_code;
  } else if (
    members && s.selectors.mode === "member" && s.selectors.rows.length >= 1 &&
    s.selectors.rows.length <= 50
  ) {
    const keys = registrationFields(api),
      seen = new Set<string>(),
      ids = new Set<string>();
    for (const row of s.selectors.rows) {
      if (
        !object(row) || Object.keys(row).length !== keys.length ||
        keys.some((k) => typeof row[k] !== "string" || !row[k].trim()) ||
        !/^[A-Za-z0-9_-]{1,100}$/.test(row.member_unique_id) ||
        !/^[0-9]+$/.test(row[keys[0]]) || !/^[0-9]+$/.test(row.member_code) ||
        seen.has(row.member_unique_id) || ids.has(row[keys[0]])
      ) invalid();
      seen.add(row.member_unique_id);
      ids.add(row[keys[0]]);
    }
    field = "member_unique_ids";
    expected = s.selectors.rows.map((r) => r.member_unique_id).join(",");
  } else return invalid();
  // Only the effective owned selector is emitted. Registration/parent IDs are
  // disabled, never allowed to override owned client/member scope.
  if (
    r[field] !== expected ||
    Object.keys(r).some((k) => ![field, "from_date", "to_date"].includes(k)) ||
    Object.values(r).some((v) => typeof v !== "string")
  ) invalid();
  // Tables require dates when registration ID and UCC are absent, including
  // the member-only slice. An effective member/UCC selector ignores these dates.
  dates(r, days, nonPast, s.today, field === "member_unique_ids");
  return { ...r };
}
// SIP_REG_REPORT: sip_reg_id > member_unique_ids > client_code > date fallback.
export function buildSipRegReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "SIP_REG_REPORT", 31, false, true);
}
// SIP_CAN_REPORT: sip_reg_id > client_code > date fallback.
export function buildSipCanReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "SIP_CAN_REPORT", 31, false, false);
}
// SIP_INST_DUE_REPORT: sip_reg_id > client_code > date fallback.
export function buildSipInstDueReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "SIP_INST_DUE_REPORT", 7, true, false);
}
// SIP_TOPUP_REPORT: parent_sip_reg_id > client_code > date fallback.
export function buildSipTopupReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "SIP_TOPUP_REPORT", 31, false, false);
}
// STEPUP_REG_REPORT: sip_reg_id > client_code > date fallback.
export function buildStepupRegReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "STEPUP_REG_REPORT", 31, false, false);
}
// XSIP_REG_REPORT: xsip_reg_id > member_unique_ids > client_code > date fallback.
export function buildXsipRegReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "XSIP_REG_REPORT", 31, false, true);
}
// XSIP_CAN_REPORT: xsip_reg_id > client_code > date fallback.
export function buildXsipCanReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "XSIP_CAN_REPORT", 31, false, false);
}
// XSIP_INST_DUE_REPORT: xsip_reg_id > client_code > date fallback.
export function buildXsipInstDueReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "XSIP_INST_DUE_REPORT", 7, true, false);
}
// XSIP_TOPUP_REPORT: parent_xsip_reg_id > client_code > date fallback.
export function buildXsipTopupReportRequest(s: SipXsipReportsSource) {
  return requestFor(s, "XSIP_TOPUP_REPORT", 31, false, false);
}
export function buildNseSipXsipReportsRequest(
  s: SipXsipReportsSource,
): Record<string, string> {
  switch (s.api) {
    case "SIP_REG_REPORT":
      return buildSipRegReportRequest(s);
    case "SIP_CAN_REPORT":
      return buildSipCanReportRequest(s);
    case "SIP_INST_DUE_REPORT":
      return buildSipInstDueReportRequest(s);
    case "SIP_TOPUP_REPORT":
      return buildSipTopupReportRequest(s);
    case "STEPUP_REG_REPORT":
      return buildStepupRegReportRequest(s);
    case "XSIP_REG_REPORT":
      return buildXsipRegReportRequest(s);
    case "XSIP_CAN_REPORT":
      return buildXsipCanReportRequest(s);
    case "XSIP_INST_DUE_REPORT":
      return buildXsipInstDueReportRequest(s);
    case "XSIP_TOPUP_REPORT":
      return buildXsipTopupReportRequest(s);
    default:
      return invalid();
  }
}
const SIP_REG_REPORT_FIELDS = [
  "status",
  "member_code",
  "client_code",
  "client_name",
  "pg_bank_ref_no",
  "sip_reg_number",
  "sip_reg_date",
  "amc_name",
  "rta_scheme_code",
  "scheme_name",
  "frequency_type",
  "start_date",
  "end_date",
  "installments_amount",
  "entry_by",
  "dpc_flag",
  "dp_trans",
  "first_order_today",
  "sub_broker_code",
  "euin",
  "euin_declaration",
  "folio_number",
  "remarks",
  "sub_broker_arn_code",
  "no_of_installments",
  "exchange_remark",
  "health_declaration_flag",
  "nominee_dob",
  "disclaimer_flag",
  "internal_ref_no",
  "primary_holder_email",
  "primary_holder_mobile",
  "second_holder_email",
  "second_holder_mobile",
  "third_holder_email",
  "third_holder_mobile",
  "member_unique_id",
];
const SIP_CAN_REPORT_FIELDS = [
  "member_code",
  "client_code",
  "client_name",
  "internal_ref_num",
  "sip_registration_no",
  "sip_registration_date",
  "sip_cancellation_date",
  "amc_name",
  "scheme_code",
  "scheme_name",
  "frequency_type",
  "start_date",
  "end_date",
  "next_due_date",
  "no_of_installments_paid",
  "installments_amt",
  "total_installment_amt_paid",
  "cancelled_by",
  "sip_status",
  "remark",
];
const SIP_INST_DUE_REPORT_FIELDS = [
  "member_code",
  "client_code",
  "client_name",
  "internal_ref_no",
  "sip_reg_number",
  "reg_date",
  "amc_name",
  "scheme_code",
  "scheme_name",
  "frequency_type",
  "installment_amt",
  "due_date",
  "prev_paid_date",
  "no_of_installments_paid",
  "total_installment_amt_paid",
  "entry_by",
  "dp_trans",
  "first_order_today",
];
const SIP_TOPUP_REPORT_FIELDS = [
  "member_code",
  "client_code",
  "client_name",
  "reg_no",
  "scheme_code",
  "scheme_name",
  "sip_xsip_amount",
  "start_date",
  "end_date",
  "top_up_amount",
  "date_of_activation",
  "entry_by",
  "principle_sip_reg_no",
  "principle_sip_internal_ref_no",
  "last_child_sip_reg_no",
  "top_up_frequency",
  "top_up_status",
];
const STEPUP_REG_REPORT_FIELDS = [
  "status",
  "member_code",
  "client_code",
  "client_name",
  "sip_xsip_regn_number",
  "sip_xsip_regn_date",
  "sip_xsip_type",
  "amc_name",
  "rta_scheme_code",
  "scheme_code",
  "scheme_name",
  "frequency_type",
  "start_date",
  "end_date",
  "stepup_start__effective_date",
  "stepup_enddate",
  "stepup_frequency",
  "stepup_amount",
  "entry_by",
];
const XSIP_REG_REPORT_FIELDS = [
  "status",
  "member_code",
  "client_code",
  "client_name",
  "pg_bank_ref_no",
  "xsip_registration_no",
  "xsip_registration_date",
  "amc_name",
  "rta_scheme_code",
  "scheme_name",
  "frequency_type",
  "start_date",
  "end_date",
  "installments_amount",
  "brokerage",
  "entry_by",
  "nse_mandate_id",
  "dpc_flag",
  "dp_trans",
  "sub_broker",
  "euin_no",
  "euin_declaration",
  "first_order_today",
  "folio_number",
  "remarks",
  "sub_broker_arn",
  "no_of_installments",
  "exchange_remark",
  "health_declaration_flag",
  "nominee_dob",
  "disclaimer_flag",
  "internal_ref_no",
  "primary_holder_email",
  "primary_holder_mobile",
  "second_holder_email",
  "second_holder_mobile",
  "third_holder_email",
  "third_holder_mobile",
  "member_unique_id",
];
const XSIP_CAN_REPORT_FIELDS = [
  "status",
  "member_code",
  "client_code",
  "client_name",
  "internal_ref_num",
  "xsip_registration_no",
  "xsip_registration_date",
  "xsip_cancellation_date",
  "amc_name",
  "scheme_code",
  "scheme_name",
  "frequency_type",
  "start_date",
  "end_date",
  "next_due_date",
  "no_of_installments_paid",
  "installments_amt",
  "brokerage",
  "total_installment_amt_paid",
  "cancelled_by",
  "nse_mandate_id",
  "remark",
];
const XSIP_INST_DUE_REPORT_FIELDS = [
  "member_code",
  "client_code",
  "client_name",
  "internal_ref_no",
  "sip_reg_number",
  "reg_date",
  "amc_name",
  "scheme_code",
  "scheme_name",
  "frequency_type",
  "installment_amt",
  "due_date",
  "prev_paid_date",
  "no_of_installments_paid",
  "total_installment_amt_paid",
  "entry_by",
  "mandate_id",
  "dp_trans",
  "first_order_today",
];
const XSIP_TOPUP_REPORT_FIELDS = [
  "member_code",
  "client_code",
  "client_name",
  "reg_no",
  "scheme_code",
  "scheme_name",
  "sip_xsip_amount",
  "start_date",
  "end_date",
  "top_up_amount",
  "date_of_activation",
  "entry_by",
  "principle_sip_reg_no",
  "principle_sip_internal_ref_no",
  "last_child_sip_reg_no",
  "top_up_frequency",
  "top_up_status",
];
function parseRows(
  raw: string,
  s: SipXsipReportsSource,
  api: SipXsipReportsApi,
  keys: string[],
  idField: string,
  distinctFields: string[],
): SipXsipReportsObservation {
  const result: SipXsipReportsObservation = {
    nativeStatus: null,
    nativeRemarkCategory: "sip_xsip_reports_response_invalid",
    success: false,
    recordCount: 0,
  };
  try {
    if (s.api !== api) return result;
    buildNseSipXsipReportsRequest(s);
    const body: unknown = JSON.parse(raw);
    if (!object(body)) return result;
    if (body.response_status === "S" || body.response_status === "F") {
      result.nativeStatus = body.response_status;
    }
    // B04 samples contain no diagnostic field. No historical B04 response
    // establishes even an empty error_remark alias, or a known F/no-record shape.
    if (Object.hasOwn(body, "error_remark")) {
      return {
        ...result,
        nativeRemarkCategory: "sip_xsip_reports_unknown_diagnostic",
      };
    }
    if (
      Object.keys(body).length !== 3 ||
      !["response_status", "report_data_total", "report_data"].every((k) =>
        Object.hasOwn(body, k)
      ) ||
      body.response_status !== "S" || !Array.isArray(body.report_data)
    ) return result;
    const n = body.report_data_total;
    if (
      (typeof n !== "string" && typeof n !== "number") ||
      (typeof n === "string" && !/^[0-9]+$/.test(n)) ||
      !Number.isInteger(Number(n)) || Number(n) < 0 || Number(n) > 10000 ||
      Number(n) !== body.report_data.length
    ) return result;
    const seen = new Set<string>(), memberCodes = new Set<string>();
    for (const row of body.report_data) {
      if (
        !object(row) || Object.keys(row).length !== keys.length ||
        keys.some((k) => typeof row[k] !== "string") ||
        row.client_code !== s.client_code ||
        !/^[0-9]+$/.test(row.member_code as string) ||
        !/^[0-9]+$/.test(row[idField] as string)
      ) {
        return {
          ...result,
          nativeRemarkCategory: "sip_xsip_reports_row_scope_invalid",
        };
      }
      // Two member identities inside one account response are not a trusted observation.
      memberCodes.add(row.member_code as string);
      if (memberCodes.size > 1) {
        return {
          ...result,
          nativeRemarkCategory: "sip_xsip_reports_row_scope_invalid",
        };
      }
      const key = JSON.stringify(distinctFields.map((k) => row[k]));
      if (seen.has(key)) {
        return {
          ...result,
          nativeRemarkCategory: "sip_xsip_reports_duplicate_rows",
        };
      }
      seen.add(key);
      if (s.selectors.mode === "member") {
        const owned = s.selectors.rows.find((r) =>
          r.member_unique_id === row.member_unique_id
        );
        if (
          !owned || registrationFields(api).some((k) => owned[k] !== row[k])
        ) {
          return {
            ...result,
            nativeRemarkCategory: "sip_xsip_reports_row_scope_invalid",
          };
        }
      }
    }
    if (
      s.selectors.mode === "member" && Number(n) > 0 &&
      Number(n) !== s.selectors.rows.length
    ) {
      return {
        ...result,
        nativeRemarkCategory: "sip_xsip_reports_incomplete_selection",
      };
    }
    return {
      ...result,
      success: true,
      recordCount: Number(n),
      nativeRemarkCategory: Number(n) === 0
        ? "sip_xsip_reports_no_records"
        : "sip_xsip_reports_report_received",
    };
  } catch {
    return result;
  }
}
export function parseSipRegReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "SIP_REG_REPORT",
    SIP_REG_REPORT_FIELDS,
    "sip_reg_number",
    ["sip_reg_number"],
  );
}
export function parseSipCanReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "SIP_CAN_REPORT",
    SIP_CAN_REPORT_FIELDS,
    "sip_registration_no",
    ["sip_registration_no"],
  );
}
export function parseSipInstDueReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "SIP_INST_DUE_REPORT",
    SIP_INST_DUE_REPORT_FIELDS,
    "sip_reg_number",
    ["sip_reg_number", "due_date"],
  );
}
export function parseSipTopupReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "SIP_TOPUP_REPORT",
    SIP_TOPUP_REPORT_FIELDS,
    "reg_no",
    ["reg_no"],
  );
}
export function parseStepupRegReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "STEPUP_REG_REPORT",
    STEPUP_REG_REPORT_FIELDS,
    "sip_xsip_regn_number",
    [
      "sip_xsip_regn_number",
      "sip_xsip_type",
      "stepup_start__effective_date",
      "stepup_enddate",
    ],
  );
}
export function parseXsipRegReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "XSIP_REG_REPORT",
    XSIP_REG_REPORT_FIELDS,
    "xsip_registration_no",
    ["xsip_registration_no"],
  );
}
export function parseXsipCanReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "XSIP_CAN_REPORT",
    XSIP_CAN_REPORT_FIELDS,
    "xsip_registration_no",
    ["xsip_registration_no"],
  );
}
export function parseXsipInstDueReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "XSIP_INST_DUE_REPORT",
    XSIP_INST_DUE_REPORT_FIELDS,
    "sip_reg_number",
    ["sip_reg_number", "due_date"],
  );
}
export function parseXsipTopupReportResponse(
  raw: string,
  s: SipXsipReportsSource,
) {
  return parseRows(
    raw,
    s,
    "XSIP_TOPUP_REPORT",
    XSIP_TOPUP_REPORT_FIELDS,
    "reg_no",
    ["reg_no"],
  );
}
export function parseNseSipXsipReportsResponse(
  raw: string,
  s: SipXsipReportsSource,
): SipXsipReportsObservation {
  switch (s.api) {
    case "SIP_REG_REPORT":
      return parseSipRegReportResponse(raw, s);
    case "SIP_CAN_REPORT":
      return parseSipCanReportResponse(raw, s);
    case "SIP_INST_DUE_REPORT":
      return parseSipInstDueReportResponse(raw, s);
    case "SIP_TOPUP_REPORT":
      return parseSipTopupReportResponse(raw, s);
    case "STEPUP_REG_REPORT":
      return parseStepupRegReportResponse(raw, s);
    case "XSIP_REG_REPORT":
      return parseXsipRegReportResponse(raw, s);
    case "XSIP_CAN_REPORT":
      return parseXsipCanReportResponse(raw, s);
    case "XSIP_INST_DUE_REPORT":
      return parseXsipInstDueReportResponse(raw, s);
    case "XSIP_TOPUP_REPORT":
      return parseXsipTopupReportResponse(raw, s);
    default:
      return {
        nativeStatus: null,
        nativeRemarkCategory: "sip_xsip_reports_response_invalid",
        success: false,
        recordCount: 0,
      };
  }
}
