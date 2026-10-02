/** B05, NNF 1.9.7 pp180–191,276–277. Observations only; no schedule projection. */
export const STP_SWP_REPORTS_ENDPOINTS = {
  "STP_REG_REPORT": "/nsemfdesk/api/v2/reports/STP_REG_REPORT",
  "STP_CAN_REPORT": "/nsemfdesk/api/v2/reports/STP_CAN_REPORT",
  "STP_INST_DUE_REPORT": "/nsemfdesk/api/v2/reports/STP_INST_DUE_REPORT",
  "SWP_REG_REPORT": "/nsemfdesk/api/v2/reports/SWP_REG_REPORT",
  "SWP_CAN_REPORT": "/nsemfdesk/api/v2/reports/SWP_CAN_REPORT",
  "SWP_INST_DUE_REPORT": "/nsemfdesk/api/v2/reports/SWP_INST_DUE_REPORT",
  "SIP_AMC_PAUSE_REPORT": "/nsemfdesk/api/v2/reports/SIP_AMC_PAUSE",
} as const;
export type StpSwpReportsApi = keyof typeof STP_SWP_REPORTS_ENDPOINTS;
export type OwnedRegistration = Record<string, string>;
export type StpSwpReportsSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  api: StpSwpReportsApi;
  client_code: string;
  pan: string;
  today: string;
  selectors: {
    mode: "client" | "member" | "registration";
    rows: OwnedRegistration[];
  };
  request: Record<string, string>;
};
export type StpSwpReportsObservation = {
  nativeStatus: "S" | "F" | null;
  nativeRemarkCategory: string;
  success: boolean;
  recordCount: number;
};
function object(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}
function invalid(): never {
  throw new Error("stp_swp_reports_request_invalid");
}
function date(v: unknown, slash = false): string {
  if (
    typeof v !== "string" ||
    !(slash ? /^\d{2}\/\d{2}\/\d{4}$/ : /^\d{2}-\d{2}-\d{4}$/).test(v)
  ) invalid();
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
  slash = false,
) {
  const hasFrom = Object.hasOwn(request, "from_date"),
    hasTo = Object.hasOwn(request, "to_date");
  if (!hasFrom && !hasTo && !required) return;
  const from = date(request.from_date, slash),
    to = date(request.to_date, slash);
  const gap = (Date.parse(to) - Date.parse(from)) / 86400000;
  if (gap <= 0 || gap > days || (nonPast && from < today)) invalid();
}
const REGISTRATION_FIELDS: Partial<Record<StpSwpReportsApi, string[]>> = {
  "STP_REG_REPORT": [
    "stp_registration_no",
    "stp_registration_date",
    "member_unique_id",
    "member_code",
    "from_nse_scheme_code",
    "to_nse_scheme_code",
    "frequency_type",
    "stp_start_date",
    "stp_end_date",
    "transfer_amount",
    "transfer_units",
  ],
  "SWP_REG_REPORT": [
    "swp_registration_no",
    "swp_registration_date",
    "member_unique_id",
    "member_code",
    "nse_scheme_code",
    "frequency_type",
    "swp_start_date",
    "swp_end_date",
    "withdrawl_amount",
    "withdrawal_units",
  ],
  "STP_INST_DUE_REPORT": [
    "stp_registration_no",
    "frequency_type",
    "transfer_amount",
    "transfer_units",
    "folio_no",
    "internal_ref_no",
  ],
};
function registrationFields(api: StpSwpReportsApi): string[] {
  return REGISTRATION_FIELDS[api] ?? invalid();
}
function requestFor(
  s: StpSwpReportsSource,
  api: StpSwpReportsApi,
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
    if (api === "STP_INST_DUE_REPORT") invalid();
    if (
      api === "SIP_AMC_PAUSE_REPORT" &&
      (s.client_code.length > 15 || r.modification_type !== "PAUSE")
    ) invalid();
    field = "client_code";
    expected = s.client_code;
  } else if (
    api === "STP_INST_DUE_REPORT" && s.selectors.mode === "registration" &&
    s.selectors.rows.length >= 1 && s.selectors.rows.length <= 50
  ) {
    const keys = registrationFields(api), seen = new Set<string>();
    for (const row of s.selectors.rows) {
      if (
        !object(row) || Object.keys(row).length !== keys.length ||
        keys.some((k) => typeof row[k] !== "string") ||
        !/^[0-9]+$/.test(row.stp_registration_no) ||
        seen.has(row.stp_registration_no) ||
        ["frequency_type", "transfer_amount", "transfer_units"].some((k) =>
          !row[k].trim()
        )
      ) invalid();
      seen.add(row.stp_registration_no);
    }
    field = "stp_reg_id";
    expected = s.selectors.rows.map((r) => r.stp_registration_no).join(",");
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
  // Emit only the effective owned selector. STP due IDs come from validated
  // registration evidence; all raw caller identifiers remain disabled.
  if (
    r[field] !== expected ||
    Object.keys(r).some((k) =>
      ![
        field,
        "from_date",
        "to_date",
        ...(api === "SIP_AMC_PAUSE_REPORT" ? ["modification_type"] : []),
      ].includes(k)
    ) ||
    Object.values(r).some((v) => typeof v !== "string")
  ) invalid();
  // Tables require dates when registration ID and UCC are absent, including
  // the member-only slice. An effective member/UCC selector ignores these dates.
  dates(
    r,
    days,
    nonPast,
    s.today,
    field === "member_unique_ids",
    api === "SIP_AMC_PAUSE_REPORT",
  );
  return { ...r };
}
export function buildStpRegReportRequest(s: StpSwpReportsSource) {
  return requestFor(s, "STP_REG_REPORT", 31, false, true);
}
export function buildStpCanReportRequest(s: StpSwpReportsSource) {
  return requestFor(s, "STP_CAN_REPORT", 31, false, false);
}
export function buildStpInstDueReportRequest(s: StpSwpReportsSource) {
  return requestFor(s, "STP_INST_DUE_REPORT", 7, true, false);
}
export function buildSwpRegReportRequest(s: StpSwpReportsSource) {
  return requestFor(s, "SWP_REG_REPORT", 31, false, true);
}
export function buildSwpCanReportRequest(s: StpSwpReportsSource) {
  return requestFor(s, "SWP_CAN_REPORT", 31, false, false);
}
export function buildSwpInstDueReportRequest(s: StpSwpReportsSource) {
  return requestFor(s, "SWP_INST_DUE_REPORT", 7, true, false);
}
export function buildSipAmcPauseReportRequest(s: StpSwpReportsSource) {
  return requestFor(s, "SIP_AMC_PAUSE_REPORT", 7, false, false);
}
export function buildNseStpSwpReportsRequest(
  s: StpSwpReportsSource,
): Record<string, string> {
  switch (s.api) {
    case "STP_REG_REPORT":
      return buildStpRegReportRequest(s);
    case "STP_CAN_REPORT":
      return buildStpCanReportRequest(s);
    case "STP_INST_DUE_REPORT":
      return buildStpInstDueReportRequest(s);
    case "SWP_REG_REPORT":
      return buildSwpRegReportRequest(s);
    case "SWP_CAN_REPORT":
      return buildSwpCanReportRequest(s);
    case "SWP_INST_DUE_REPORT":
      return buildSwpInstDueReportRequest(s);
    case "SIP_AMC_PAUSE_REPORT":
      return buildSipAmcPauseReportRequest(s);
    default:
      return invalid();
  }
}
const STP_REG_REPORT_FIELDS = [
  "status",
  "member_code",
  "client_code",
  "stp_registration_no",
  "folio_no",
  "internal_ref_no",
  "from_amc_name",
  "to_amc_name",
  "from_scheme_name",
  "to_scheme_name",
  "stp_registration_date",
  "stp_start_date",
  "stp_end_date",
  "frequency_type",
  "trxn_mode",
  "transfer_amount",
  "transfer_units",
  "no_of_transfers",
  "first_order_todays_flag",
  "euin_declaration",
  "euin_number",
  "sub_br_code",
  "remarks",
  "sub_br_arn_code",
  "buy_sell_type",
  "from_nse_scheme_code",
  "to_nse_scheme_code",
  "email_id",
  "mobile_no",
  "member_unique_id",
];
const STP_CAN_REPORT_FIELDS = [
  "member_code",
  "client_code",
  "stp_registration_no",
  "folio_no",
  "from_amc_name",
  "to_amc_name",
  "from_scheme_name",
  "to_scheme_name",
  "stp_registration_date",
  "stp_start_date",
  "stp_end_date",
  "frequency",
  "trxn_mode",
  "transfer_amount",
  "transfer_units",
  "no_of_transfers",
  "euin_declaration",
  "euin_number",
  "sub_br_code",
  "remarks",
  "stp_cancellation_date",
  "stp_cancelled_by",
];
const STP_INST_DUE_REPORT_FIELDS = [
  "stp_registration_no",
  "client_name",
  "folio_no",
  "internal_ref_no",
  "stp_registration_date",
  "amc_name",
  "from_scheme_name",
  "to_scheme_name",
  "frequency_type",
  "dp_trans",
  "transfer_amount",
  "transfer_units",
  "due_date",
  "prev_transfer_date",
  "no_of_transfer_completed",
  "first_order_todays_flag",
  "euin_declaration",
  "euin_number",
  "sub_br_code",
  "remarks",
  "entry_by",
];
const SWP_REG_REPORT_FIELDS = [
  "status",
  "member_code",
  "client_code",
  "swp_registration_no",
  "folio_no",
  "amc",
  "scheme_name",
  "frequency_type",
  "swp_registration_date",
  "swp_start_date",
  "swp_end_date",
  "withdrawl_amount",
  "withdrawal_units",
  "no_of_withdrawls",
  "euin_declaration",
  "euin_number",
  "subbrcode",
  "first_order_flag",
  "int_ref_no",
  "remark",
  "sub_broker_arn_code",
  "nse_scheme_code",
  "transaction_mode",
  "mobile_no",
  "email_id",
  "bank_account_no",
  "member_unique_id",
];
const SWP_CAN_REPORT_FIELDS = [
  "member_code",
  "client_code",
  "swp_registration_no",
  "folio_no",
  "amc",
  "scheme_name",
  "swp_registration_date",
  "swp_cancellation_date",
  "swp_start_date",
  "swp_end_date",
  "frequency_type",
  "withdrawl_amount",
  "withdrawl_units",
  "no_of_withdrawls",
  "euin_declaration",
  "euin_number",
  "subbrcode",
  "remark",
  "swp_cancelled_by",
  "nse_scheme_code",
];
const SWP_INST_DUE_REPORT_FIELDS = [
  "member_code",
  "client_code",
  "client_name",
  "swp_regn_no",
  "folio_no",
  "internal_ref_no",
  "regn_date",
  "amc_name",
  "scheme_code",
  "scheme_name",
  "frequency_type",
  "installment_amt",
  "installment_units",
  "due_date",
  "prev_paid_date",
  "no_of_installments_paid",
  "total_installment_amt_sold",
  "unit_sold",
  "entry_by",
  "dp_trans",
  "euin_declaration",
  "euin_number",
  "subbrcode",
  "first_order_flag",
  "remark",
];
const SIP_AMC_PAUSE_REPORT_FIELDS = [
  "client_code",
  "sip_registration_no",
  "scheme_code",
  "scheme_name",
  "amount",
  "sip_start_date",
  "sip_end_date",
  "no_of_instalments_paused",
  "date_of_activation",
  "pause_from_date",
  "pause_to_date",
  "request_id",
  "entry_by",
  "modified_date",
  "modified_instalments",
];
function parseRows(
  raw: string,
  s: StpSwpReportsSource,
  api: StpSwpReportsApi,
  keys: string[],
  idField: string,
  distinctFields: string[],
): StpSwpReportsObservation {
  const result: StpSwpReportsObservation = {
    nativeStatus: null,
    nativeRemarkCategory: "stp_swp_reports_response_invalid",
    success: false,
    recordCount: 0,
  };
  try {
    if (s.api !== api) return result;
    buildNseStpSwpReportsRequest(s);
    const body: unknown = JSON.parse(raw);
    if (!object(body)) return result;
    if (body.response_status === "S" || body.response_status === "F") {
      result.nativeStatus = body.response_status;
    }
    // AMC Pause independently requires its documented empty error_remark.
    // No diagnostic compatibility is characterized for any B05 endpoint.
    const amc = api === "SIP_AMC_PAUSE_REPORT";
    const countField = amc ? "response_data_total" : "report_data_total";
    if (
      (!amc && Object.hasOwn(body, "error_remark")) ||
      (amc && body.error_remark !== "")
    ) {
      return {
        ...result,
        nativeRemarkCategory: "stp_swp_reports_unknown_diagnostic",
      };
    }
    if (
      Object.keys(body).length !== (amc ? 4 : 3) ||
      !["response_status", countField, "report_data"].every((k) =>
        Object.hasOwn(body, k)
      ) ||
      body.response_status !== "S" || !Array.isArray(body.report_data)
    ) return result;
    const n = body[countField];
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
        (api !== "STP_INST_DUE_REPORT" && row.client_code !== s.client_code) ||
        (keys.includes("member_code") &&
          !/^[0-9]+$/.test(row.member_code as string)) ||
        (amc &&
          (!/^[0-9]{1,11}$/.test(row.request_id as string) ||
            (row[idField] as string).length > 15)) ||
        !/^[0-9]+$/.test(row[idField] as string)
      ) {
        return {
          ...result,
          nativeRemarkCategory: "stp_swp_reports_row_scope_invalid",
        };
      }
      // Two member identities inside one account response are not a trusted observation.
      memberCodes.add(row.member_code as string);
      if (memberCodes.size > 1) {
        return {
          ...result,
          nativeRemarkCategory: "stp_swp_reports_row_scope_invalid",
        };
      }
      const key = JSON.stringify(distinctFields.map((k) => row[k]));
      if (seen.has(key)) {
        return {
          ...result,
          nativeRemarkCategory: "stp_swp_reports_duplicate_rows",
        };
      }
      seen.add(key);
      if (api === "STP_INST_DUE_REPORT") {
        const owned = s.selectors.rows.find((r) =>
          r.stp_registration_no === row.stp_registration_no
        );
        if (
          !owned || registrationFields(api).some((k) => owned[k] !== row[k])
        ) {
          return {
            ...result,
            nativeRemarkCategory: "stp_swp_reports_row_scope_invalid",
          };
        }
      }
      if (s.selectors.mode === "member") {
        const owned = s.selectors.rows.find((r) =>
          r.member_unique_id === row.member_unique_id
        );
        if (
          !owned || registrationFields(api).some((k) => owned[k] !== row[k])
        ) {
          return {
            ...result,
            nativeRemarkCategory: "stp_swp_reports_row_scope_invalid",
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
        nativeRemarkCategory: "stp_swp_reports_incomplete_selection",
      };
    }
    return {
      ...result,
      success: true,
      recordCount: Number(n),
      nativeRemarkCategory: Number(n) === 0
        ? "stp_swp_reports_no_records"
        : "stp_swp_reports_report_received",
    };
  } catch {
    return result;
  }
}
export function parseStpRegReportResponse(raw: string, s: StpSwpReportsSource) {
  return parseRows(
    raw,
    s,
    "STP_REG_REPORT",
    STP_REG_REPORT_FIELDS,
    "stp_registration_no",
    ["stp_registration_no"],
  );
}
export function parseStpCanReportResponse(raw: string, s: StpSwpReportsSource) {
  return parseRows(
    raw,
    s,
    "STP_CAN_REPORT",
    STP_CAN_REPORT_FIELDS,
    "stp_registration_no",
    ["stp_registration_no"],
  );
}
export function parseStpInstDueReportResponse(
  raw: string,
  s: StpSwpReportsSource,
) {
  return parseRows(
    raw,
    s,
    "STP_INST_DUE_REPORT",
    STP_INST_DUE_REPORT_FIELDS,
    "stp_registration_no",
    ["stp_registration_no", "due_date"],
  );
}
export function parseSwpRegReportResponse(raw: string, s: StpSwpReportsSource) {
  return parseRows(
    raw,
    s,
    "SWP_REG_REPORT",
    SWP_REG_REPORT_FIELDS,
    "swp_registration_no",
    ["swp_registration_no"],
  );
}
export function parseSwpCanReportResponse(raw: string, s: StpSwpReportsSource) {
  return parseRows(
    raw,
    s,
    "SWP_CAN_REPORT",
    SWP_CAN_REPORT_FIELDS,
    "swp_registration_no",
    ["swp_registration_no"],
  );
}
export function parseSwpInstDueReportResponse(
  raw: string,
  s: StpSwpReportsSource,
) {
  return parseRows(
    raw,
    s,
    "SWP_INST_DUE_REPORT",
    SWP_INST_DUE_REPORT_FIELDS,
    "swp_regn_no",
    ["swp_regn_no", "due_date"],
  );
}
export function parseSipAmcPauseReportResponse(
  raw: string,
  s: StpSwpReportsSource,
) {
  return parseRows(
    raw,
    s,
    "SIP_AMC_PAUSE_REPORT",
    SIP_AMC_PAUSE_REPORT_FIELDS,
    "sip_registration_no",
    ["request_id"],
  );
}
export function parseNseStpSwpReportsResponse(
  raw: string,
  s: StpSwpReportsSource,
): StpSwpReportsObservation {
  switch (s.api) {
    case "STP_REG_REPORT":
      return parseStpRegReportResponse(raw, s);
    case "STP_CAN_REPORT":
      return parseStpCanReportResponse(raw, s);
    case "STP_INST_DUE_REPORT":
      return parseStpInstDueReportResponse(raw, s);
    case "SWP_REG_REPORT":
      return parseSwpRegReportResponse(raw, s);
    case "SWP_CAN_REPORT":
      return parseSwpCanReportResponse(raw, s);
    case "SWP_INST_DUE_REPORT":
      return parseSwpInstDueReportResponse(raw, s);
    case "SIP_AMC_PAUSE_REPORT":
      return parseSipAmcPauseReportResponse(raw, s);
    default:
      return {
        nativeStatus: null,
        nativeRemarkCategory: "stp_swp_reports_response_invalid",
        success: false,
        recordCount: 0,
      };
  }
}
