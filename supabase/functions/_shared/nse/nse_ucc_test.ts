import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  assertIntegrationPayloadHasNoCredentials,
  buildNseUccRequest,
  NSE_UCC_FIELDS,
  type NseUccSource,
  NseUccValidationError,
  parseNseUccResponse,
} from "./nse_ucc.ts";

export function syntheticUccSource(): NseUccSource {
  return {
    operation_id: "00000000-0000-4000-8000-000000000101",
    workspace_id: "00000000-0000-4000-8000-000000000102",
    integration_account_id: "00000000-0000-4000-8000-000000000103",
    correlation_id: "00000000-0000-4000-8000-000000000104",
    registration_mode: "physical",
    investor_kind: "individual",
    external_account_candidate: "MBUAT0001",
    legal_first_name: "MONEYBOWL",
    legal_middle_name: "",
    legal_last_name: "SYNTHETIC",
    date_of_birth: "01/01/1990",
    gender: "other",
    residency: "resident_individual",
    occupation: "other",
    holding_mode: "single",
    pan_exempt: false,
    pan: "ZZZZZ0000Z",
    kyc_method: "kra",
    kyc_verified: true,
    ckyc_number: "",
    communication_preference: "electronic",
    mobile_owner_relationship: "self",
    email_owner_relationship: "self",
    onboarding_mode: "paper",
    nomination_opted_in: false,
    email: "ucc-fixture@moneybowl.invalid",
    mobile: "0000000000",
    address: {
      line_1: "SYNTHETIC UAT ADDRESS",
      line_2: "",
      line_3: "",
      city: "UATCITY",
      region: "synthetic_region",
      postal_code: "000000",
      country: "synthetic_country",
    },
    bank: {
      account_type: "savings",
      account_number: "TESTACCOUNT01",
      ifsc_code: "TEST0000000",
      micr_code: "",
      account_holder_name: "MONEYBOWL SYNTHETIC",
    },
    nse_codes: {
      tax_status: "01",
      occupation_code: "99",
      state: "ZZ",
      country: "INDIA",
      mobile_declaration_flag: "SE",
      email_declaration_flag: "SE",
      div_pay_mode: "04",
    },
  };
}

Deno.test("CLIENTCOMMON183 mapper emits one 175-field physical single-holder record", () => {
  const request = buildNseUccRequest(syntheticUccSource());
  assertEquals(NSE_UCC_FIELDS.length, 175);
  assertEquals(request.reg_details.length, 1);
  assertEquals(Object.keys(request.reg_details[0]).length, 175);
  assertEquals(request.reg_details[0].holding_nature, "SI");
  assertEquals(request.reg_details[0].client_type, "P");
  assertEquals(request.reg_details[0].account_type_1, "SB");
  assertEquals(request.reg_details[0].nomination_opt, "N");
  assertEquals(request.reg_details[0].account_no_2, "");
  assertEquals(request.reg_details[0].default_dp, "");
});

Deno.test("CLIENTCOMMON183 validation reports field names and codes without values", () => {
  const source = syntheticUccSource();
  source.bank.ifsc_code = "BADIFSC";
  let thrown: NseUccValidationError | null = null;
  try {
    buildNseUccRequest(source);
  } catch (error) {
    thrown = error as NseUccValidationError;
  }
  assertEquals(thrown instanceof NseUccValidationError, true);
  assertEquals(
    thrown?.issues.some((item) =>
      item.field === "ifsc_code_1" && item.code === "invalid_format"
    ),
    true,
  );
  assertEquals(JSON.stringify(thrown?.issues).includes("BADIFSC"), false);
});

Deno.test("integration payload credential keys are rejected recursively", () => {
  assertThrows(
    () =>
      assertIntegrationPayloadHasNoCredentials({
        reg_details: [{ authorization: "must-never-be-recorded" }],
      }),
    NseUccValidationError,
  );
});

Deno.test("UCC response parser keeps HTTP and business success separate", () => {
  const businessFailure = parseNseUccResponse(
    JSON.stringify({
      reg_details: [{
        client_code: "MBUAT0001",
        reg_id: "",
        reg_status: "REG_FAILED",
        reg_remark: "synthetic validation failure",
      }],
    }),
    200,
  );
  assertEquals(businessFailure.businessSuccess, false);
  assertEquals(
    businessFailure.nativeRemarkCategory,
    "integration_validation_remark",
  );

  const success = parseNseUccResponse(
    JSON.stringify({
      reg_details: [{
        client_code: "MBUAT0001",
        reg_id: "SYNTHETIC-REG",
        reg_status: "REG_SUCCESS",
        reg_remark: "",
      }],
    }),
    200,
  );
  assertEquals(success.businessSuccess, true);
  assertEquals(success.registrationReference, "SYNTHETIC-REG");
});

Deno.test("first-slice rejects minor, non-individual, non-physical and unverified KYC", () => {
  for (
    const mutate of [
      (source: NseUccSource) => source.date_of_birth = "01/01/2015",
      (source: NseUccSource) => source.investor_kind = "non_individual",
      (source: NseUccSource) => source.registration_mode = "demat",
      (source: NseUccSource) => source.kyc_verified = false,
    ]
  ) {
    const source = syntheticUccSource();
    mutate(source);
    assertThrows(
      () => buildNseUccRequest(source, new Date("2026-09-01T00:00:00Z")),
      NseUccValidationError,
    );
  }
});

Deno.test("NNF validation covers populated optional fields", () => {
  const source = syntheticUccSource();
  source.address.line_2 = "X".repeat(41);
  source.bank.micr_code = "123";
  source.bank.account_holder_name = "X".repeat(36);
  const error = assertThrows(
    () => buildNseUccRequest(source),
    NseUccValidationError,
  );
  assertEquals(error.issues.some((item) => item.field === "address_2"), true);
  assertEquals(error.issues.some((item) => item.field === "micr_no_1"), true);
  assertEquals(error.issues.some((item) => item.field === "cheque_name"), true);
});
