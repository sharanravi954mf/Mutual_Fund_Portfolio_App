export const NSE_CLIENT_MASTER_ENDPOINT =
  "/nsemfdesk/api/v2/reports/client_master_report";

export type NseUccVerificationPurpose =
  | "POST_REGISTRATION_VERIFICATION"
  | "AMBIGUOUS_WRITE_RECONCILIATION";

export type NseUccVerificationSource = {
  operation_id: string;
  target_operation_id: string;
  workspace_id: string;
  integration_account_id: string;
  correlation_id: string;
  verification_purpose: NseUccVerificationPurpose;
  intended_client_code: string;
  pan: string;
};

export type NseClientMasterRequest = {
  client_code: string;
  PAN: "";
  from_date: "";
  to_date: "";
};

export type NseClientMasterObservation = {
  nativeStatus: string | null;
  nativeRemarkCategory: string;
  exactIdentityMatch: boolean;
  recordCount: number;
};

export class NseUccVerificationError extends Error {
  readonly code: string;
  constructor(code: string) {
    super(code);
    this.name = "NseUccVerificationError";
    this.code = code;
  }
}

function requiredString(value: unknown, code: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new NseUccVerificationError(code);
  }
  return value.trim().toUpperCase();
}

export function buildNseClientMasterRequest(
  source: NseUccVerificationSource,
): NseClientMasterRequest {
  const clientCode = requiredString(
    source.intended_client_code,
    "verification_client_code_required",
  );
  const pan = requiredString(source.pan, "verification_pan_required");
  if (!/^[A-Z0-9]{1,10}$/.test(clientCode)) {
    throw new NseUccVerificationError("verification_client_code_invalid");
  }
  if (!/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(pan)) {
    throw new NseUccVerificationError("verification_pan_invalid");
  }
  return { client_code: clientCode, PAN: "", from_date: "", to_date: "" };
}

function recordString(
  record: Record<string, unknown>,
  ...names: string[]
): string | null {
  for (const name of names) {
    const value = record[name];
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim().toUpperCase();
    }
  }
  return null;
}

export function parseNseClientMasterResponse(
  rawBody: string,
  intendedClientCode: string,
  canonicalPan: string,
): NseClientMasterObservation {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    throw new NseUccVerificationError("client_master_response_not_json");
  }
  if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new NseUccVerificationError("client_master_response_invalid");
  }
  const object = parsed as Record<string, unknown>;
  const nativeStatus = typeof object.response_status === "string"
    ? object.response_status.trim()
    : null;
  const reportData = Array.isArray(object.report_data)
    ? object.report_data
    : [];
  const expectedCode = intendedClientCode.trim().toUpperCase();
  const expectedPan = canonicalPan.trim().toUpperCase();
  const exactIdentityMatch = reportData.some((entry) => {
    if (entry == null || typeof entry !== "object" || Array.isArray(entry)) {
      return false;
    }
    const record = entry as Record<string, unknown>;
    return recordString(record, "client_code") === expectedCode &&
      recordString(record, "primary_holder_pan", "primary_pan") === expectedPan;
  });
  return {
    nativeStatus,
    nativeRemarkCategory: exactIdentityMatch
      ? "ucc_match_confirmed"
      : "ucc_match_not_confirmed",
    exactIdentityMatch,
    recordCount: reportData.length,
  };
}
