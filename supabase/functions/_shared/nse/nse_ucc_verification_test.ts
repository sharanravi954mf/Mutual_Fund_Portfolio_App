import {
  assertEquals,
  assertFalse,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseClientMasterRequest,
  NseUccVerificationError,
  parseNseClientMasterResponse,
} from "./nse_ucc_verification.ts";

const source = {
  operation_id: "10000000-0000-4000-8000-000000000001",
  target_operation_id: "10000000-0000-4000-8000-000000000002",
  workspace_id: "10000000-0000-4000-8000-000000000003",
  integration_account_id: "10000000-0000-4000-8000-000000000004",
  correlation_id: "10000000-0000-4000-8000-000000000005",
  verification_purpose: "POST_REGISTRATION_VERIFICATION" as const,
  intended_client_code: "MBUAT0001",
  pan: "AAAAA0000A",
};

Deno.test("client master request sends client code and blank optional filters", () => {
  const request = buildNseClientMasterRequest(source);
  assertEquals(request, {
    client_code: "MBUAT0001",
    PAN: "",
    from_date: "",
    to_date: "",
  });
  assertFalse(JSON.stringify(request).includes(source.pan));
});
Deno.test("client master parser requires exact returned client code and secured PAN", () => {
  const body = JSON.stringify({
    response_status: "S",
    report_data: [{
      client_code: "MBUAT0001",
      primary_holder_pan: "AAAAA0000A",
    }],
  });
  assertEquals(parseNseClientMasterResponse(body, "MBUAT0001", "AAAAA0000A"), {
    nativeStatus: "S",
    nativeRemarkCategory: "ucc_match_confirmed",
    exactIdentityMatch: true,
    recordCount: 1,
  });
  assertFalse(
    parseNseClientMasterResponse(body, "MBUAT0001", "BBBBB0000B")
      .exactIdentityMatch,
  );
});
Deno.test("client master parser rejects an identity match when response status is not S", () => {
  const body = JSON.stringify({
    response_status: "F",
    report_data: [{
      client_code: "MBUAT0001",
      primary_holder_pan: "AAAAA0000A",
    }],
  });
  assertEquals(parseNseClientMasterResponse(body, "MBUAT0001", "AAAAA0000A"), {
    nativeStatus: "F",
    nativeRemarkCategory: "ucc_match_not_confirmed",
    exactIdentityMatch: false,
    recordCount: 1,
  });
});
Deno.test("client master request validates secured identity even though PAN is not transmitted", () => {
  assertThrows(
    () => buildNseClientMasterRequest({ ...source, pan: "invalid" }),
    NseUccVerificationError,
  );
});
