import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  assertIntegrationPayloadHasNoCredentials,
  buildNseUccRequest,
  NSE_UCC_CONTACT_DECLARATION_CODES,
  NSE_UCC_FIELDS,
  NSE_UCC_OCCUPATION_CODES,
  type NseUccSource,
  NseUccValidationError,
  parseNseUccResponse,
  validateNseUccRequest,
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
    pan: "ZZZPZ0000Z",
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
      region: "KARNATAKA",
      postal_code: "000000",
      country: "INDIA",
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
      occupation_code: "08",
      state: "KA",
      country: "INDIA",
      mobile_declaration_flag: "SE",
      email_declaration_flag: "SE",
      div_pay_mode: "04",
    },
  };
}

function expectValidationIssue(
  action: () => unknown,
  field: string,
  code: string,
): NseUccValidationError {
  const error = assertThrows(action, NseUccValidationError);
  assertEquals(
    error.issues.some((item) => item.field === field && item.code === code),
    true,
  );
  return error;
}

function requestWith(
  field: (typeof NSE_UCC_FIELDS)[number],
  value: string,
) {
  const request = buildNseUccRequest(syntheticUccSource());
  request.reg_details[0][field] = value;
  return request;
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

Deno.test("official NSE occupation codes 01 through 08 are accepted", () => {
  for (const occupationCode of NSE_UCC_OCCUPATION_CODES) {
    validateNseUccRequest(requestWith("occupation_code", occupationCode));
  }
});

Deno.test("occupation codes outside the official NSE master are rejected", () => {
  for (const occupationCode of ["00", "09", "99"]) {
    expectValidationIssue(
      () =>
        validateNseUccRequest(requestWith("occupation_code", occupationCode)),
      "occupation_code",
      "invalid_allowed_value",
    );
  }
});

Deno.test("canonical occupation must agree with the NSE occupation code", () => {
  const mismatch = syntheticUccSource();
  mismatch.nse_codes.occupation_code = "01";
  expectValidationIssue(
    () => buildNseUccRequest(mismatch),
    "nse_codes.occupation_code",
    "occupation_code_does_not_match_canonical_occupation",
  );

  const unsupported = syntheticUccSource();
  unsupported.occupation = "unsupported synthetic occupation";
  expectValidationIssue(
    () => buildNseUccRequest(unsupported),
    "occupation",
    "unsupported_canonical_occupation",
  );
});

Deno.test("first slice accepts only resident-individual tax status 01", () => {
  const source = syntheticUccSource();
  source.nse_codes.tax_status = "02";
  expectValidationIssue(
    () => buildNseUccRequest(source),
    "nse_codes.tax_status",
    "first_slice_requires_individual_tax_status",
  );
  expectValidationIssue(
    () => validateNseUccRequest(requestWith("tax_status", "02")),
    "tax_status",
    "first_slice_requires_individual_tax_status",
  );
});

Deno.test("individual tax status requires PAN fourth character P without exposing PAN", () => {
  buildNseUccRequest(syntheticUccSource());

  const source = syntheticUccSource();
  source.pan = "ZZZAZ0000Z";
  const error = expectValidationIssue(
    () => buildNseUccRequest(source),
    "primary_holder_pan",
    "individual_pan_category_mismatch",
  );
  assertEquals(JSON.stringify(error.issues).includes(source.pan), false);
  assertEquals(error.message.includes(source.pan), false);
});

Deno.test("state master code is normalized and must match canonical region", () => {
  const normalized = syntheticUccSource();
  normalized.nse_codes.state = " ka ";
  normalized.address.region = "  Karnataka  ";
  assertEquals(
    buildNseUccRequest(normalized).reg_details[0].state,
    "KA",
  );

  expectValidationIssue(
    () => validateNseUccRequest(requestWith("state", "ZZ")),
    "state",
    "invalid_allowed_value",
  );

  const mismatch = syntheticUccSource();
  mismatch.address.region = "MAHARASHTRA";
  expectValidationIssue(
    () => buildNseUccRequest(mismatch),
    "nse_codes.state",
    "state_code_does_not_match_canonical_region",
  );
});

Deno.test("official contact declaration codes are valid at request level", () => {
  for (const declarationCode of NSE_UCC_CONTACT_DECLARATION_CODES) {
    const request = buildNseUccRequest(syntheticUccSource());
    request.reg_details[0].mobile_declaration_flag = declarationCode;
    request.reg_details[0].email_declaration_flag = declarationCode;
    validateNseUccRequest(request);
  }
});

Deno.test("contact declaration codes outside the official master are rejected", () => {
  for (
    const field of [
      "mobile_declaration_flag",
      "email_declaration_flag",
    ] as const
  ) {
    expectValidationIssue(
      () => validateNseUccRequest(requestWith(field, "ZZ")),
      field,
      "invalid_allowed_value",
    );
  }
});

Deno.test("self-owned contacts require declaration code SE", () => {
  for (
    const field of [
      "mobile_declaration_flag",
      "email_declaration_flag",
    ] as const
  ) {
    const source = syntheticUccSource();
    source.nse_codes[field] = "SP";
    expectValidationIssue(
      () => buildNseUccRequest(source),
      `nse_codes.${field}`,
      field === "mobile_declaration_flag"
        ? "declaration_does_not_match_self_owned_mobile"
        : "declaration_does_not_match_self_owned_email",
    );
  }
});

Deno.test("first-slice defensive fields must remain blank", () => {
  const cases: Array<{
    field: (typeof NSE_UCC_FIELDS)[number];
    value: string;
    code: string;
  }> = [
    {
      field: "cdsl_dpid",
      value: "SYNTHETIC",
      code: "must_be_blank_for_physical",
    },
    {
      field: "primary_holder_exempt_category",
      value: "01",
      code: "must_be_blank_for_non_exempt_pan",
    },
    {
      field: "primary_holder_kra_exempt_ref_no",
      value: "SYNTHETIC",
      code: "must_be_blank_for_non_exempt_pan",
    },
    {
      field: "foreign_address_1",
      value: "SYNTHETIC",
      code: "must_be_blank_for_resident_individual",
    },
    {
      field: "second_holder_first_name",
      value: "SYNTHETIC",
      code: "must_be_blank_for_simple_fixture",
    },
    {
      field: "account_type_2",
      value: "SB",
      code: "first_slice_supports_one_bank",
    },
  ];

  for (const item of cases) {
    expectValidationIssue(
      () => validateNseUccRequest(requestWith(item.field, item.value)),
      item.field,
      item.code,
    );
  }
});
