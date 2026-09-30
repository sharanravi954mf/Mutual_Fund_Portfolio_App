export const NSE_ORDER_STATUS_ENDPOINT =
  "/nsemfdesk/api/v2/reports/ORDER_STATUS";

export type NseOrderStatusSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  correlation_id: string;
  client_code: string;
  from_date: string;
  to_date: string;
  trans_type: "P" | "R" | "ALL";
  order_type: "ALL" | "NRM" | "SIP" | "XSP" | "STP";
  sub_order_type: "ALL" | "NRM" | "SPOR" | "SWH" | "STP";
  order_status?: "All" | "VALID" | "INVALID";
  settlement_type?: "ALL" | "L0" | "L1" | "OTHERS";
  order_ids?: string[];
  member_unique_ids?: string[];
};

export class NseOrderStatusError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

const date = /^\d{4}-\d{2}-\d{2}$/;
const values = {
  trans_type: ["P", "R", "ALL"],
  order_type: ["ALL", "NRM", "SIP", "XSP", "STP"],
  sub_order_type: ["ALL", "NRM", "SPOR", "SWH", "STP"],
  order_status: ["All", "VALID", "INVALID"],
  settlement_type: ["ALL", "L0", "L1", "OTHERS"],
} as const;

function required(value: unknown, name: string) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new NseOrderStatusError(`order_status_${name}_required`);
  }
  return value.trim();
}
function enumValue(value: unknown, name: keyof typeof values) {
  const result = required(value, name);
  if (!(values[name] as readonly string[]).includes(result)) {
    throw new NseOrderStatusError(`order_status_${name}_invalid`);
  }
  return result;
}
function ids(value: unknown, name: string) {
  if (value == null) return undefined;
  if (
    !Array.isArray(value) || value.length === 0 || value.length > 50 ||
    value.some((id) =>
      typeof id !== "string" || !/^[A-Za-z0-9_-]{1,64}$/.test(id)
    )
  ) {
    throw new NseOrderStatusError(`order_status_${name}_invalid`);
  }
  return value;
}

export function buildNseOrderStatusRequest(source: NseOrderStatusSource) {
  const fromDate = required(source.from_date, "from_date");
  const toDate = required(source.to_date, "to_date");
  const start = Date.parse(`${fromDate}T00:00:00Z`);
  const end = Date.parse(`${toDate}T00:00:00Z`);
  if (
    !date.test(fromDate) || !date.test(toDate) || Number.isNaN(start) ||
    Number.isNaN(end) || end < start || end - start > 6 * 86_400_000
  ) {
    throw new NseOrderStatusError("order_status_date_range_invalid");
  }
  const orderIds = ids(source.order_ids, "order_ids");
  const memberIds = orderIds == null
    ? ids(source.member_unique_ids, "member_unique_ids")
    : undefined;
  const body: Record<string, unknown> = {
    client_code: required(source.client_code, "client_code").toUpperCase(),
    from_date: fromDate,
    to_date: toDate,
    trans_type: enumValue(source.trans_type, "trans_type"),
    order_type: enumValue(source.order_type, "order_type"),
    sub_order_type: enumValue(source.sub_order_type, "sub_order_type"),
  };
  if (source.order_status != null) {
    body.order_status = enumValue(source.order_status, "order_status");
  }
  if (source.settlement_type != null) {
    body.settlement_type = enumValue(source.settlement_type, "settlement_type");
  }
  if (orderIds != null) body.order_ids = orderIds;
  else if (memberIds != null) body.member_unique_ids = memberIds;
  return body;
}

export type NseOrderStatusObservation = {
  nativeStatus: string | null;
  nativeRemarkCategory: string;
  recordCount: number;
  projectedRecords: Array<Record<string, string | number | null>>;
};
const prohibited = /applicant|account|mobile|email|holder|remark/i;
const allowed = new Set([
  "order_id",
  "member_unique_id",
  "order_status",
  "product_code",
  "product_name",
  "amount",
  "units",
  "transaction_type",
  "order_type",
  "sub_order_type",
  "settlement_type",
  "order_date",
]);
export function parseNseOrderStatusResponse(
  rawBody: string,
): NseOrderStatusObservation {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    throw new NseOrderStatusError("order_status_response_not_json");
  }
  if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new NseOrderStatusError("order_status_response_invalid");
  }
  const object = parsed as Record<string, unknown>;
  if (object.response_status !== "S" && object.response_status !== "F") {
    throw new NseOrderStatusError("order_status_response_status_invalid");
  }
  const rows = object.report_data;
  if (rows != null && !Array.isArray(rows)) {
    throw new NseOrderStatusError("order_status_response_invalid");
  }
  const projectedRecords = (rows ?? []).map((row) => {
    if (row == null || typeof row !== "object" || Array.isArray(row)) {
      throw new NseOrderStatusError("order_status_response_invalid");
    }
    const projected: Record<string, string | number | null> = {};
    for (const [key, value] of Object.entries(row as Record<string, unknown>)) {
      if (
        allowed.has(key) && !prohibited.test(key) &&
        (typeof value === "string" || typeof value === "number" ||
          value === null)
      ) projected[key] = value;
    }
    return projected;
  });
  return {
    nativeStatus: object.response_status,
    nativeRemarkCategory: object.response_status === "S"
      ? "order_status_report_received"
      : "order_status_business_failure",
    recordCount: projectedRecords.length,
    projectedRecords,
  };
}
