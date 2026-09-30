/** NSE NNF 1.9.7 ORDER_STATUS report contract. */
export const NSE_ORDER_STATUS_ENDPOINT =
  "/nsemfdesk/api/v2/reports/ORDER_STATUS";
export const NSE_ORDER_STATUS_API_KEY = "ORDER_STATUS";

export type NseOrderStatusSource = {
  operation_id: string;
  client_code: string;
  from_date: string;
  to_date: string;
  order_status: string;
  transaction_type: string;
};
export type NseOrderStatusRequest = {
  client_code: string;
  from_date: string;
  to_date: string;
  order_status: string;
  transaction_type: string;
};
export class NseOrderStatusValidationError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "NseOrderStatusValidationError";
  }
}
const date = /^\d{4}-\d{2}-\d{2}$/;
const orderStatuses = new Set([
  "ALL",
  "PENDING",
  "ACCEPTED",
  "REJECTED",
  "CANCELLED",
  "EXPIRED",
]);
const transactionTypes = new Set([
  "ALL",
  "PURCHASE",
  "REDEMPTION",
  "SWITCH",
  "SIP",
  "STP",
  "SWP",
]);
export function buildNseOrderStatusRequest(
  source: NseOrderStatusSource,
): NseOrderStatusRequest {
  if (!/^[A-Z0-9]{1,10}$/.test(source.client_code)) {
    throw new NseOrderStatusValidationError("client_code_invalid");
  }
  if (!date.test(source.from_date) || !date.test(source.to_date)) {
    throw new NseOrderStatusValidationError("report_date_invalid");
  }
  const start = Date.parse(`${source.from_date}T00:00:00Z`),
    end = Date.parse(`${source.to_date}T00:00:00Z`);
  if (
    !Number.isFinite(start) || !Number.isFinite(end) || end < start ||
    end - start > 6 * 86400000
  ) throw new NseOrderStatusValidationError("report_date_range_invalid");
  if (!orderStatuses.has(source.order_status)) {
    throw new NseOrderStatusValidationError("order_status_invalid");
  }
  if (!transactionTypes.has(source.transaction_type)) {
    throw new NseOrderStatusValidationError("transaction_type_invalid");
  }
  return {
    client_code: source.client_code,
    from_date: source.from_date,
    to_date: source.to_date,
    order_status: source.order_status,
    transaction_type: source.transaction_type,
  };
}
export type NseOrderStatusResult = {
  businessSuccess: boolean;
  nativeStatus: string | null;
  observationCount: number;
  invalidCount: number;
};
export function parseNseOrderStatusResponse(raw: string): NseOrderStatusResult {
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new NseOrderStatusValidationError("nse_response_contract_invalid");
  }
  if (body == null || typeof body !== "object" || Array.isArray(body)) {
    throw new NseOrderStatusValidationError("nse_response_contract_invalid");
  }
  const root = body as Record<string, unknown>;
  const status = typeof root.status === "string" ? root.status : null;
  const rows = root.order_status ?? root.data ?? root.orders;
  if (!Array.isArray(rows) || status == null) {
    throw new NseOrderStatusValidationError("nse_response_contract_invalid");
  }
  const invalidCount =
    rows.filter((row) =>
      row == null || typeof row !== "object" || Array.isArray(row)
    ).length;
  return {
    businessSuccess: status === "S",
    nativeStatus: status,
    observationCount: rows.length,
    invalidCount,
  };
}
