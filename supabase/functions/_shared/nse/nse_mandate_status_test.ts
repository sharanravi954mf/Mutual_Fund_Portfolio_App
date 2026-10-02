import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseMandateStatusRequest,
  type MandateStatusSource,
  parseNseMandateStatusResponse,
} from "./nse_mandate_status.ts";
const source: MandateStatusSource = {
  operation_id: "op",
  workspace_id: "w",
  integration_account_id: "a",
  api: "MANDATE_STATUS",
  client_code: "OWNED",
  pan: "AAAAA0000A",
  bank_account_number: "PRIVATE",
  request: { client_code: "OWNED" },
};
const row = {
  mandateId: "2024012510001",
  clientCode: "OWNED",
  memberCode: "70790",
  memberMandateId: "01234567890123456789",
  bankAccountNumber: "PRIVATE",
  status: "APPROVED",
  dateOfUpload: " ",
  remarks: "PRIVATE",
};
const envelope = {
  response_status: "S",
  report_data_total: "1",
  report_data: [row],
  error_remark: "",
};
const parse = (e: unknown, s = source) =>
  parseNseMandateStatusResponse(JSON.stringify(e), s);
Deno.test("B07 exact case, owned selector and no arbitrary filters", () => {
  assertEquals(buildNseMandateStatusRequest(source), { client_code: "OWNED" });
  const request = { memberMandateIds: row.memberMandateId };
  assertEquals(buildNseMandateStatusRequest({ ...source, request }), request);
  for (
    const r of [
      { membermandateids: row.memberMandateId },
      { member_mandate_ids: row.memberMandateId },
      { mandate_id: "123" },
      { client_code: "OTHER" },
      { from_date: "2024-01-01", to_date: "2024-01-02" },
      { ...request, client_code: "OWNED" },
      { memberMandateIds: "a,b" },
      { url: "https://bad.invalid" },
    ]
  ) {
    assertThrows(() =>
      buildNseMandateStatusRequest({ ...source, request: r as never })
    );
  }
});
Deno.test("B07 unique match proves existence only; no raw identifiers or diagnostics", () => {
  assertEquals(parse(envelope), {
    nativeStatus: "S",
    nativeRemarkCategory: "mandate_status_unique_match_received",
    success: true,
    recordCount: 1,
  });
  assertEquals(JSON.stringify(parse(envelope)).includes("PRIVATE"), false);
  for (const status of ["APPROVED", "UNRECOGNIZED_FUTURE_STATE"]) {
    assertEquals(
      parse({ ...envelope, report_data: [{ ...row, status }] }).success,
      true,
    );
  }
});
Deno.test("B07 missing, multiple, duplicate and foreign matches never reconcile", () => {
  for (
    const report_data of [[], [row, row], [row, {
      ...row,
      mandateId: "different",
    }], [{ ...row, clientCode: "OTHER" }]]
  ) {
    assertEquals(
      parse({ ...envelope, report_data, report_data_total: report_data.length })
        .success,
      false,
    );
  }
  const s = { ...source, request: { memberMandateIds: row.memberMandateId } };
  assertEquals(parse(envelope, s).success, true);
  assertEquals(
    parse({
      ...envelope,
      report_data: [{ ...row, bankAccountNumber: "OTHER" }],
    }, s).success,
    false,
  );
  assertEquals(
    parse({ ...envelope, report_data: [{ ...row, mandateId: " " }] }, s)
      .success,
    false,
  );
  assertEquals(
    parse({
      ...envelope,
      report_data: [{ ...row, memberMandateId: "DIFFERENT" }],
    }, s).success,
    false,
  );
});
Deno.test("B07 envelope, casing, malformed values and status fail closed", () => {
  for (
    const e of [
      null,
      [],
      {},
      { ...envelope, response_status: "s" },
      { ...envelope, response_status: "F" },
      { ...envelope, error_remark: "PRIVATE" },
      { ...envelope, report_data_total: "1.0" },
      { ...envelope, report_data_total: 2 },
      { ...envelope, report_data: [{ ...row, mandateId: "" }] },
      { ...envelope, report_data: [{ ...row, status: 42 }] },
      { ...envelope, extra: "\u0000" },
      { ...envelope, extra: "\ud800" },
    ]
  ) assertEquals(parse(e).success, false);
  assertEquals(
    parseNseMandateStatusResponse(
      '{"response_status":"S","extra":1e999}',
      source,
    ).nativeStatus,
    null,
  );
  assertEquals(
    parseNseMandateStatusResponse("not json", source).success,
    false,
  );
});
