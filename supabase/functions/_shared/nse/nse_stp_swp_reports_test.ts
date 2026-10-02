import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseStpSwpReportsRequest as build,
  parseNseStpSwpReportsResponse as parse,
  STP_SWP_REPORTS_ENDPOINTS,
} from "./nse_stp_swp_reports.ts";
import {
  B05_APIS,
  B05_ROWS,
  b05Envelope,
  b05Source,
} from "./nse_stp_swp_reports_fixtures.ts";
for (const api of B05_APIS) {
  const source = b05Source(api), row = B05_ROWS[api];
  const count = api === "SIP_AMC_PAUSE_REPORT"
    ? "response_data_total"
    : "report_data_total";
  Deno.test(`${api}: exact owned request serialization and native path`, () => {
    const expected = api === "STP_INST_DUE_REPORT"
      ? '{"stp_reg_id":"202501011000001"}'
      : api === "SIP_AMC_PAUSE_REPORT"
      ? '{"client_code":"SYNTHETIC1","modification_type":"PAUSE"}'
      : '{"client_code":"SYNTHETIC1"}';
    assertEquals(JSON.stringify(build(source)), expected);
    assertEquals(
      STP_SWP_REPORTS_ENDPOINTS[api],
      "/nsemfdesk/api/v2/reports/" +
        (api === "SIP_AMC_PAUSE_REPORT" ? "SIP_AMC_PAUSE" : api),
    );
  });
  Deno.test(`${api}: complete positive schema and bounded empty observation`, () => {
    for (const rows of [[row], []]) {
      assertEquals(parse(JSON.stringify(b05Envelope(api, rows)), source), {
        nativeStatus: "S",
        nativeRemarkCategory: rows.length
          ? "stp_swp_reports_report_received"
          : "stp_swp_reports_no_records",
        success: true,
        recordCount: rows.length,
      });
    }
  });
  Deno.test(`${api}: every documented field is required, string and closed`, () => {
    for (const key of Object.keys(row)) {
      for (const value of [undefined, null, 1, {}]) {
        const changed: Record<string, unknown> = { ...row, [key]: value };
        if (value === undefined) {
          delete changed[key];
        }
        assertEquals(
          parse(JSON.stringify(b05Envelope(api, [changed])), source).success,
          false,
        );
      }
    }
    assertEquals(
      parse(JSON.stringify(b05Envelope(api, [{ ...row, unknown: "" }])), source)
        .success,
      false,
    );
  });
  Deno.test(`${api}: exact duplicate and mixed/foreign report fails whole observation`, () => {
    for (
      const rows of [[row, row], [row, { ...row, client_code: "FOREIGN" }], [{
        ...row,
        client_code: "FOREIGN",
      }]]
    ) {
      assertEquals(
        parse(JSON.stringify(b05Envelope(api, rows)), source).success,
        false,
      );
    }
  });
  Deno.test(`${api}: unknown diagnostics never borrowed from other endpoints`, () => {
    for (
      const error_remark of [
        "No record(s) found.",
        "No record(s) found",
        "Success",
        " ",
        null,
        {},
        "PRIVATE",
      ]
    ) {
      for (const rows of [[], [row]]) {
        const result = parse(
          JSON.stringify({ ...b05Envelope(api, rows), error_remark }),
          source,
        );
        assertEquals(result.success, false);
        assertEquals(
          result.nativeRemarkCategory,
          "stp_swp_reports_unknown_diagnostic",
        );
      }
    }
  });
  Deno.test(`${api}: count field, count mismatch and envelope closed`, () => {
    const empty = b05Envelope(api, []);
    for (
      const n of [null, {}, [], true, -1, 1, 0.5, "0.0", "", "1e0", "10001"]
    ) {
      assertEquals(
        parse(JSON.stringify({ ...empty, [count]: n }), source).success,
        false,
      );
    }
    for (
      const mutation of [{ report_data: {} }, { response_status: "F" }, {
        unknown: "",
      }, {
        [
          count === "report_data_total"
            ? "response_data_total"
            : "report_data_total"
        ]: "0",
      }]
    ) {
      assertEquals(
        parse(JSON.stringify({ ...empty, ...mutation }), source).success,
        false,
      );
    }
    delete empty[count];
    assertEquals(parse(JSON.stringify(empty), source).success, false);
  });
  Deno.test(`${api}: arbitrary identifiers, endpoint URLs and broad selectors blocked`, () => {
    for (
      const field of [
        "client_code",
        "stp_reg_id",
        "swp_reg_id",
        "request_id",
        "registration_no",
        "member_unique_ids",
        "scheme_code",
        "amc_code",
        "url",
        "member_code",
      ]
    ) {
      assertThrows(() =>
        build({ ...source, request: { ...source.request, [field]: "FOREIGN" } })
      );
    }
    assertThrows(() => build({ ...source, request: {} }));
  });
  Deno.test(`${api}: date format/calendar/window rules are independent`, () => {
    const amc = api === "SIP_AMC_PAUSE_REPORT",
      due = api.includes("DUE"),
      sep = amc ? "/" : "-";
    const from = `02${sep}10${sep}2026`,
      to = (amc || due) ? `09${sep}10${sep}2026` : `02${sep}11${sep}2026`;
    build({
      ...source,
      request: { ...source.request, from_date: from, to_date: to },
    });
    for (
      const [f, t] of [[from, from], [to, from], ["31-02-2026", "01-03-2026"], [
        "2026-10-02",
        "2026-10-03",
      ], [from, (amc || due) ? `10${sep}10${sep}2026` : `03${sep}11${sep}2026`]]
    ) {
      assertThrows(() =>
        build({
          ...source,
          request: { ...source.request, from_date: f, to_date: t },
        })
      );
    }
    assertThrows(() =>
      build({ ...source, request: { ...source.request, from_date: from } })
    );
    if (due) {
      assertThrows(() =>
        build({
          ...source,
          request: {
            ...source.request,
            from_date: "01-10-2026",
            to_date: "02-10-2026",
          },
        })
      );
    }
    if (amc) {
      build({
        ...source,
        request: {
          ...source.request,
          from_date: "01/01/2025",
          to_date: "02/01/2025",
        },
      });
    }
  });
}
Deno.test("STP due has no UCC in response: only frozen owned registrations may select it", () => {
  const source = b05Source("STP_INST_DUE_REPORT");
  assertThrows(() =>
    build({
      ...source,
      selectors: { mode: "client", rows: [] },
      request: { client_code: "SYNTHETIC1" },
    })
  );
  for (const k of Object.keys(source.selectors.rows[0])) {
    assertEquals(
      parse(
        JSON.stringify(
          b05Envelope(source.api, [{
            ...B05_ROWS[source.api],
            [k]: "FOREIGN",
          }]),
        ),
        source,
      ).success,
      false,
    );
  }
  const rows = [B05_ROWS[source.api], {
    ...B05_ROWS[source.api],
    due_date: "02 JAN 2025",
  }];
  assertEquals(
    parse(JSON.stringify(b05Envelope(source.api, rows)), source).recordCount,
    2,
  );
});
Deno.test("AMC pause preserves distinct request IDs for the same registration; UNPAUSE disabled", () => {
  const s = b05Source("SIP_AMC_PAUSE_REPORT");
  assertEquals(
    parse(
      JSON.stringify(
        b05Envelope(s.api, [B05_ROWS[s.api], {
          ...B05_ROWS[s.api],
          request_id: "557",
        }]),
      ),
      s,
    ).recordCount,
    2,
  );
  for (const modification_type of ["UNPAUSE", "", "PAUSE ", "pause"]) {
    assertThrows(() =>
      build({ ...s, request: { ...s.request, modification_type } })
    );
  }
  const e = b05Envelope(s.api);
  delete e.error_remark;
  assertEquals(parse(JSON.stringify(e), s).success, false);
});
for (const api of ["STP_REG_REPORT", "SWP_REG_REPORT"] as const) {
  Deno.test(`${api}: C029/C030 member precedence and frozen business correlation`, () => {
    const row = B05_ROWS[api];
    const keys = api === "STP_REG_REPORT"
      ? [
        "stp_registration_no",
        "stp_registration_date",
        "member_unique_id",
        "member_code",
        "from_nse_scheme_code",
        "to_nse_scheme_code",
        "frequency_type",
        "stp_start_date",
        "stp_end_date",
        "transfer_amount",
        "transfer_units",
      ]
      : [
        "swp_registration_no",
        "swp_registration_date",
        "member_unique_id",
        "member_code",
        "nse_scheme_code",
        "frequency_type",
        "swp_start_date",
        "swp_end_date",
        "withdrawl_amount",
        "withdrawal_units",
      ];
    const source = {
      ...b05Source(api),
      selectors: {
        mode: "member" as const,
        rows: [Object.fromEntries(keys.map((k) => [k, row[k]]))],
      },
      request: {
        member_unique_ids: "SYNTHETIC_REF_1",
        from_date: "01-01-2025",
        to_date: "01-02-2025",
      },
    };
    assertEquals(build(source), source.request);
    assertEquals(parse(JSON.stringify(b05Envelope(api)), source).success, true);
    for (const k of keys) {
      assertEquals(
        parse(
          JSON.stringify(b05Envelope(api, [{ ...row, [k]: "FOREIGN" }])),
          source,
        ).success,
        false,
      );
    }
    assertThrows(() =>
      build({ ...source, request: { member_unique_ids: "SYNTHETIC_REF_1" } })
    );
    assertThrows(() =>
      build({
        ...source,
        request: { ...source.request, client_code: "SYNTHETIC1" },
      })
    );
  });
}
