/** NSE handbook v1.9.7 pp78–82; recovered decisions C022/C032 and D21. */
import {
  buildNseOrderStatusRequest,
  type NseOrderStatusObservation,
  type NseOrderStatusRequest,
  parseNseOrderStatusResponse,
} from "./nse_order_status.ts";

export const NSE_PROV_ORDERS_ENDPOINT = "/nsemfdesk/api/v2/reports/PROV_ORDERS";
export type NseProvOrdersRequest = NseOrderStatusRequest & {
  date_type?: "REQUEST DATE" | "ORDER DATE" | null;
};
export type NseProvOrdersSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  request: NseProvOrdersRequest;
};
export type NseProvOrdersObservation = NseOrderStatusObservation;

/** Shared p78 fields retain required syntax, even with an effective ID filter.
 * MoneyBowl supplies account identity and evidence-derived IDs, never callers.
 * Explicitly emit the handbook default for absent/null date_type.
 */
export function buildNseProvOrdersRequest(
  source: NseProvOrdersSource,
): NseProvOrdersRequest {
  try {
    if (
      !source.request || typeof source.request !== "object" ||
      Array.isArray(source.request)
    ) {
      throw new Error();
    }
    const { date_type, ...common } = source.request;
    if (
      date_type != null && date_type !== "REQUEST DATE" &&
      date_type !== "ORDER DATE"
    ) {
      throw new Error();
    }
    return {
      ...buildNseOrderStatusRequest({ ...source, request: common }),
      date_type: date_type ?? "REQUEST DATE",
    };
  } catch {
    throw new Error("prov_orders_request_invalid");
  }
}

/** The shared envelope/identity columns are documented together on pp79–83.
 * PROV_ORDERS rows use request_date (not ORDER_STATUS's order_date); neither
 * sample specifies requiredness for every column. No date/settlement/financial
 * field is projected or renamed. The ORDER_STATUS live-UAT diagnostic exception
 * is NOT authority for this route: p79 still requires a blank success remark.
 */
export function parseNseProvOrdersResponse(
  rawBody: string,
  request: NseProvOrdersRequest,
): NseProvOrdersObservation {
  const common = parseNseOrderStatusResponse(rawBody, request);
  if (common.success && JSON.parse(rawBody).error_remark !== "") {
    return {
      nativeStatus: "S",
      nativeRemarkCategory: "prov_orders_response_invalid",
      success: false,
      recordCount: 0,
      validCount: 0,
      invalidCount: 0,
      otherCount: 0,
    };
  }
  return {
    ...common,
    nativeRemarkCategory: common.nativeRemarkCategory.replace(
      /^order_status_/,
      "prov_orders_",
    ),
  };
}
