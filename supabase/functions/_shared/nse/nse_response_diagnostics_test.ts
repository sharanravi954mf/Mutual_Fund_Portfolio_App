import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { matchNseResponseDiagnostic as match } from "./nse_response_diagnostics.ts";
import policy from "./nse_response_diagnostics_v1.json" with { type: "json" };
import {
  parseNseClientReadinessResponse,
  type ReadinessSource,
} from "./nse_client_readiness.ts";
for (const rule of policy.rules) {
  Deno.test(`Diagnostic policy ${rule.id}: exact endpoint/status/diagnostic/count/shape`, () => {
    assertEquals(match(rule.api, rule.native_status, rule.diagnostic, 0, []), {
      outcome: rule.outcome,
      category: rule.category,
      retry: false,
      ruleId: rule.id,
    });
    for (
      const args of [
        ["NSE_STP_REG_REPORT", rule.native_status, rule.diagnostic, 0, []],
        [rule.api, "UNKNOWN", rule.diagnostic, 0, []],
        [rule.api, rule.native_status, rule.diagnostic + " ", 0, []],
        [rule.api, rule.native_status, rule.diagnostic, 1, [{}]],
        [rule.api, rule.native_status, rule.diagnostic, 0, ""],
        [rule.api, rule.native_status, rule.diagnostic, 0, [{}]],
        [rule.api, rule.native_status, rule.diagnostic, NaN, []],
      ] as const
    ) assertEquals(match(args[0], args[1], args[2], args[3], args[4]), null);
  });
}
Deno.test("CLIENT_KYC_REPORT exact 2026-10-02 live diagnostic: empty observation only", () => {
  const source: ReadinessSource = {
    operation_id: "local",
    workspace_id: "local",
    integration_account_id: "local",
    client_code: "SYNTHETIC1",
    pan: "AAAAA0000A",
    api: "CLIENT_KYC_REPORT",
    request: { pan_no: "AAAAA0000A" },
  };
  const live = {
    response_status: "S",
    error_remark: "No record(s) found.",
    report_data_total: "0",
    report_data: [],
  };
  assertEquals(parseNseClientReadinessResponse(JSON.stringify(live), source), {
    nativeStatus: "S",
    nativeRemarkCategory: "client_readiness_report_received",
    success: true,
    recordCount: 0,
  });
  for (
    const patch of [
      { error_remark: "No record(s) found" },
      { error_remark: "Success" },
      { error_remark: null },
      { response_status: "F" },
      { report_data_total: "1" },
      { report_data: [{}] },
      { report_data: "" },
    ]
  ) {
    assertEquals(
      parseNseClientReadinessResponse(
        JSON.stringify({ ...live, ...patch }),
        source,
      ).success,
      false,
    );
  }
  for (
    const api of ["FATCA_REPORT", "CLIENT_AUTHORIZATION", "TWO_FA"] as const
  ) {
    assertEquals(
      parseNseClientReadinessResponse(JSON.stringify(live), { ...source, api })
        .success,
      false,
    );
  }
});
