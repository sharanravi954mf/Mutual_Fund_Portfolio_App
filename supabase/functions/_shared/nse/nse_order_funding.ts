/** B02: handbook v1.9.7 pp115–121,150–157; recovered C006, plan V2-06.
 * Source objects are private database projections, never caller query options.
 */
export const ORDER_FUNDING_ENDPOINTS = {
  ORDER_LIFECYCLE: "/nsemfdesk/api/v2/reports/order_lifecycle",
  TRANSACTION_DETAIL: "/nsemfdesk/api/v2/reports/TRANSACTION_DETAIL_REPORT",
  FUND_ORDER: "/nsemfdesk/api/v2/reports/MEMBER_FUND_ALLOCATION/ORDER_WISE",
  FUND_AGE: "/nsemfdesk/api/v2/reports/MEMBER_FUND_ALLOCATION/AGE_WISE",
} as const;
export type OrderFundingApi = keyof typeof ORDER_FUNDING_ENDPOINTS;
export type LifecycleProduct = "PUR" | "RED" | "SWITCH" | "SIP" | "STP" | "SWP";
export type OrderFundingSelectors =
  | { Product_type: LifecycleProduct; product_id: string }
  | { order_id: string }
  | Record<string, never>;
type Dates = { from_date: string; to_date: string; client_code: string };
export type OrderFundingRequest =
  | (Dates & { Product_type?: LifecycleProduct; product_id?: string })
  | (Dates & {
    date_type: "REQUEST_DATE" | "ORDER_DATE" | "LAST_ACTIVITY_DATE";
    order_id?: string;
  })
  | { date: string; client_code: string; settlement_type: "all" };
export type OrderFundingSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  api: OrderFundingApi;
  client_code: string;
  pan: string;
  selectors: OrderFundingSelectors;
  request: OrderFundingRequest;
};
export type OrderFundingObservation = {
  nativeStatus: "S" | "F" | null;
  nativeRemarkCategory: string;
  success: boolean;
  recordCount: number;
};
function invalid(): never {
  throw new Error("order_funding_request_invalid");
}
function object(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}
function date(v: unknown): number {
  if (typeof v !== "string" || !/^\d{2}-\d{2}-\d{4}$/.test(v)) return invalid();
  const iso = v.slice(6) + "-" + v.slice(3, 5) + "-" + v.slice(0, 2);
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
    Object.keys(r).some((k) =>
      !required.includes(k) && !optional.includes(k)
    ) ||
    Object.values(r).some((v) => typeof v !== "string")
  ) invalid();
}
function ids(v: unknown): string[] {
  if (typeof v !== "string") return invalid();
  const list = v.split(",");
  if (
    list.length > 50 || list.some((x) => !/^[A-Za-z0-9_-]+$/.test(x)) ||
    new Set(list).size !== list.length
  ) return invalid();
  return list;
}
export function buildNseOrderFundingRequest(
  source: OrderFundingSource,
): OrderFundingRequest {
  if (
    !object(source) || !Object.hasOwn(ORDER_FUNDING_ENDPOINTS, source.api) ||
    typeof source.client_code !== "string" ||
    !/^[A-Za-z0-9_-]{1,20}$/.test(source.client_code) ||
    typeof source.pan !== "string" ||
    !/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(source.pan) ||
    !object(source.request) || !object(source.selectors)
  ) return invalid();
  const r: Record<string, unknown> = source.request;
  const s: Record<string, unknown> = source.selectors;
  const selected = Object.keys(s).length > 0;
  switch (source.api) {
    case "ORDER_LIFECYCLE":
      keys(r, ["from_date", "to_date", "client_code"], [
        "Product_type",
        "product_id",
      ]);
      if (selected) {
        // Only TWO_FA evidence types have proven selector lineage in this slice.
        keys(s, ["Product_type", "product_id"]);
        if (
          !["PUR", "RED", "SWITCH", "SIP", "STP", "SWP"].includes(
            String(s.Product_type),
          )
        ) invalid();
        ids(s.product_id);
        if (
          r.Product_type !== s.Product_type || r.product_id !== s.product_id
        ) invalid();
      } else if ("Product_type" in r || "product_id" in r) invalid();
      break;
    case "TRANSACTION_DETAIL":
      keys(r, ["from_date", "to_date", "client_code", "date_type"], [
        "order_id",
      ]);
      if (
        !["REQUEST_DATE", "ORDER_DATE", "LAST_ACTIVITY_DATE"].includes(
          String(r.date_type),
        )
      ) invalid();
      if (selected) {
        keys(s, ["order_id"]);
        ids(s.order_id);
        if (r.order_id !== s.order_id) invalid();
      } else if ("order_id" in r) invalid();
      // order_id overrides systematic_reg_id and all other filters (p153).
      // Systematic selection has no proven response-to-registration mapping yet.
      break;
    case "FUND_ORDER":
      keys(r, ["from_date", "to_date", "client_code"]);
      if (selected) invalid(); // pg_bank_refno identifier domain is unresolved.
      break;
    case "FUND_AGE":
      keys(r, ["date", "client_code", "settlement_type"]);
      if (selected || r.settlement_type !== "all") invalid();
      date(r.date);
      break;
  }
  if (r.client_code !== source.client_code) invalid();
  if ("from_date" in r) {
    const gap = (date(r.to_date) - date(r.from_date)) / 86400000;
    // FUND_ORDER has no documented maximum date gap (p116). Never borrow one.
    const max = source.api === "FUND_ORDER"
      ? Infinity
      : source.api === "TRANSACTION_DETAIL" &&
          r.date_type === "LAST_ACTIVITY_DATE"
      ? 3
      : 7;
    if (gap < 0 || gap > max) invalid();
  }
  return { ...source.request };
}
function stringRow(
  row: unknown,
  required: string[],
): row is Record<string, string> {
  return object(row) && required.every((k) => typeof row[k] === "string") &&
    Object.values(row).every((v) => typeof v === "string");
}
function identifier(v: string) {
  return /^[A-Za-z0-9_-]+$/.test(v);
}
function lifecycle(row: unknown, source: OrderFundingSource): boolean {
  if (
    !stringRow(row, [
      "client_code",
      "product_type",
      "product_id",
      "order_status",
      "payment_status",
      "reconciliation_status",
    ]) ||
    row.client_code !== source.client_code || !identifier(row.product_id) ||
    ![
      "PUR",
      "RED",
      "SWITCH",
      "SIP",
      "STP",
      "SWP",
      "MANDATE",
      "SIP CANCEL",
      "XSIP CANCEL",
      "STP CANCEL",
      "SWP CANCEL",
    ].includes(row.product_type)
  ) return false;
  const s = source.selectors;
  return !("product_id" in s) ||
    row.product_type === s.Product_type &&
      ids(s.product_id).includes(row.product_id);
}
function transaction(row: unknown, source: OrderFundingSource): boolean {
  if (
    !stringRow(row, [
      "client_code",
      "primary_holder_pan",
      "product_type",
      "product_id",
      "sip_registration_no",
      "order_status",
      "payment_status",
      "reconciliation_status",
    ]) ||
    row.client_code !== source.client_code ||
    row.primary_holder_pan !== source.pan ||
    !identifier(row.product_id) || !row.product_type.trim()
  ) return false;
  // Native product_type is descriptive, e.g. NORMAL PURCHASE (p154), not PUR.
  return !("order_id" in source.selectors) ||
    ids(source.selectors.order_id).includes(row.product_id);
}
function fundOrder(row: unknown, source: OrderFundingSource): boolean {
  return stringRow(row, [
    "clientcode",
    "cfppgbankrefno",
    "utrno",
    "id",
    "totalamount",
    "totalallocatedamount",
    "remainingamount",
    "mappedorders",
    "settledorders",
    "allotmentorders",
  ]) &&
    row.clientcode === source.client_code && identifier(row.cfppgbankrefno) &&
    identifier(row.id) && !!row.utrno.trim();
  // Amounts/mapped order strings stay native evidence; no financial interpretation.
}
function fundAge(row: unknown, source: OrderFundingSource): boolean {
  return stringRow(row, [
    "clientcode",
    "orderno",
    "date",
    "schemecode",
    "orderstatus",
    "funds_received_status",
  ]) &&
    row.clientcode === source.client_code && identifier(row.orderno) &&
    !!row.schemecode.trim() &&
    row.date === (source.request as { date: string }).date.replaceAll("-", "/");
  // p120's I/C are examples, not an exhaustive status enum or settled flags.
}
// Same PostgreSQL JSON representability boundary as the existing evidence path.
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
      for (const [key, child] of Object.entries(item)) {
        pending.push(key, child);
      }
    }
  }
  return true;
}
export function parseNseOrderFundingResponse(
  raw: string,
  source: OrderFundingSource,
): OrderFundingObservation {
  let nativeStatus: "S" | "F" | null = null;
  const fail = (
    category = "order_funding_response_invalid",
  ): OrderFundingObservation => ({
    nativeStatus,
    nativeRemarkCategory: category,
    success: false,
    recordCount: 0,
  });
  try {
    buildNseOrderFundingRequest(source);
    const e: unknown = JSON.parse(raw);
    if (
      !object(e) || !databaseJsonCompatible(e) ||
      (e.response_status !== "S" && e.response_status !== "F")
    ) return fail();
    nativeStatus = e.response_status as "S" | "F";
    // Lifecycle has only an S example; F cannot yield trusted observations.
    if (nativeStatus === "F" && source.api === "ORDER_LIFECYCLE") {
      return fail("order_funding_business_failed");
    }
    const total = e.report_data_total;
    if (
      (typeof total !== "number" &&
        !(typeof total === "string" && /^\d+$/.test(total))) ||
      !Number.isSafeInteger(Number(total)) || Number(total) < 0 ||
      Number(total) > 10000 || typeof e.error_remark !== "string"
    ) return fail();
    if (nativeStatus === "F") {
      return e.report_data === "" && Number(total) === 0
        ? fail("order_funding_business_failed")
        : fail();
    }
    if (
      !Array.isArray(e.report_data) || e.report_data.length !== Number(total)
    ) return fail();
    // Endpoint-specific empty-success diagnostics only; never generalize unknown remarks.
    const lifecycleNoRecords = source.api === "ORDER_LIFECYCLE" &&
      Number(total) === 0 && e.error_remark === "No record(s) found.";
    const fundAgeHistoricalEmpty = source.api === "FUND_AGE" &&
      Number(total) === 0;
    if (
      e.error_remark !== "" && !lifecycleNoRecords && !fundAgeHistoricalEmpty
    ) return fail();
    const seen = new Set<string>();
    for (const row of e.report_data) {
      const valid = source.api === "ORDER_LIFECYCLE"
        ? lifecycle(row, source)
        : source.api === "TRANSACTION_DETAIL"
        ? transaction(row, source)
        : source.api === "FUND_ORDER"
        ? fundOrder(row, source)
        : fundAge(row, source);
      if (!valid) return fail("order_funding_row_scope_invalid");
      // No undocumented funding uniqueness key: reject exact duplicate objects.
      const key =
        source.api === "ORDER_LIFECYCLE" || source.api === "TRANSACTION_DETAIL"
          ? JSON.stringify([row.product_type, row.product_id])
          : JSON.stringify(Object.keys(row).sort().map((k) => [k, row[k]]));
      if (seen.has(key)) return fail("order_funding_duplicate_rows");
      seen.add(key);
    }
    return {
      nativeStatus,
      nativeRemarkCategory: lifecycleNoRecords
        ? "order_funding_no_records"
        : Number(total) === 0 && e.error_remark !== ""
        ? "order_funding_empty_success_diagnostic"
        : "order_funding_report_received",
      success: true,
      recordCount: Number(total),
    };
  } catch {
    return fail();
  }
}
