import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseSipXsipReportsRequest as build,
  nseReportToday,
  parseNseSipXsipReportsResponse as parse,
  type SipXsipReportsApi,
  type SipXsipReportsSource,
} from "./nse_sip_xsip_reports.ts";
// Synthetic fixtures preserve each sample's independent spellings and types.
export const reportFixtures: Record<SipXsipReportsApi, Record<string, string>> =
  {
    "SIP_REG_REPORT": {
      "status": "NATIVE_UNCHARACTERIZED",
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "pg_bank_ref_no": "PRIVATE_REFERENCE",
      "sip_reg_number": "202501011000001",
      "sip_reg_date": "01 JAN 2025",
      "amc_name": "SYNTHETIC_SCHEME",
      "rta_scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "frequency_type": "MONTHLY",
      "start_date": "01 JAN 2025",
      "end_date": "01 JAN 2025",
      "installments_amount": "1000",
      "entry_by": " ",
      "dpc_flag": " ",
      "dp_trans": " ",
      "first_order_today": " ",
      "sub_broker_code": " ",
      "euin": " ",
      "euin_declaration": " ",
      "folio_number": " ",
      "remarks": " ",
      "sub_broker_arn_code": " ",
      "no_of_installments": "1000",
      "exchange_remark": " ",
      "health_declaration_flag": " ",
      "nominee_dob": " ",
      "disclaimer_flag": " ",
      "internal_ref_no": " ",
      "primary_holder_email": " ",
      "primary_holder_mobile": " ",
      "second_holder_email": " ",
      "second_holder_mobile": " ",
      "third_holder_email": " ",
      "third_holder_mobile": " ",
      "member_unique_id": "SYNTHETIC_REF_1",
    },
    "SIP_CAN_REPORT": {
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "internal_ref_num": "PRIVATE_REFERENCE",
      "sip_registration_no": "202501011000001",
      "sip_registration_date": "01/01/2025 12:00:00 AM",
      "sip_cancellation_date": "01/01/2025 12:00:00 AM",
      "amc_name": "SYNTHETIC_SCHEME",
      "scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "frequency_type": "MONTHLY",
      "start_date": "01/01/2025 12:00:00 AM",
      "end_date": "01/01/2025 12:00:00 AM",
      "next_due_date": "01/01/2025 12:00:00 AM",
      "no_of_installments_paid": "1000",
      "installments_amt": "1000",
      "total_installment_amt_paid": "1000",
      "cancelled_by": " ",
      "sip_status": "NATIVE_UNCHARACTERIZED",
      "remark": " ",
    },
    "SIP_INST_DUE_REPORT": {
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "internal_ref_no": " ",
      "sip_reg_number": "202501011000001",
      "reg_date": "01 JAN 2025",
      "amc_name": "SYNTHETIC_SCHEME",
      "scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "frequency_type": "MONTHLY",
      "installment_amt": "1000",
      "due_date": "02 OCT 2026",
      "prev_paid_date": "01 JAN 2025",
      "no_of_installments_paid": "1000",
      "total_installment_amt_paid": "1000",
      "entry_by": " ",
      "dp_trans": " ",
      "first_order_today": " ",
    },
    "SIP_TOPUP_REPORT": {
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "reg_no": "202501011000001",
      "scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "sip_xsip_amount": "1000",
      "start_date": "01-Jan-2025",
      "end_date": "01-Jan-2025",
      "top_up_amount": "1000",
      "date_of_activation": "01-Jan-2025",
      "entry_by": " ",
      "principle_sip_reg_no": "202412011000001",
      "principle_sip_internal_ref_no": "PRIVATE_REFERENCE",
      "last_child_sip_reg_no": "202501011000002",
      "top_up_frequency": "MONTHLY",
      "top_up_status": "NATIVE_UNCHARACTERIZED",
    },
    "STEPUP_REG_REPORT": {
      "status": "NATIVE_UNCHARACTERIZED",
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "sip_xsip_regn_number": "202501011000001",
      "sip_xsip_regn_date": "01 JAN 2025",
      "sip_xsip_type": "SIP",
      "amc_name": "SYNTHETIC_SCHEME",
      "rta_scheme_code": "SYNTHETIC_SCHEME",
      "scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "frequency_type": "MONTHLY",
      "start_date": "01 JAN 2025",
      "end_date": "01 JAN 2025",
      "stepup_start__effective_date": "01 JAN 2025",
      "stepup_enddate": "01 JAN 2025",
      "stepup_frequency": "MONTHLY",
      "stepup_amount": "1000",
      "entry_by": " ",
    },
    "XSIP_REG_REPORT": {
      "status": "NATIVE_UNCHARACTERIZED",
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "pg_bank_ref_no": "PRIVATE_REFERENCE",
      "xsip_registration_no": "202501011000001",
      "xsip_registration_date": "01 JAN 2025",
      "amc_name": "SYNTHETIC_SCHEME",
      "rta_scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "frequency_type": "MONTHLY",
      "start_date": "01 JAN 2025",
      "end_date": "01 JAN 2025",
      "installments_amount": "1000",
      "brokerage": "1000",
      "entry_by": " ",
      "nse_mandate_id": "01 JAN 2025",
      "dpc_flag": " ",
      "dp_trans": " ",
      "sub_broker": " ",
      "euin_no": " ",
      "euin_declaration": " ",
      "first_order_today": " ",
      "folio_number": " ",
      "remarks": " ",
      "sub_broker_arn": " ",
      "no_of_installments": "1000",
      "exchange_remark": " ",
      "health_declaration_flag": " ",
      "nominee_dob": " ",
      "disclaimer_flag": " ",
      "internal_ref_no": " ",
      "primary_holder_email": " ",
      "primary_holder_mobile": " ",
      "second_holder_email": " ",
      "second_holder_mobile": " ",
      "third_holder_email": " ",
      "third_holder_mobile": " ",
      "member_unique_id": "SYNTHETIC_REF_1",
    },
    "XSIP_CAN_REPORT": {
      "status": "NATIVE_UNCHARACTERIZED",
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "internal_ref_num": "PRIVATE_REFERENCE",
      "xsip_registration_no": "202501011000001",
      "xsip_registration_date": "01/01/2025",
      "xsip_cancellation_date": "01/01/2025",
      "amc_name": "SYNTHETIC_SCHEME",
      "scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "frequency_type": "MONTHLY",
      "start_date": "01/01/2025",
      "end_date": "01/01/2025",
      "next_due_date": "01 JAN 2025",
      "no_of_installments_paid": "1000",
      "installments_amt": "1000",
      "brokerage": "1000",
      "total_installment_amt_paid": "1000",
      "cancelled_by": " ",
      "nse_mandate_id": "01 JAN 2025",
      "remark": " ",
    },
    "XSIP_INST_DUE_REPORT": {
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "internal_ref_no": " ",
      "sip_reg_number": "202501011000001",
      "reg_date": "01 JAN 2025",
      "amc_name": "SYNTHETIC_SCHEME",
      "scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "frequency_type": "MONTHLY",
      "installment_amt": "1000",
      "due_date": "02 OCT 2026",
      "prev_paid_date": "01 JAN 2025",
      "no_of_installments_paid": "1000",
      "total_installment_amt_paid": "1000",
      "entry_by": " ",
      "mandate_id": "01 JAN 2025",
      "dp_trans": " ",
      "first_order_today": " ",
    },
    "XSIP_TOPUP_REPORT": {
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "client_name": "SYNTHETIC HOLDER",
      "reg_no": "202501011000001",
      "scheme_code": "SYNTHETIC_SCHEME",
      "scheme_name": "SYNTHETIC_SCHEME",
      "sip_xsip_amount": "1000",
      "start_date": "01-Jan-2025",
      "end_date": "01-Jan-2025",
      "top_up_amount": "1000",
      "date_of_activation": "01-Jan-2025",
      "entry_by": " ",
      "principle_sip_reg_no": "202412011000001",
      "principle_sip_internal_ref_no": "PRIVATE_REFERENCE",
      "last_child_sip_reg_no": "202501011000002",
      "top_up_frequency": "MONTHLY",
      "top_up_status": "NATIVE_UNCHARACTERIZED",
    },
  };
export const apis = Object.keys(reportFixtures) as SipXsipReportsApi[];
export function source(api: SipXsipReportsApi): SipXsipReportsSource {
  return {
    operation_id: "10000000-0000-4000-8000-000000000002",
    workspace_id: "10000000-0000-4000-8000-000000000004",
    integration_account_id: "10000000-0000-4000-8000-000000000004",
    api,
    client_code: "SYNTHETIC1",
    pan: "AAAAA0000A",
    today: "2026-10-01",
    selectors: { mode: "client", rows: [] },
    request: { client_code: "SYNTHETIC1" },
  };
}
export function report(
  api: SipXsipReportsApi,
  rows: unknown[] = [reportFixtures[api]],
) {
  return {
    response_status: "S",
    report_data_total: String(rows.length),
    report_data: rows,
  };
}
function memberSource(
  api: "SIP_REG_REPORT" | "XSIP_REG_REPORT",
  rows = [reportFixtures[api]],
): SipXsipReportsSource {
  const s = source(api);
  const keys = api === "SIP_REG_REPORT"
    ? ["sip_reg_number", "sip_reg_date"]
    : ["xsip_registration_no", "xsip_registration_date"];
  keys.push(
    "member_unique_id",
    "member_code",
    "rta_scheme_code",
    "frequency_type",
    "start_date",
    "end_date",
    "installments_amount",
  );
  s.selectors = {
    mode: "member",
    rows: rows.map((r) => Object.fromEntries(keys.map((k) => [k, r[k]]))),
  };
  s.request = {
    member_unique_ids: rows.map((r) => r.member_unique_id).join(","),
    from_date: "01-01-2025",
    to_date: "01-02-2025",
  };
  return s;
}
for (const api of apis) {
  Deno.test(`${api}: only trusted UCC selector, never broad or raw stronger precedence`, () => {
    const s = source(api);
    assertEquals(build(s), { client_code: "SYNTHETIC1" });
    for (
      const key of [
        "client_code",
        "sip_reg_id",
        "xsip_reg_id",
        "parent_sip_reg_id",
        "parent_xsip_reg_id",
        "member_unique_ids",
        "unknown",
      ]
    ) {
      assertThrows(() =>
        build({ ...s, request: { ...s.request, [key]: "FOREIGN" } })
      );
    }
    for (const client_code of ["", "FOREIGN,OWNED", "A B", "A".repeat(21)]) {
      assertThrows(() =>
        build({ ...s, client_code, request: { client_code } })
      );
    }
    assertThrows(() => build({ ...s, request: {} }));
    assertThrows(() =>
      build({ ...s, selectors: { mode: "member", rows: [] } })
    );
  });
  Deno.test(`${api}: independent optional date window, real dates and strict increasing range`, () => {
    const s = source(api),
      due = api === "SIP_INST_DUE_REPORT" || api === "XSIP_INST_DUE_REPORT";
    const valid = {
      from_date: "01-10-2026",
      to_date: due ? "08-10-2026" : "01-11-2026",
    };
    assertEquals(build({ ...s, request: { ...s.request, ...valid } }), {
      ...s.request,
      ...valid,
    });
    const bad = [
      { from_date: "01-10-2026", to_date: due ? "09-10-2026" : "02-11-2026" },
      { from_date: "01-10-2026", to_date: "01-10-2026" },
      { from_date: "02-10-2026", to_date: "01-10-2026" },
      { from_date: "31-02-2025", to_date: "01-03-2025" },
      { from_date: "2026-10-01", to_date: "02-10-2026" },
      { from_date: "01-01-0000", to_date: "02-01-0000" },
      { from_date: "" },
      { to_date: "02-10-2026" },
      { from_date: null, to_date: "02-10-2026" },
    ];
    for (const dates of bad) {
      assertThrows(() =>
        build({
          ...s,
          request: { ...s.request, ...dates } as Record<string, string>,
        })
      );
    }
    const past = {
      ...s,
      request: { ...s.request, from_date: "30-09-2026", to_date: "01-10-2026" },
    };
    if (due) assertThrows(() => build(past));
    else assertEquals(build(past), past.request);
  });
  Deno.test(`${api}: exact native schema, no state projection, empty observations`, () => {
    assertEquals(parse(JSON.stringify(report(api)), source(api)), {
      nativeStatus: "S",
      nativeRemarkCategory: "sip_xsip_reports_report_received",
      success: true,
      recordCount: 1,
    });
    assertEquals(parse(JSON.stringify(report(api, [])), source(api)), {
      nativeStatus: "S",
      nativeRemarkCategory: "sip_xsip_reports_no_records",
      success: true,
      recordCount: 0,
    });
    for (const key of Object.keys(reportFixtures[api])) {
      const row = { ...reportFixtures[api] };
      delete row[key];
      assertEquals(
        parse(JSON.stringify(report(api, [row])), source(api)).success,
        false,
        `missing ${key}`,
      );
      assertEquals(
        parse(
          JSON.stringify(
            report(api, [{ ...reportFixtures[api], [key]: null }]),
          ),
          source(api),
        ).success,
        false,
        `null ${key}`,
      );
    }
  });
  Deno.test(`${api}: foreign, mixed, duplicate, unknown schemas and diagnostics fail closed`, () => {
    const s = source(api), row = reportFixtures[api], good = report(api);
    for (
      const body of [
        null,
        [],
        {},
        { ...good, response_status: "F" },
        { ...good, response_status: "UNKNOWN" },
        { ...good, report_data_total: null },
        { ...good, report_data_total: "1.0" },
        { ...good, report_data_total: 2 },
        { ...good, report_data_total: -1 },
        { ...good, report_data_total: 10001 },
        { ...good, report_data: {} },
        { ...good, error_remark: "" },
        { ...good, error_remark: "No record(s) found." },
        { ...good, error_remark: "SUCCESS" },
        { ...good, unknown: "" },
        report(api, [{ ...row, unknown: "" }]),
        report(api, [{ ...row, client_code: "FOREIGN" }]),
        report(api, [row, { ...row, client_code: "FOREIGN" }]),
        report(api, [row, { ...row, member_code: "9999" }]),
        report(api, [row, row]),
      ]
    ) {
      assertEquals(parse(JSON.stringify(body), s).success, false);
    }
    for (const raw of ["PRIVATE", "{", "\ufeff{}"]) {
      assertEquals(parse(raw, s).success, false);
    }
  });
}
Deno.test("B04 India day has deterministic midnight boundary", () => {
  assertEquals(nseReportToday(new Date("2026-09-30T18:29:59Z")), "2026-09-30");
  assertEquals(nseReportToday(new Date("2026-09-30T18:30:00Z")), "2026-10-01");
});
for (const api of ["SIP_REG_REPORT", "XSIP_REG_REPORT"] as const) {
  Deno.test(`${api}: current member filter uses owned lineage, no ignored selector overrides`, () => {
    const s = memberSource(api);
    assertEquals(build(s), s.request);
    assertEquals(parse(JSON.stringify(report(api)), s).success, true);
    for (
      const key of [
        "client_code",
        "sip_reg_id",
        "xsip_reg_id",
        "parent_sip_reg_id",
        "parent_xsip_reg_id",
      ]
    ) {
      assertThrows(() =>
        build({ ...s, request: { ...s.request, [key]: "FOREIGN" } })
      );
    }
    for (const key of ["from_date", "to_date"]) {
      const request = { ...s.request };
      delete request[key];
      assertThrows(() => build({ ...s, request }));
    }
    for (const key of Object.keys(s.selectors.rows[0])) {
      assertEquals(
        parse(
          JSON.stringify(
            report(api, [{ ...reportFixtures[api], [key]: "DIFFERENT" }]),
          ),
          s,
        ).success,
        false,
      );
    }
    assertThrows(() =>
      build({ ...s, request: { ...s.request, member_unique_ids: "FOREIGN" } })
    );
    assertThrows(() =>
      build({
        ...s,
        selectors: {
          mode: "member",
          rows: [...s.selectors.rows, ...s.selectors.rows],
        },
      })
    );
    assertThrows(() =>
      build({
        ...s,
        selectors: {
          mode: "member",
          rows: Array(51).fill(s.selectors.rows[0]),
        },
      })
    );
    const id = api === "SIP_REG_REPORT"
      ? "sip_reg_number"
      : "xsip_registration_no";
    const second = {
      ...reportFixtures[api],
      [id]: "202501011000002",
      member_unique_id: "SECOND",
    };
    const multi = memberSource(api, [reportFixtures[api], second]);
    assertEquals(
      parse(JSON.stringify(report(api)), multi).nativeRemarkCategory,
      "sip_xsip_reports_incomplete_selection",
    );
    assertEquals(
      parse(JSON.stringify(report(api, [second, reportFixtures[api]])), multi)
        .success,
      true,
    );
    assertEquals(parse(JSON.stringify(report(api, [])), multi).success, true);
  });
}
Deno.test("C041 corrupted count key is never a JSON alias", () => {
  const good = report("SIP_REG_REPORT");
  assertEquals(
    parse(
      JSON.stringify({
        response_status: "S",
        report_data: good.report_data,
        "reportXSIP Registration Report _data_total": "1",
      }),
      source("SIP_REG_REPORT"),
    ).success,
    false,
  );
});
Deno.test("B04 cross-schema field aliases and due/stepup multiplicity stay endpoint-specific", () => {
  const xsip = reportFixtures.XSIP_INST_DUE_REPORT;
  assertEquals(
    parse(
      JSON.stringify(
        report("XSIP_INST_DUE_REPORT", [{
          ...xsip,
          xsip_registration_no: xsip.sip_reg_number,
        }]),
      ),
      source("XSIP_INST_DUE_REPORT"),
    ).success,
    false,
  );
  const step = reportFixtures.STEPUP_REG_REPORT;
  assertEquals(
    parse(
      JSON.stringify(
        report("STEPUP_REG_REPORT", [{
          ...step,
          stepup_start_effective_date: step.stepup_start__effective_date,
        }]),
      ),
      source("STEPUP_REG_REPORT"),
    ).success,
    false,
  );
  for (const api of ["SIP_INST_DUE_REPORT", "XSIP_INST_DUE_REPORT"] as const) {
    assertEquals(
      parse(
        JSON.stringify(
          report(api, [reportFixtures[api], {
            ...reportFixtures[api],
            due_date: "03 OCT 2026",
          }]),
        ),
        source(api),
      ).success,
      true,
    );
  }
});
