export const NSE_UCC_ENDPOINT =
  "/nsemfdesk/api/v2/registration/CLIENTCOMMON183";
export const NSE_UCC_ENDPOINT_ID = "CLIENTCOMMON183";

export const NSE_UCC_FIELDS = [
  "client_code",
  "primary_holder_first_name",
  "primary_holder_middle_name",
  "primary_holder_last_name",
  "tax_status",
  "gender",
  "primary_holder_dob_incorporation",
  "occupation_code",
  "holding_nature",
  "second_holder_first_name",
  "second_holder_middle_name",
  "second_holder_last_name",
  "third_holder_first_name",
  "third_holder_middle_name",
  "third_holder_last_name",
  "second_holder_dob",
  "third_holder_dob",
  "guardian_first_name",
  "guardian_middle_name",
  "guardian_last_name",
  "guardian_dob",
  "primary_holder_pan_exempt",
  "second_holder_pan_exempt",
  "third_holder_pan_exempt",
  "guardian_pan_exempt",
  "primary_holder_pan",
  "second_holder_pan",
  "third_holder_pan",
  "guardian_pan",
  "primary_holder_exempt_category",
  "second_holder_exempt_category",
  "third_holder_exempt_category",
  "guardian_exempt_category",
  "client_type",
  "pms",
  "default_dp",
  "cdsl_dpid",
  "cdslcltid",
  "cmbp_id",
  "nsdldpid",
  "nsdlcltid",
  "account_type_1",
  "account_no_1",
  "micr_no_1",
  "ifsc_code_1",
  "default_bank_flag_1",
  "account_type_2",
  "account_no_2",
  "micr_no_2",
  "ifsc_code_2",
  "default_bank_flag_2",
  "account_type_3",
  "account_no_3",
  "micr_no_3",
  "ifsc_code_3",
  "default_bank_flag_3",
  "account_type_4",
  "account_no_4",
  "micr_no_4",
  "ifsc_code_4",
  "default_bank_flag_4",
  "account_type_5",
  "account_no_5",
  "micr_no_5",
  "ifsc_code_5",
  "default_bank_flag_5",
  "cheque_name",
  "div_pay_mode",
  "address_1",
  "address_2",
  "address_3",
  "city",
  "state",
  "pincode",
  "country",
  "resi_phone",
  "resi_fax",
  "office_phone",
  "office_fax",
  "email",
  "communication_mode",
  "foreign_address_1",
  "foreign_address_2",
  "foreign_address_3",
  "foreign_address_city",
  "foreign_address_pincode",
  "foreign_address_state",
  "foreign_address_country",
  "foreign_address_resi_phone",
  "foreign_address_fax",
  "foreign_address_off_phone",
  "foreign_address_off_fax",
  "indian_mobile_no",
  "primary_holder_kyc_type",
  "primary_holder_ckyc_number",
  "second_holder_kyc_type",
  "second_holder_ckyc_number",
  "third_holder_kyc_type",
  "third_holder_ckyc_number",
  "guardian_kyc_type",
  "guardian_ckyc_number",
  "primary_holder_kra_exempt_ref_no",
  "second_holder_kra_exempt_ref_no",
  "third_holder_kra_exempt_ref_no",
  "guardian_exempt_ref_no",
  "aadhaar_updated",
  "mapin_id",
  "paperless_flag",
  "lei_no",
  "lei_validity",
  "mobile_declaration_flag",
  "email_declaration_flag",
  "second_holder_email",
  "second_holder_email_declaration",
  "second_holder_mobile",
  "second_holder_mobile_declaration",
  "third_holder_email",
  "third_holder_email_declaration",
  "third_holder_mobile",
  "third_holder_mobile_declaration",
  "guardian_relation",
  "nomination_opt",
  "nomination_authentication",
  "nominee_1_name",
  "nominee_1_relationship",
  "nominee_1_applicable",
  "nominee_1_minor_flag",
  "nominee_1_dob",
  "nominee_1_guardian",
  "nominee_1_guardian_pan",
  "nominee_1_identity_type",
  "nominee_1_identity_number",
  "nominee_1_email",
  "nominee_1_mobile",
  "nominee_1_address1",
  "nominee_1_address2",
  "nominee_1_address3",
  "nominee_1_city",
  "nominee_1_pin",
  "nominee_1_country",
  "nominee_2_name",
  "nominee_2_relationship",
  "nominee_2_applicable",
  "nominee_2_minor_flag",
  "nominee_2_dob",
  "nominee_2_guardian",
  "nominee_2_guardian_pan",
  "nominee_2_identity_type",
  "nominee_2_identity_number",
  "nominee_2_email",
  "nominee_2_mobile",
  "nominee_2_address1",
  "nominee_2_address2",
  "nominee_2_address3",
  "nominee_2_city",
  "nominee_2_pin",
  "nominee_2_country",
  "nominee_3_name",
  "nominee_3_relationship",
  "nominee_3_applicable",
  "nominee_3_minor_flag",
  "nominee_3_dob",
  "nominee_3_guardian",
  "nominee_3_guardian_pan",
  "nominee_3_identity_type",
  "nominee_3_identity_number",
  "nominee_3_email",
  "nominee_3_mobile",
  "nominee_3_address1",
  "nominee_3_address2",
  "nominee_3_address3",
  "nominee_3_city",
  "nominee_3_pin",
  "nominee_3_country",
  "nominee_soa",
] as const;

export type NseUccRecord = Record<(typeof NSE_UCC_FIELDS)[number], string>;
export type NseUccRequest = { reg_details: [NseUccRecord] };

export type NseUccSource = {
  operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  correlation_id: string;
  external_account_candidate: string;
  registration_mode: string;
  investor_kind: string;
  legal_first_name: string;
  legal_middle_name: string;
  legal_last_name: string;
  date_of_birth: string;
  gender: string;
  residency: string;
  occupation: string;
  holding_mode: string;
  pan_exempt: boolean;
  pan: string;
  kyc_method: string;
  kyc_verified: boolean;
  ckyc_number: string;
  communication_preference: string;
  mobile_owner_relationship: string;
  email_owner_relationship: string;
  onboarding_mode: string;
  nomination_opted_in: boolean;
  email: string;
  mobile: string;
  address: {
    line_1: string;
    line_2: string;
    line_3: string;
    city: string;
    region: string;
    postal_code: string;
    country: string;
  };
  bank: {
    account_type: string;
    account_number: string;
    ifsc_code: string;
    micr_code: string;
    account_holder_name: string;
  };
  nse_codes: {
    tax_status: string;
    occupation_code: string;
    state: string;
    country: string;
    mobile_declaration_flag: string;
    email_declaration_flag: string;
    div_pay_mode: string;
  };
};

export type NseUccValidationIssue = { field: string; code: string };

export class NseUccValidationError extends Error {
  readonly issues: readonly NseUccValidationIssue[];

  constructor(issues: readonly NseUccValidationIssue[]) {
    super("NSE UCC request validation failed");
    this.name = "NseUccValidationError";
    this.issues = issues;
  }
}

const requiredLimits: Record<string, number> = {
  client_code: 10,
  primary_holder_first_name: 70,
  tax_status: 2,
  gender: 1,
  primary_holder_dob_incorporation: 10,
  occupation_code: 2,
  holding_nature: 2,
  primary_holder_pan_exempt: 1,
  primary_holder_pan: 10,
  client_type: 1,
  account_type_1: 2,
  account_no_1: 40,
  ifsc_code_1: 11,
  default_bank_flag_1: 1,
  div_pay_mode: 2,
  address_1: 120,
  city: 35,
  state: 2,
  pincode: 6,
  country: 35,
  email: 50,
  communication_mode: 1,
  indian_mobile_no: 10,
  primary_holder_kyc_type: 1,
  paperless_flag: 1,
  mobile_declaration_flag: 2,
  email_declaration_flag: 2,
  nomination_opt: 1,
};

const optionalLimits: Record<string, number> = {
  primary_holder_middle_name: 70,
  primary_holder_last_name: 70,
  micr_no_1: 9,
  cheque_name: 35,
  address_2: 40,
  address_3: 40,
  primary_holder_ckyc_number: 14,
};

const credentialKeyPattern =
  /^(authorization|cookie|set[_-]?cookie|api[_-]?key|api[_-]?secret|encrypted[_-]?password|password|client[_-]?secret|access[_-]?token|refresh[_-]?token)$/i;

export function assertIntegrationPayloadHasNoCredentials(value: unknown): void {
  if (Array.isArray(value)) {
    for (const item of value) assertIntegrationPayloadHasNoCredentials(item);
    return;
  }
  if (value == null || typeof value !== "object") return;
  for (const [key, nested] of Object.entries(value)) {
    if (credentialKeyPattern.test(key)) {
      throw new NseUccValidationError([{
        field: key,
        code: "credential_field_forbidden",
      }]);
    }
    assertIntegrationPayloadHasNoCredentials(nested);
  }
}

function emptyRecord(): NseUccRecord {
  return Object.fromEntries(
    NSE_UCC_FIELDS.map((field) => [field, ""]),
  ) as NseUccRecord;
}

const genderCode: Record<string, string> = {
  male: "M",
  female: "F",
  other: "O",
  transgender: "T",
};
const kycCode: Record<string, string> = {
  kra: "K",
  ckyc: "C",
  biometric: "B",
  aadhaar_ekyc_pan: "E",
};
const bankTypeCode: Record<string, string> = {
  savings: "SB",
  current: "CB",
  nre: "NE",
  nro: "NO",
};
const communicationCode: Record<string, string> = {
  physical: "P",
  electronic: "E",
  mobile: "M",
};

// NSE MF WebfileStructure business masters used by CLIENTCOMMON183. The NNF
// remains authoritative for the JSON contract itself.
export const NSE_UCC_OCCUPATION_CODES = [
  "01",
  "02",
  "03",
  "04",
  "05",
  "06",
  "07",
  "08",
] as const;

export const NSE_UCC_CONTACT_DECLARATION_CODES = [
  "SE",
  "SP",
  "DC",
  "DS",
  "DP",
  "GD",
  "PM",
  "CD",
  "PO",
] as const;

export const NSE_UCC_STATE_MASTER = {
  AN: "ANDAMAN & NICOBAR",
  AP: "ANDHRA PRADESH",
  AR: "ARUNACHAL PRADESH",
  AS: "ASSAM",
  BH: "BIHAR",
  CH: "CHANDIGARH",
  CG: "CHHATTISGARH",
  DN: "DADRA AND NAGAR HAVELI",
  DD: "DAMAN AND DIU",
  GO: "GOA",
  GU: "GUJARAT",
  HA: "HARYANA",
  HP: "HIMACHAL PRADESH",
  JM: "JAMMU & KASHMIR",
  JK: "JHARKHAND",
  KA: "KARNATAKA",
  KE: "KERALA",
  LD: "LAKSHADWEEP",
  MA: "MAHARASHTRA",
  MP: "MADHYA PRADESH",
  MN: "MANIPUR",
  ME: "MEGHALAYA",
  MI: "MIZORAM",
  NA: "NAGALAND",
  ND: "NEW DELHI",
  OR: "ODISHA",
  OH: "OTHERS",
  PO: "PONDICHERRY",
  PU: "PUNJAB",
  RA: "RAJASTHAN",
  SI: "SIKKIM",
  TN: "TAMIL NADU",
  TG: "TELANGANA",
  TR: "TRIPURA",
  UP: "UTTER PRADESH",
  UL: "UTTARAKHAND",
  WB: "WEST BENGAL",
} as const;

const occupationCodes = new Set<string>(NSE_UCC_OCCUPATION_CODES);
const declarationCodes = new Set<string>(NSE_UCC_CONTACT_DECLARATION_CODES);
const canonicalOccupationCode: Readonly<Record<string, string>> = {
  business: "01",
  services: "02",
  professional: "03",
  agriculture: "04",
  retired: "05",
  housewife: "06",
  student: "07",
  other: "08",
  others: "08",
};

const physicalOnlyBlankFields = [
  "pms",
  "default_dp",
  "cdsl_dpid",
  "cdslcltid",
  "cmbp_id",
  "nsdldpid",
  "nsdlcltid",
] as const;

const residentOnlyBlankFields = [
  "foreign_address_1",
  "foreign_address_2",
  "foreign_address_3",
  "foreign_address_city",
  "foreign_address_pincode",
  "foreign_address_state",
  "foreign_address_country",
  "foreign_address_resi_phone",
  "foreign_address_fax",
  "foreign_address_off_phone",
  "foreign_address_off_fax",
] as const;

function normalizeCanonicalMasterName(value: string): string {
  return value.trim().replace(/\s+/g, " ").toUpperCase();
}

function sourceIssue(field: string, code: string): never {
  throw new NseUccValidationError([{ field, code }]);
}

function parseIndianDate(value: string): Date | null {
  const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value);
  if (match == null) return null;
  const date = new Date(
    Date.UTC(Number(match[3]), Number(match[2]) - 1, Number(match[1])),
  );
  return date.getUTCFullYear() === Number(match[3]) &&
      date.getUTCMonth() === Number(match[2]) - 1 &&
      date.getUTCDate() === Number(match[1])
    ? date
    : null;
}

function isAdultOn(dateOfBirth: Date, asOf: Date): boolean {
  const birthday = new Date(Date.UTC(
    asOf.getUTCFullYear(),
    dateOfBirth.getUTCMonth(),
    dateOfBirth.getUTCDate(),
  ));
  const years = asOf.getUTCFullYear() - dateOfBirth.getUTCFullYear() -
    (asOf.getTime() < birthday.getTime() ? 1 : 0);
  return years >= 18;
}

export function buildNseUccRequest(
  source: NseUccSource,
  asOf = new Date(),
): NseUccRequest {
  if (source.investor_kind !== "individual") {
    sourceIssue("investor_kind", "first_slice_requires_individual");
  }
  const dob = parseIndianDate(source.date_of_birth);
  if (dob == null) sourceIssue("date_of_birth", "valid_date_of_birth_required");
  if (!isAdultOn(dob, asOf)) {
    sourceIssue("date_of_birth", "first_slice_requires_adult");
  }
  if (source.residency !== "resident_individual") {
    sourceIssue("residency", "first_slice_requires_resident_individual");
  }
  if (source.holding_mode !== "single") {
    sourceIssue("holding_mode", "first_slice_requires_single_holder");
  }
  if (source.registration_mode !== "physical") {
    sourceIssue("registration_mode", "first_slice_requires_physical");
  }
  if (source.pan_exempt) {
    sourceIssue("pan_exempt", "first_slice_requires_non_exempt_pan");
  }
  if (!source.kyc_verified) {
    sourceIssue("kyc_verified", "first_slice_requires_verified_kyc");
  }
  if (source.nomination_opted_in) {
    sourceIssue(
      "nomination_opted_in",
      "first_slice_requires_nomination_opt_out",
    );
  }
  if (genderCode[source.gender] == null) {
    sourceIssue("gender", "unsupported_gender");
  }
  if (kycCode[source.kyc_method] == null) {
    sourceIssue("kyc_method", "unsupported_kyc_method");
  }
  if (bankTypeCode[source.bank.account_type] == null) {
    sourceIssue("bank.account_type", "unsupported_bank_account_type");
  }
  if (communicationCode[source.communication_preference] == null) {
    sourceIssue("communication_preference", "unsupported_communication_mode");
  }
  if (!["paper", "paperless"].includes(source.onboarding_mode)) {
    sourceIssue("onboarding_mode", "unsupported_onboarding_mode");
  }

  const taxStatus = source.nse_codes.tax_status.trim();
  if (taxStatus !== "01") {
    sourceIssue(
      "nse_codes.tax_status",
      "first_slice_requires_individual_tax_status",
    );
  }

  const occupationCode = source.nse_codes.occupation_code.trim();
  if (!occupationCodes.has(occupationCode)) {
    sourceIssue("nse_codes.occupation_code", "invalid_nse_occupation_code");
  }
  const expectedOccupationCode = canonicalOccupationCode[
    source.occupation.trim().toLowerCase()
  ];
  if (expectedOccupationCode == null) {
    sourceIssue("occupation", "unsupported_canonical_occupation");
  }
  if (occupationCode !== expectedOccupationCode) {
    sourceIssue(
      "nse_codes.occupation_code",
      "occupation_code_does_not_match_canonical_occupation",
    );
  }

  const stateCode = source.nse_codes.state.trim().toUpperCase();
  const stateName = NSE_UCC_STATE_MASTER[
    stateCode as keyof typeof NSE_UCC_STATE_MASTER
  ];
  if (stateName == null) {
    sourceIssue("nse_codes.state", "invalid_nse_state_code");
  }
  if (
    normalizeCanonicalMasterName(source.address.region) !==
      normalizeCanonicalMasterName(stateName)
  ) {
    sourceIssue(
      "nse_codes.state",
      "state_code_does_not_match_canonical_region",
    );
  }

  const mobileDeclaration = source.nse_codes.mobile_declaration_flag.trim()
    .toUpperCase();
  const emailDeclaration = source.nse_codes.email_declaration_flag.trim()
    .toUpperCase();
  if (!declarationCodes.has(mobileDeclaration)) {
    sourceIssue(
      "nse_codes.mobile_declaration_flag",
      "invalid_nse_declaration_code",
    );
  }
  if (!declarationCodes.has(emailDeclaration)) {
    sourceIssue(
      "nse_codes.email_declaration_flag",
      "invalid_nse_declaration_code",
    );
  }
  if (source.mobile_owner_relationship.trim().toLowerCase() !== "self") {
    sourceIssue(
      "mobile_owner_relationship",
      "first_slice_requires_self_owned_mobile",
    );
  }
  if (mobileDeclaration !== "SE") {
    sourceIssue(
      "nse_codes.mobile_declaration_flag",
      "declaration_does_not_match_self_owned_mobile",
    );
  }
  if (source.email_owner_relationship.trim().toLowerCase() !== "self") {
    sourceIssue(
      "email_owner_relationship",
      "first_slice_requires_self_owned_email",
    );
  }
  if (emailDeclaration !== "SE") {
    sourceIssue(
      "nse_codes.email_declaration_flag",
      "declaration_does_not_match_self_owned_email",
    );
  }

  const record = emptyRecord();
  Object.assign(record, {
    client_code: source.external_account_candidate.trim().toUpperCase(),
    primary_holder_first_name: source.legal_first_name.trim(),
    primary_holder_middle_name: source.legal_middle_name.trim(),
    primary_holder_last_name: source.legal_last_name.trim(),
    tax_status: taxStatus,
    gender: genderCode[source.gender],
    primary_holder_dob_incorporation: source.date_of_birth,
    occupation_code: occupationCode,
    holding_nature: "SI",
    primary_holder_pan_exempt: "N",
    primary_holder_pan: source.pan.trim().toUpperCase(),
    client_type: "P",
    account_type_1: bankTypeCode[source.bank.account_type],
    account_no_1: source.bank.account_number.trim(),
    micr_no_1: source.bank.micr_code.trim(),
    ifsc_code_1: source.bank.ifsc_code.trim().toUpperCase(),
    default_bank_flag_1: "Y",
    cheque_name: source.bank.account_holder_name.trim(),
    div_pay_mode: source.nse_codes.div_pay_mode.trim(),
    address_1: source.address.line_1.trim(),
    address_2: source.address.line_2.trim(),
    address_3: source.address.line_3.trim(),
    city: source.address.city.trim(),
    state: stateCode,
    pincode: source.address.postal_code.trim(),
    country: source.nse_codes.country.trim(),
    email: source.email.trim(),
    communication_mode: communicationCode[source.communication_preference],
    indian_mobile_no: source.mobile.trim(),
    primary_holder_kyc_type: kycCode[source.kyc_method],
    primary_holder_ckyc_number: source.kyc_method === "ckyc"
      ? source.ckyc_number.trim()
      : "",
    paperless_flag: source.onboarding_mode === "paperless" ? "Z" : "P",
    mobile_declaration_flag: mobileDeclaration,
    email_declaration_flag: emailDeclaration,
    nomination_opt: "N",
  });
  const request: NseUccRequest = { reg_details: [record] };
  validateNseUccRequest(request);
  return request;
}

function issue(
  issues: NseUccValidationIssue[],
  field: string,
  code: string,
): void {
  issues.push({ field, code });
}

export function validateNseUccRequest(request: NseUccRequest): void {
  const issues: NseUccValidationIssue[] = [];
  assertIntegrationPayloadHasNoCredentials(request);
  if (!Array.isArray(request.reg_details) || request.reg_details.length !== 1) {
    throw new NseUccValidationError([{
      field: "reg_details",
      code: "exactly_one_record_required",
    }]);
  }
  const record = request.reg_details[0] as Record<string, unknown>;
  const expected = new Set<string>(NSE_UCC_FIELDS);
  for (const key of Object.keys(record)) {
    if (!expected.has(key)) issue(issues, key, "field_not_in_nnf_v1_9_7");
  }
  for (const field of NSE_UCC_FIELDS) {
    if (typeof record[field] !== "string") {
      issue(issues, field, "string_required");
    }
  }
  const value = (field: string): string =>
    typeof record[field] === "string" ? record[field] as string : "";
  for (const [field, maximum] of Object.entries(requiredLimits)) {
    if (value(field).length === 0) issue(issues, field, "required");
    if (value(field).length > maximum) {
      issue(issues, field, "maximum_length_exceeded");
    }
  }
  for (const [field, maximum] of Object.entries(optionalLimits)) {
    if (value(field).length > maximum) {
      issue(issues, field, "maximum_length_exceeded");
    }
  }
  if (!/^[A-Z0-9]{1,10}$/.test(value("client_code"))) {
    issue(issues, "client_code", "invalid_format");
  }
  if (!/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(value("primary_holder_pan"))) {
    issue(issues, "primary_holder_pan", "valid_non_exempt_pan_required");
  } else if (
    value("tax_status") === "01" && value("primary_holder_pan")[3] !== "P"
  ) {
    issue(
      issues,
      "primary_holder_pan",
      "individual_pan_category_mismatch",
    );
  }
  if (value("tax_status") !== "01") {
    issue(
      issues,
      "tax_status",
      "first_slice_requires_individual_tax_status",
    );
  }
  if (!occupationCodes.has(value("occupation_code"))) {
    issue(issues, "occupation_code", "invalid_allowed_value");
  }
  if (value("primary_holder_pan_exempt") !== "N") {
    issue(
      issues,
      "primary_holder_pan_exempt",
      "first_slice_requires_non_exempt_pan",
    );
  }
  for (
    const field of [
      "primary_holder_exempt_category",
      "primary_holder_kra_exempt_ref_no",
    ]
  ) {
    if (value(field) !== "") {
      issue(issues, field, "must_be_blank_for_non_exempt_pan");
    }
  }
  if (parseIndianDate(value("primary_holder_dob_incorporation")) == null) {
    issue(issues, "primary_holder_dob_incorporation", "invalid_date_format");
  }
  if (!["M", "F", "O", "T"].includes(value("gender"))) {
    issue(issues, "gender", "invalid_allowed_value");
  }
  if (value("holding_nature") !== "SI") {
    issue(issues, "holding_nature", "first_slice_requires_single_holder");
  }
  if (value("client_type") !== "P") {
    issue(issues, "client_type", "first_slice_requires_physical");
  }
  for (const field of physicalOnlyBlankFields) {
    if (value(field) !== "") {
      issue(issues, field, "must_be_blank_for_physical");
    }
  }
  if (!["SB", "CB", "NE", "NO"].includes(value("account_type_1"))) {
    issue(issues, "account_type_1", "invalid_allowed_value");
  }
  if (!/^[A-Z0-9]{1,40}$/i.test(value("account_no_1"))) {
    issue(issues, "account_no_1", "invalid_format");
  }
  if (value("micr_no_1") !== "" && !/^[0-9]{9}$/.test(value("micr_no_1"))) {
    issue(issues, "micr_no_1", "invalid_format");
  }
  if (!/^[A-Z]{4}0[A-Z0-9]{6}$/.test(value("ifsc_code_1"))) {
    issue(issues, "ifsc_code_1", "invalid_format");
  }
  if (value("default_bank_flag_1") !== "Y") {
    issue(issues, "default_bank_flag_1", "invalid_allowed_value");
  }
  if (!["01", "02", "03", "04", "05"].includes(value("div_pay_mode"))) {
    issue(issues, "div_pay_mode", "invalid_allowed_value");
  }
  if (!/^[0-9]{6}$/.test(value("pincode"))) {
    issue(issues, "pincode", "invalid_format");
  }
  if (!(value("state") in NSE_UCC_STATE_MASTER)) {
    issue(issues, "state", "invalid_allowed_value");
  }
  // Country intentionally remains governed by the NNF/Postman API shape.
  // WebfileStructure's numeric country master conflicts with those examples.
  for (const field of residentOnlyBlankFields) {
    if (value(field) !== "") {
      issue(issues, field, "must_be_blank_for_resident_individual");
    }
  }
  if (!/^[0-9]{10}$/.test(value("indian_mobile_no"))) {
    issue(issues, "indian_mobile_no", "invalid_format");
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value("email"))) {
    issue(issues, "email", "invalid_format");
  }
  if (!["P", "E", "M"].includes(value("communication_mode"))) {
    issue(issues, "communication_mode", "invalid_allowed_value");
  }
  if (!["K", "C", "B", "E"].includes(value("primary_holder_kyc_type"))) {
    issue(issues, "primary_holder_kyc_type", "invalid_allowed_value");
  }
  if (
    value("primary_holder_kyc_type") === "C" &&
    !/^[A-Z0-9]{14}$/i.test(value("primary_holder_ckyc_number"))
  ) issue(issues, "primary_holder_ckyc_number", "required_for_ckyc");
  if (
    value("primary_holder_kyc_type") !== "C" &&
    value("primary_holder_ckyc_number") !== ""
  ) issue(issues, "primary_holder_ckyc_number", "only_for_ckyc");
  if (!["P", "Z"].includes(value("paperless_flag"))) {
    issue(issues, "paperless_flag", "invalid_allowed_value");
  }
  if (!declarationCodes.has(value("mobile_declaration_flag"))) {
    issue(issues, "mobile_declaration_flag", "invalid_allowed_value");
  }
  if (!declarationCodes.has(value("email_declaration_flag"))) {
    issue(issues, "email_declaration_flag", "invalid_allowed_value");
  }
  if (value("nomination_opt") !== "N") {
    issue(issues, "nomination_opt", "first_slice_requires_nomination_opt_out");
  }
  for (let bank = 2; bank <= 5; bank++) {
    for (
      const prefix of [
        "account_type",
        "account_no",
        "micr_no",
        "ifsc_code",
        "default_bank_flag",
      ]
    ) {
      if (value(prefix + "_" + bank) !== "") {
        issue(issues, prefix + "_" + bank, "first_slice_supports_one_bank");
      }
    }
  }
  for (const field of NSE_UCC_FIELDS) {
    if (
      (field.startsWith("second_holder_") ||
        field.startsWith("third_holder_") ||
        field.startsWith("guardian_") || field.startsWith("nominee_") ||
        field === "nominee_soa" || field === "nomination_authentication") &&
      value(field) !== ""
    ) {
      issue(issues, field, "must_be_blank_for_simple_fixture");
    }
  }
  if (issues.length > 0) throw new NseUccValidationError(issues);
}

export type ParsedNseUccResponse = {
  httpStatus: number;
  businessSuccess: boolean;
  clientCode: string | null;
  registrationReference: string | null;
  nativeStatusValue: string | null;
  nativeRemarkCategory: string;
};

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

export function parseNseUccResponse(
  rawResponse: string,
  httpStatus: number,
): ParsedNseUccResponse {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawResponse);
  } catch {
    throw new NseUccValidationError([{
      field: "$response",
      code: "invalid_json",
    }]);
  }
  if (
    parsed == null || typeof parsed !== "object" ||
    !Array.isArray((parsed as { reg_details?: unknown }).reg_details) ||
    (parsed as { reg_details: unknown[] }).reg_details.length !== 1
  ) {
    throw new NseUccValidationError([{
      field: "reg_details",
      code: "exactly_one_response_record_required",
    }]);
  }
  const record = (parsed as { reg_details: unknown[] }).reg_details[0];
  if (record == null || typeof record !== "object") {
    throw new NseUccValidationError([{
      field: "reg_details[0]",
      code: "response_object_required",
    }]);
  }
  const fields = record as Record<string, unknown>;
  const status = optionalString(fields.reg_status);
  const remark = optionalString(fields.reg_remark);
  return {
    httpStatus,
    businessSuccess: httpStatus >= 200 && httpStatus <= 299 &&
      status === "REG_SUCCESS",
    clientCode: optionalString(fields.client_code),
    registrationReference: optionalString(fields.reg_id),
    nativeStatusValue: status,
    nativeRemarkCategory: remark == null
      ? "none"
      : status === "REG_SUCCESS"
      ? "integration_success_remark"
      : "integration_validation_remark",
  };
}
