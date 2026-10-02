/** Handbook v1.9.7 pp83–84; C031 VERSION_FILTER_ADDITION.
 * Only an owned UCC or a MoneyBowl-owned member reference, never member-wide dates.
 * A unique row establishes existence only, never consent or document receipt.
 */
export const MANDATE_STATUS_ENDPOINTS = {
  MANDATE_STATUS: "/nsemfdesk/api/v2/reports/MANDATE_STATUS",
} as const;
export type MandateStatusApi = keyof typeof MANDATE_STATUS_ENDPOINTS;
export type MandateStatusSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  api: MandateStatusApi;
  client_code: string;
  pan: string;
  bank_account_number?: string;
  request: { client_code: string } | { memberMandateIds: string };
};
function object(v: unknown): v is Record<string, unknown> {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}
export function buildNseMandateStatusRequest(source: MandateStatusSource) {
  const r = source.request;
  if (
    source.api !== "MANDATE_STATUS" ||
    !/^[A-Za-z0-9_-]{1,20}$/.test(source.client_code) ||
    !object(r) || Object.keys(r).length !== 1 ||
    !("client_code" in r && r.client_code === source.client_code ||
      "memberMandateIds" in r && typeof r.memberMandateIds === "string" &&
        /^[0-9a-f]{20}$/.test(r.memberMandateIds) &&
        typeof source.bank_account_number === "string" &&
        /^[A-Z0-9]{1,40}$/.test(source.bank_account_number))
  ) {
    throw new Error("mandate_status_request_invalid");
  }
  return { ...r };
}
export function parseNseMandateStatusResponse(
  raw: string,
  source: MandateStatusSource,
) {
  let nativeStatus: "S" | "F" | null = null;
  const fail = (nativeRemarkCategory = "mandate_status_response_invalid") => ({
    nativeStatus,
    nativeRemarkCategory,
    success: false,
    recordCount: 0,
  });
  try {
    buildNseMandateStatusRequest(source);
    const e: unknown = JSON.parse(raw);
    const pending: unknown[] = [e];
    while (pending.length) {
      const v = pending.pop();
      if (typeof v === "number" && !Number.isFinite(v)) return fail();
      if (
        typeof v === "string" &&
        /\u0000|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/
          .test(v)
      ) return fail();
      if (v && typeof v === "object") {
        for (const [k, c] of Object.entries(v)) pending.push(k, c);
      }
    }
    if (!object(e) || !["S", "F"].includes(String(e.response_status))) {
      return fail();
    }
    nativeStatus = e.response_status as "S" | "F";
    if (nativeStatus === "F") return fail("mandate_status_business_failed");
    const count = e.report_data_total;
    if (
      e.error_remark !== "" || !Array.isArray(e.report_data) ||
      !((typeof count === "string" && /^\d+$/.test(count)) ||
        (typeof count === "number" && Number.isSafeInteger(count) &&
          count >= 0)) ||
      Number(count) !== e.report_data.length || e.report_data.length > 10000
    ) return fail();
    if (e.report_data.length !== 1) {
      return fail("mandate_status_unique_match_required");
    }
    const row: unknown = e.report_data[0];
    if (!object(row)) return fail();
    if (
      ![
        "mandateId",
        "clientCode",
        "memberCode",
        "memberMandateId",
        "bankAccountNumber",
        "status",
      ].every((k) => typeof row[k] === "string") ||
      !Object.values(row).every((v) => typeof v === "string") ||
      !String(row.mandateId).trim() || !String(row.status).trim() ||
      row.clientCode !== source.client_code ||
      ("memberMandateIds" in source.request &&
        (row.memberMandateId !== source.request.memberMandateIds ||
          row.bankAccountNumber !== source.bank_account_number))
    ) return fail("mandate_status_row_scope_invalid");
    // PostgreSQL jsonb rejects NUL and unpaired UTF-16 surrogate code points.
    if (
      Object.entries(row).flat().some((v) =>
        typeof v === "string" &&
        /\u0000|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/
          .test(v)
      )
    ) return fail();
    return {
      nativeStatus,
      nativeRemarkCategory: "mandate_status_unique_match_received",
      success: true,
      recordCount: 1,
    };
  } catch {
    return fail();
  }
}
