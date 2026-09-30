/** Exact, intentionally small contract for NSE's read-only ORDER_STATUS report. */
export const NSE_ORDER_STATUS_ENDPOINT =
  "/nsemfdesk/api/v2/reports/ORDER_STATUS";

export type NseOrderStatusRequest = {
  client_code: string;
  from_date: string;
  to_date: string;
  trans_type: "P" | "R" | "ALL";
  order_type: "ALL" | "NRM" | "SIP" | "XSP" | "STP";
  sub_order_type: "ALL" | "NRM" | "SPOR" | "SWH" | "STP";
  order_status?: "All" | "VALID" | "INVALID";
  settlement_type?: "ALL" | "L0" | "L1" | "OTHERS";
  order_ids?: string;
  member_unique_ids?: string;
};

const date = /^\d{4}-\d{2}-\d{2}$/;
const clientCode = /^[A-Z0-9]{1,10}$/;
const allowed = {
  trans_type: new Set(["P", "R", "ALL"]),
  order_type: new Set(["ALL", "NRM", "SIP", "XSP", "STP"]),
  sub_order_type: new Set(["ALL", "NRM", "SPOR", "SWH", "STP"]),
  order_status: new Set(["All", "VALID", "INVALID"]),
  settlement_type: new Set(["ALL", "L0", "L1", "OTHERS"]),
};

export class NseOrderStatusValidationError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "NseOrderStatusValidationError";
  }
}

function requiredEnum<K extends keyof typeof allowed>(
  input: Record<string, unknown>,
  key: K,
): string {
  const value = input[key];
  if (typeof value !== "string" || !allowed[key].has(value)) {
    throw new NseOrderStatusValidationError(`order_status_${key}_invalid`);
  }
  return value;
}

function optionalEnum<K extends "order_status" | "settlement_type">(
  input: Record<string, unknown>,
  key: K,
): string | undefined {
  const value = input[key];
  if (value == null) return undefined;
  if (typeof value !== "string" || !allowed[key].has(value)) {
    throw new NseOrderStatusValidationError(`order_status_${key}_invalid`);
  }
  return value;
}

function boundedIds(value: unknown, key: "order_ids" | "member_unique_ids") {
  if (value == null) return undefined;
  if (
    !Array.isArray(value) || value.length === 0 || value.length > 50 ||
    value.some((id) =>
      typeof id !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(id)
    )
  ) {
    throw new NseOrderStatusValidationError(`order_status_${key}_invalid`);
  }
  return (value as string[]).join(",");
}

/** Maps only persisted service-owned source data; it never accepts date_type. */
export function buildNseOrderStatusRequest(
  source: unknown,
): NseOrderStatusRequest {
  if (source == null || typeof source !== "object" || Array.isArray(source)) {
    throw new NseOrderStatusValidationError("order_status_source_invalid");
  }
  const input = source as Record<string, unknown>;
  if (
    typeof input.client_code !== "string" || !clientCode.test(input.client_code)
  ) {
    throw new NseOrderStatusValidationError("order_status_client_code_invalid");
  }
  if (
    typeof input.from_date !== "string" || typeof input.to_date !== "string" ||
    !date.test(input.from_date) || !date.test(input.to_date)
  ) {
    throw new NseOrderStatusValidationError("order_status_date_invalid");
  }
  const start = Date.parse(`${input.from_date}T00:00:00Z`);
  const end = Date.parse(`${input.to_date}T00:00:00Z`);
  if (
    !Number.isFinite(start) || !Number.isFinite(end) || end < start ||
    end - start > 6 * 86_400_000
  ) {
    throw new NseOrderStatusValidationError("order_status_date_range_invalid");
  }
  const orderIds = boundedIds(input.order_ids, "order_ids");
  const memberIds = boundedIds(input.member_unique_ids, "member_unique_ids");
  const request: NseOrderStatusRequest = {
    client_code: input.client_code,
    from_date: input.from_date,
    to_date: input.to_date,
    trans_type: requiredEnum(
      input,
      "trans_type",
    ) as NseOrderStatusRequest["trans_type"],
    order_type: requiredEnum(
      input,
      "order_type",
    ) as NseOrderStatusRequest["order_type"],
    sub_order_type: requiredEnum(
      input,
      "sub_order_type",
    ) as NseOrderStatusRequest["sub_order_type"],
  };
  const status = optionalEnum(input, "order_status");
  const settlement = optionalEnum(input, "settlement_type");
  if (status) {
    request.order_status = status as NseOrderStatusRequest["order_status"];
  }
  if (settlement) {
    request.settlement_type =
      settlement as NseOrderStatusRequest["settlement_type"];
  }
  // NSE gives order IDs precedence when both future-bound ID filters exist.
  if (orderIds) request.order_ids = orderIds;
  else if (memberIds) request.member_unique_ids = memberIds;
  return request;
}

export type NseOrderStatusResponse = {
  responseStatus: "S" | "F" | null;
  recordCount: number;
  invalidCount: number;
  remarkCategory: string;
};

/** No row values are returned: observations are deliberately PII-free. */
export function parseNseOrderStatusResponse(
  raw: string,
): NseOrderStatusResponse {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return {
      responseStatus: null,
      recordCount: 0,
      invalidCount: 0,
      remarkCategory: "malformed_response",
    };
  }
  if (value == null || typeof value !== "object" || Array.isArray(value)) {
    return {
      responseStatus: null,
      recordCount: 0,
      invalidCount: 0,
      remarkCategory: "malformed_response",
    };
  }
  const response = value as Record<string, unknown>;
  const status = response.response_status;
  if (status !== "S" && status !== "F") {
    return {
      responseStatus: null,
      recordCount: 0,
      invalidCount: 0,
      remarkCategory: "malformed_response",
    };
  }
  const rows = Array.isArray(response.report_data) ? response.report_data : [];
  const invalidCount =
    rows.filter((row) =>
      row != null && typeof row === "object" &&
      (row as Record<string, unknown>).order_status === "INVALID"
    ).length;
  return {
    responseStatus: status,
    recordCount: rows.length,
    invalidCount,
    remarkCategory: status === "S"
      ? "report_success"
      : "report_business_failure",
  };
}
