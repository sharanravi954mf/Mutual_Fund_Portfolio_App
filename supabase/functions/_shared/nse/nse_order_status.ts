/** NSE handbook v1.9.7 pp78–83; recovered decisions C023/C032 and D21. */
export const NSE_ORDER_STATUS_ENDPOINT =
  "/nsemfdesk/api/v2/reports/ORDER_STATUS";

export type NseOrderStatusRequest = {
  from_date: string;
  to_date: string;
  trans_type: "P" | "R" | "ALL";
  order_type: "ALL" | "NRM" | "SIP" | "XSP" | "STP";
  sub_order_type: "ALL" | "NRM" | "SPOR" | "SWH" | "STP";
  client_code: string;
  order_status: "" | "All" | "VALID" | "INVALID";
  settlement_type: "" | "ALL" | "L0" | "L1" | "OTHERS";
  order_ids: string;
  member_unique_ids: string;
};

export type NseOrderStatusSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  request: NseOrderStatusRequest;
};

export type NseOrderStatusObservation = {
  nativeStatus: "S" | "F" | null;
  nativeRemarkCategory: string;
  success: boolean;
  recordCount: number;
  validCount: number;
  invalidCount: number;
  otherCount: number;
};

function invalid(): never {
  // Field values, IDs and provider text must never enter diagnostics.
  throw new Error("order_status_request_invalid");
}

function date(value: unknown): number {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return invalid();
  }
  const milliseconds = Date.parse(value + "T00:00:00Z");
  if (
    !Number.isFinite(milliseconds) ||
    new Date(milliseconds).toISOString().slice(0, 10) !== value ||
    value.startsWith("0000")
  ) return invalid();
  return milliseconds;
}

function ids(value: unknown, maximumLength?: number): string[] {
  if (value === "") return [];
  if (typeof value !== "string") return invalid();
  const values = value.split(",");
  if (
    values.length > 50 ||
    values.some((id) =>
      !id || id.trim() !== id || /[\x00-\x1f\x7f]/.test(id) ||
      (maximumLength != null && [...id].length > maximumLength)
    )
  ) return invalid();
  return values;
}

/** Only service-owned database projections may supply client codes and IDs. */
export function buildNseOrderStatusRequest(
  source: NseOrderStatusSource,
): NseOrderStatusRequest {
  const request = source.request;
  if (!request || typeof request !== "object" || Array.isArray(request)) {
    return invalid();
  }
  const fields = [
    "from_date",
    "to_date",
    "trans_type",
    "order_type",
    "sub_order_type",
    "client_code",
    "order_status",
    "settlement_type",
    "order_ids",
    "member_unique_ids",
  ];
  if (
    Object.keys(request).some((key) => !fields.includes(key)) ||
    fields.some((key) =>
      typeof request[key as keyof NseOrderStatusRequest] !== "string"
    )
  ) {
    return invalid();
  }
  const days = (date(request.to_date) - date(request.from_date)) / 86_400_000;
  // Seven inclusive calendar dates, as in the handbook's Nov 10–16 example.
  if (
    days < 0 || days > 6 ||
    !["P", "R", "ALL"].includes(request.trans_type) ||
    !["ALL", "NRM", "SIP", "XSP", "STP"].includes(request.order_type) ||
    !["ALL", "NRM", "SPOR", "SWH", "STP"].includes(request.sub_order_type) ||
    !["", "All", "VALID", "INVALID"].includes(request.order_status) ||
    !["", "ALL", "L0", "L1", "OTHERS"].includes(request.settlement_type) ||
    !request.client_code || [...request.client_code].length > 20 ||
    request.client_code.trim() !== request.client_code ||
    /[\x00-\x1f\x7f,]/.test(request.client_code)
  ) return invalid();
  ids(request.order_ids);
  ids(request.member_unique_ids, 25);
  // Keep mandatory syntax even when NSE ignores these filters due to IDs.
  return { ...request };
}

// The evidence classifier also runs in PostgreSQL. JSON with decoded NUL or
// lone UTF-16 surrogates cannot be represented in jsonb; reject it consistently.
function databaseJsonCompatible(value: unknown): boolean {
  const pending: unknown[] = [value];
  while (pending.length) {
    const item = pending.pop();
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

/** Read success is not order success, settlement, or proof of a missing write. */
export function parseNseOrderStatusResponse(
  rawBody: string,
  request: NseOrderStatusRequest,
): NseOrderStatusObservation {
  const observation: NseOrderStatusObservation = {
    nativeStatus: null,
    nativeRemarkCategory: "order_status_response_invalid",
    success: false,
    recordCount: 0,
    validCount: 0,
    invalidCount: 0,
    otherCount: 0,
  };
  let body;
  try {
    body = JSON.parse(rawBody);
  } catch {
    return observation;
  }
  if (
    !body || typeof body !== "object" || Array.isArray(body) ||
    !databaseJsonCompatible(body)
  ) {
    return observation;
  }
  if (body.response_status === "S" || body.response_status === "F") {
    observation.nativeStatus = body.response_status;
  }
  const total = body.report_data_total;
  if (
    (typeof total !== "number" &&
      !(typeof total === "string" && /^\d+$/.test(total))) ||
    !Number.isSafeInteger(Number(total)) || Number(total) < 0 ||
    typeof body.error_remark !== "string"
  ) return observation;
  if (body.response_status === "F") {
    if (body.report_data === "" && Number(total) === 0) {
      observation.nativeRemarkCategory = "order_status_vendor_rejected";
    }
    return observation;
  }
  if (
    body.response_status !== "S" || !Array.isArray(body.report_data) ||
    body.report_data.length !== Number(total) || body.error_remark !== ""
  ) {
    return observation;
  }
  const orderIds = ids(request.order_ids);
  const memberIds = ids(request.member_unique_ids, 25);
  let valid = 0, invalid = 0, other = 0;
  for (const row of body.report_data) {
    if (
      !row || typeof row !== "object" || Array.isArray(row) ||
      typeof row.client_code !== "string" ||
      typeof row.order_id !== "string" || !row.order_id.trim() ||
      typeof row.order_status !== "string" || !row.order_status.trim()
    ) {
      return observation;
    }
    if (
      row.client_code !== request.client_code ||
      (orderIds.length > 0
        ? !orderIds.includes(row.order_id)
        : memberIds.length > 0 && !memberIds.includes(row.member_unique_id))
    ) {
      observation.nativeRemarkCategory = "order_status_scope_mismatch";
      return observation;
    }
    if (row.order_status === "VALID") valid++;
    else if (row.order_status === "INVALID") invalid++;
    else other++;
  }
  return {
    nativeStatus: "S",
    nativeRemarkCategory: Number(total) === 0
      ? "order_status_no_records"
      : "order_status_report_received",
    success: true,
    recordCount: Number(total),
    validCount: valid,
    invalidCount: invalid,
    otherCount: other,
  };
}
