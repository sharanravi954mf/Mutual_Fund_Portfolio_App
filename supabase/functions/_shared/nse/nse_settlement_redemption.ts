/** B03: handbook v1.9.7 pp121–135. Private evidence observations only.
 * Source is a service-owned immutable projection, never caller provider IDs.
 */
export const SETTLEMENT_REDEMPTION_ENDPOINTS = {
  REDEMPTION_PAYOUT: "/nsemfdesk/api/v2/reports/REDEMPTION_PAYOUT",
  REDEMPTION_PAYOUT_NON_DEMAT:
    "/nsemfdesk/api/v2/reports/REDEMPTION_PAYOUT_NON_DEMAT",
  REDEMPTION_STATEMENT: "/nsemfdesk/api/v2/reports/REDEMPTION_STATEMENT",
  ALLOTMENT_STATEMENT: "/nsemfdesk/api/v2/reports/ALLOTMENT_STATEMENT",
} as const;
export type SettlementRedemptionApi =
  keyof typeof SETTLEMENT_REDEMPTION_ENDPOINTS;
type ReportDates = { from_date: string; to_date: string };
type PayoutSelector =
  | { order_id: string; member_unique_ids?: never }
  | { order_id?: never; member_unique_ids: string };
type StatementSelector =
  | { order_ids: string; member_unique_ids?: never }
  | { order_ids?: never; member_unique_ids: string };
type PayoutReportType = "Order Date" | "Payout Date" | "Fund Transfer Date";
export type RedemptionPayoutRequest = ReportDates & PayoutSelector & {
  report_type: PayoutReportType;
};
export type RedemptionPayoutNonDematRequest = ReportDates & PayoutSelector & {
  report_type: PayoutReportType;
};
export type RedemptionStatementRequest = ReportDates & StatementSelector;
export type AllotmentStatementRequest = ReportDates & StatementSelector & {
  date_type: "ORD_DATE" | "ALT_DATE";
};
export type SettlementRedemptionRequest =
  | RedemptionPayoutRequest
  | RedemptionPayoutNonDematRequest
  | RedemptionStatementRequest
  | AllotmentStatementRequest;
export type OwnedSettlementOrder = {
  order_id: string;
  member_unique_id: string;
  member_id: string;
  scheme_code: string;
  isin: string;
  transaction_type: "P" | "R";
  order_date: string;
  settlement_id: string;
  settlement_type: string;
  folio_no: string;
};
export type SettlementRedemptionSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  api: SettlementRedemptionApi;
  client_code: string;
  pan: string;
  selectors: { mode: "order" | "member"; rows: OwnedSettlementOrder[] };
  request: Record<string, string>;
};
export type SettlementRedemptionObservation = {
  nativeStatus: "S" | "F" | null;
  nativeRemarkCategory: string;
  success: boolean;
  recordCount: number;
};
function invalid(): never {
  throw new Error("settlement_redemption_request_invalid");
}
function object(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}
function fields(
  v: Record<string, unknown>,
  required: string[],
  optional: string[] = [],
) {
  if (
    required.some((k) =>
      typeof v[k] !== "string" || !(v[k] as string).trim()
    ) ||
    Object.keys(v).some((k) =>
      !required.includes(k) && !optional.includes(k)
    ) ||
    Object.values(v).some((x) => typeof x !== "string" || !x.trim())
  ) invalid();
}
function date(
  v: string,
  format: "DMY" | "ISO" | "SLASH" | "MONTH" = "DMY",
): string {
  let iso: string;
  if (format === "ISO" && /^\d{4}-\d{2}-\d{2}$/.test(v)) iso = v;
  else if (format === "DMY" && /^\d{2}-\d{2}-\d{4}$/.test(v)) {
    iso = v.slice(6) + "-" + v.slice(3, 5) + "-" + v.slice(0, 2);
  } else if (format === "SLASH" && /^\d{2}\/\d{2}\/\d{4}$/.test(v)) {
    iso = v.slice(6) + "-" + v.slice(3, 5) + "-" + v.slice(0, 2);
  } else if (format === "MONTH" && /^\d{2} [A-Z]{3} \d{4}$/.test(v)) {
    const month = [
      "JAN",
      "FEB",
      "MAR",
      "APR",
      "MAY",
      "JUN",
      "JUL",
      "AUG",
      "SEP",
      "OCT",
      "NOV",
      "DEC",
    ].indexOf(v.slice(3, 6)) + 1;
    iso = v.slice(7) + "-" + String(month).padStart(2, "0") + "-" +
      v.slice(0, 2);
  } else return invalid();
  const n = Date.parse(iso + "T00:00:00Z");
  if (
    !Number.isFinite(n) || iso.startsWith("0000") ||
    new Date(n).toISOString().slice(0, 10) !== iso
  ) invalid();
  return iso;
}
function commonRequest(s: SettlementRedemptionSource) {
  if (
    !object(s) || !Object.hasOwn(SETTLEMENT_REDEMPTION_ENDPOINTS, s.api) ||
    typeof s.client_code !== "string" ||
    !/^[A-Za-z0-9_-]{1,20}$/.test(s.client_code) ||
    typeof s.pan !== "string" || !/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(s.pan) ||
    !object(s.request) || !object(s.selectors) ||
    Object.keys(s.selectors).some((k) => !["mode", "rows"].includes(k)) ||
    !["order", "member"].includes(s.selectors.mode) ||
    !Array.isArray(s.selectors.rows) ||
    s.selectors.rows.length < 1 || s.selectors.rows.length > 50
  ) invalid();
  const orders = new Set<string>(), members = new Set<string>();
  for (const row of s.selectors.rows) {
    if (
      !object(row) ||
      ![
        "order_id",
        "member_unique_id",
        "member_id",
        "scheme_code",
        "isin",
        "transaction_type",
        "order_date",
        "settlement_id",
        "settlement_type",
        "folio_no",
      ].every((k) =>
        typeof row[k as keyof OwnedSettlementOrder] === "string"
      ) ||
      !/^[0-9]+$/.test(row.order_id) ||
      !/^[A-Za-z0-9_-]{1,25}$/.test(row.member_unique_id) ||
      !/^[0-9]+$/.test(row.member_id) || !/^[0-9]+$/.test(row.settlement_id) ||
      !row.scheme_code.trim() || !row.isin.trim() ||
      !row.settlement_type.trim() ||
      row.transaction_type !== (s.api === "ALLOTMENT_STATEMENT" ? "P" : "R") ||
      orders.has(row.order_id) || members.has(row.member_unique_id)
    ) invalid();
    date(row.order_date, "SLASH");
    if (
      s.api === "REDEMPTION_PAYOUT_NON_DEMAT" &&
      (!row.folio_no.trim() || row.folio_no === "-")
    ) invalid();
    orders.add(row.order_id);
    members.add(row.member_unique_id);
  }
  const days = (Date.parse(date(s.request.to_date)) -
    Date.parse(date(s.request.from_date))) / 86400000;
  // Each of pp121,124,126,129 independently states a 30-day gap.
  if (days < 0 || days > 30) invalid();
}
function selector(
  s: SettlementRedemptionSource,
  orderField: "order_id" | "order_ids",
) {
  const key = s.selectors.mode === "order" ? orderField : "member_unique_ids";
  if (
    s.request[key] !==
      s.selectors.rows.map((r) =>
        s.selectors.mode === "order" ? r.order_id : r.member_unique_id
      ).join(",")
  ) invalid();
  return key;
}
export function buildRedemptionPayoutRequest(
  s: SettlementRedemptionSource,
): RedemptionPayoutRequest {
  commonRequest(s);
  if (s.api !== "REDEMPTION_PAYOUT") invalid();
  fields(s.request, [
    "from_date",
    "to_date",
    "report_type",
    selector(s, "order_id"),
  ]);
  if (
    !["Order Date", "Payout Date", "Fund Transfer Date"].includes(
      s.request.report_type,
    )
  ) invalid();
  const selected: PayoutSelector = s.selectors.mode === "order"
    ? { order_id: s.request.order_id }
    : { member_unique_ids: s.request.member_unique_ids };
  return {
    from_date: s.request.from_date,
    to_date: s.request.to_date,
    report_type: s.request.report_type as PayoutReportType,
    ...selected,
  };
}
export function buildRedemptionPayoutNonDematRequest(
  s: SettlementRedemptionSource,
): RedemptionPayoutNonDematRequest {
  commonRequest(s);
  if (s.api !== "REDEMPTION_PAYOUT_NON_DEMAT") invalid();
  fields(s.request, [
    "from_date",
    "to_date",
    "report_type",
    selector(s, "order_id"),
  ]);
  if (
    !["Order Date", "Payout Date", "Fund Transfer Date"].includes(
      s.request.report_type,
    )
  ) invalid();
  const selected: PayoutSelector = s.selectors.mode === "order"
    ? { order_id: s.request.order_id }
    : { member_unique_ids: s.request.member_unique_ids };
  return {
    from_date: s.request.from_date,
    to_date: s.request.to_date,
    report_type: s.request.report_type as PayoutReportType,
    ...selected,
  };
}
export function buildRedemptionStatementRequest(
  s: SettlementRedemptionSource,
): RedemptionStatementRequest {
  commonRequest(s);
  if (s.api !== "REDEMPTION_STATEMENT") invalid();
  fields(s.request, ["from_date", "to_date", selector(s, "order_ids")]);
  const selected: StatementSelector = s.selectors.mode === "order"
    ? { order_ids: s.request.order_ids }
    : { member_unique_ids: s.request.member_unique_ids };
  return {
    from_date: s.request.from_date,
    to_date: s.request.to_date,
    ...selected,
  };
}
export function buildAllotmentStatementRequest(
  s: SettlementRedemptionSource,
): AllotmentStatementRequest {
  commonRequest(s);
  if (s.api !== "ALLOTMENT_STATEMENT") invalid();
  fields(s.request, [
    "from_date",
    "to_date",
    "date_type",
    selector(s, "order_ids"),
  ]);
  if (!["ORD_DATE", "ALT_DATE"].includes(s.request.date_type)) invalid();
  const selected: StatementSelector = s.selectors.mode === "order"
    ? { order_ids: s.request.order_ids }
    : { member_unique_ids: s.request.member_unique_ids };
  return {
    from_date: s.request.from_date,
    to_date: s.request.to_date,
    date_type: s.request.date_type as "ORD_DATE" | "ALT_DATE",
    ...selected,
  };
}
export function buildNseSettlementRedemptionRequest(
  s: SettlementRedemptionSource,
): SettlementRedemptionRequest {
  switch (s.api) {
    case "REDEMPTION_PAYOUT":
      return buildRedemptionPayoutRequest(s);
    case "REDEMPTION_PAYOUT_NON_DEMAT":
      return buildRedemptionPayoutNonDematRequest(s);
    case "REDEMPTION_STATEMENT":
      return buildRedemptionStatementRequest(s);
    case "ALLOTMENT_STATEMENT":
      return buildAllotmentStatementRequest(s);
    default:
      return invalid();
  }
}
function stringRow(
  row: unknown,
  required: string[],
): row is Record<string, string> {
  return object(row) && required.every((k) => typeof row[k] === "string") &&
    Object.values(row).every((v) => typeof v === "string");
}
const payoutFields = [
  "order_id",
  "member_code",
  "client_code",
  "member_unique_id",
  "scheme_code",
  "isin",
  "transaction_type",
  "order_date",
  "settlement_id",
  "settlement_type",
  "rta_transaction_no",
  "funds_payout_status",
  "allotted_amount",
  "first_applicant_pan",
];
// These are the endpoint's own sample columns, not aliases shared with ORDER_STATUS.
function payout(
  row: unknown,
  s: SettlementRedemptionSource,
): OwnedSettlementOrder | undefined {
  if (
    !stringRow(row, [
      ...payoutFields,
      "rta_scheme_code",
      "funds_payout_date",
      "funds_transfer_date",
    ])
  ) return;
  const owned = match(
    row,
    s,
    "order_id",
    "member_code",
    "client_code",
    "scheme_code",
    "settlement_id",
    "settlement_type",
  );
  if (
    !owned || row.transaction_type !== "R" ||
    row.first_applicant_pan !== s.pan ||
    date(row.order_date, "MONTH") !== date(owned.order_date, "SLASH") ||
    !row.funds_payout_status.trim()
  ) return;
  if (row.funds_payout_date.trim()) date(row.funds_payout_date, "MONTH");
  if (row.funds_transfer_date.trim()) date(row.funds_transfer_date, "MONTH");
  return owned;
}
function nonDemat(
  row: unknown,
  s: SettlementRedemptionSource,
): OwnedSettlementOrder | undefined {
  if (
    !stringRow(row, [
      ...payoutFields,
      "product_code",
      "folio_number",
      "payout_desc",
      "mailed_date",
      "funds_payout_date",
      "despatch_status",
      "instrm_no",
      "instrm_bank",
      "payee_acno",
    ])
  ) return;
  const owned = match(
    row,
    s,
    "order_id",
    "member_code",
    "client_code",
    "scheme_code",
    "settlement_id",
    "settlement_type",
  );
  if (
    !owned || row.transaction_type !== "R" ||
    row.first_applicant_pan !== s.pan || row.folio_number !== owned.folio_no ||
    date(row.order_date, "MONTH") !== date(owned.order_date, "SLASH") ||
    !row.funds_payout_status.trim()
  ) return;
  // This endpoint uses US date/time strings, unlike demat payout. No timezone/finality inference.
  for (const key of ["mailed_date", "funds_payout_date"]) {
    if (row[key].trim()) {
      const m =
        /^(\d{2})\/(\d{2})\/(\d{4}) (0?[1-9]|1[0-2]):([0-5]\d):([0-5]\d) (AM|PM)$/
          .exec(row[key]);
      if (!m) return;
      date(`${m[2]}-${m[1]}-${m[3]}`);
    }
  }
  return owned;
}
const statementFields = [
  "orderno",
  "member_unique_id",
  "clientcode",
  "schemecode",
  "isin",
  "orderdate",
  "reportdate",
  "settlementid",
  "settlementype",
  "rtatransactionno",
  "ordertype",
  "ordersubtype",
  "validflag",
  "allottednav",
  "allottedqty",
];
function redemptionStatement(
  row: unknown,
  s: SettlementRedemptionSource,
): OwnedSettlementOrder | undefined {
  if (
    !stringRow(row, [
      ...statementFields,
      "membercode",
      "allottedamt",
      "dptrans",
    ])
  ) return;
  const owned = match(
    row,
    s,
    "orderno",
    "membercode",
    "clientcode",
    "schemecode",
    "settlementid",
    "settlementype",
  );
  if (
    !owned || row.ordertype !== "NRM" || row.ordersubtype !== "NRM" ||
    !row.validflag.trim() ||
    date(row.orderdate) !== date(owned.order_date, "SLASH")
  ) return;
  date(row.reportdate);
  return owned;
}
function allotmentStatement(
  row: unknown,
  s: SettlementRedemptionSource,
): OwnedSettlementOrder | undefined {
  if (
    !stringRow(row, [
      ...statementFields,
      "memberid",
      "allotmentamt",
      "dptrans",
      "pgbankrefno",
    ])
  ) return;
  const owned = match(
    row,
    s,
    "orderno",
    "memberid",
    "clientcode",
    "schemecode",
    "settlementid",
    "settlementype",
  );
  if (
    !owned || row.ordertype !== "NRM" || row.ordersubtype !== "NRM" ||
    !row.validflag.trim() ||
    date(row.orderdate, "ISO") !== date(owned.order_date, "SLASH")
  ) return;
  date(row.reportdate, "ISO");
  return owned;
}
function match(
  row: Record<string, string>,
  s: SettlementRedemptionSource,
  order: string,
  member: string,
  client: string,
  scheme: string,
  settlement: string,
  settlementType: string,
) {
  const owned = s.selectors.rows.find((r) => r.order_id === row[order]);
  return owned && row[client] === s.client_code &&
      row[member] === owned.member_id &&
      row.member_unique_id === owned.member_unique_id &&
      row[scheme] === owned.scheme_code && row.isin === owned.isin &&
      row[settlement] === owned.settlement_id &&
      row[settlementType] === owned.settlement_type
    ? owned
    : undefined;
}
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
      for (const [k, v] of Object.entries(item)) {
        pending.push(k, v);
      }
    }
  }
  return true;
}
export function parseNseSettlementRedemptionResponse(
  raw: string,
  s: SettlementRedemptionSource,
): SettlementRedemptionObservation {
  let nativeStatus: "S" | "F" | null = null;
  const fail = (
    category = "settlement_redemption_response_invalid",
  ): SettlementRedemptionObservation => ({
    nativeStatus,
    nativeRemarkCategory: category,
    success: false,
    recordCount: 0,
  });
  try {
    buildNseSettlementRedemptionRequest(s);
    const e: unknown = JSON.parse(raw);
    if (
      !object(e) || !databaseJsonCompatible(e) ||
      (e.response_status !== "S" && e.response_status !== "F")
    ) return fail();
    nativeStatus = e.response_status as "S" | "F";
    const total = e.report_data_total;
    if (
      (typeof total !== "number" &&
        !(typeof total === "string" && /^\d+$/.test(total))) ||
      !Number.isSafeInteger(Number(total)) || Number(total) < 0 ||
      Number(total) > 10000 || typeof e.error_remark !== "string"
    ) return fail();
    // Independent handbook envelopes pp122,125,127,130–131 all document F + blank data.
    // No endpoint has a retained literal UAT diagnostic permitting an exception.
    switch (s.api) {
      case "REDEMPTION_PAYOUT":
      case "REDEMPTION_PAYOUT_NON_DEMAT":
      case "REDEMPTION_STATEMENT":
      case "ALLOTMENT_STATEMENT":
        if (nativeStatus === "F") {
          return Number(total) === 0 && e.report_data === "" &&
              e.error_remark.trim()
            ? fail("settlement_redemption_business_failed")
            : fail();
        }
        if (e.error_remark !== "") {
          return fail("settlement_redemption_unknown_success_diagnostic");
        }
    }
    if (
      !Array.isArray(e.report_data) || e.report_data.length !== Number(total)
    ) return fail();
    const orders = new Set<string>(), registrar = new Set<string>();
    for (const row of e.report_data) {
      let owned: OwnedSettlementOrder | undefined;
      try {
        switch (s.api) {
          case "REDEMPTION_PAYOUT":
            owned = payout(row, s);
            break;
          case "REDEMPTION_PAYOUT_NON_DEMAT":
            owned = nonDemat(row, s);
            break;
          case "REDEMPTION_STATEMENT":
            owned = redemptionStatement(row, s);
            break;
          case "ALLOTMENT_STATEMENT":
            owned = allotmentStatement(row, s);
            break;
        }
      } catch {
        return fail("settlement_redemption_row_scope_invalid");
      }
      if (!owned) return fail("settlement_redemption_row_scope_invalid");
      const rta = row[
        s.api.startsWith("REDEMPTION_PAYOUT")
          ? "rta_transaction_no"
          : "rtatransactionno"
      ];
      if (typeof rta !== "string" || !/^[A-Za-z0-9_-]+$/.test(rta)) {
        return fail("settlement_redemption_row_scope_invalid");
      }
      if (orders.has(owned.order_id) || registrar.has(rta)) {
        return fail("settlement_redemption_duplicate_rows");
      }
      orders.add(owned.order_id);
      registrar.add(rta);
    }
    if (orders.size > 0 && orders.size !== s.selectors.rows.length) {
      return fail("settlement_redemption_incomplete_selection");
    }
    return {
      nativeStatus: "S",
      nativeRemarkCategory: Number(total) === 0
        ? "settlement_redemption_no_records"
        : "settlement_redemption_report_received",
      success: true,
      recordCount: Number(total),
    };
  } catch {
    return fail();
  }
}
