import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseSettlementRedemptionRequest as build,
  parseNseSettlementRedemptionResponse as parse,
  type SettlementRedemptionSource,
} from "./nse_settlement_redemption.ts";
const fixtures = [
  {
    "api": "REDEMPTION_PAYOUT",
    "source": {
      "operation_id": "10000000-0000-4000-8000-000000000002",
      "workspace_id": "10000000-0000-4000-8000-000000000004",
      "integration_account_id": "10000000-0000-4000-8000-000000000004",
      "api": "REDEMPTION_PAYOUT",
      "client_code": "SYNTHETIC1",
      "pan": "AAAAA0000A",
      "selectors": {
        "mode": "order",
        "rows": [
          {
            "order_id": "451480000468",
            "member_unique_id": "SYNTHETICREF",
            "member_id": "05418",
            "scheme_code": "TEST-GR",
            "isin": "INF000000001",
            "transaction_type": "R",
            "order_date": "27/05/2025",
            "settlement_id": "2025105",
            "settlement_type": "T2",
            "folio_no": "SYNTHETIC/FOLIO",
          },
        ],
      },
      "request": {
        "from_date": "27-05-2025",
        "to_date": "28-05-2025",
        "report_type": "Order Date",
        "order_id": "451480000468",
      },
    },
    "row": {
      "order_id": "451480000468",
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "member_unique_id": "SYNTHETICREF",
      "scheme_code": "TEST-GR",
      "isin": "INF000000001",
      "transaction_type": "R",
      "order_date": "27 MAY 2025",
      "settlement_id": "2025105",
      "settlement_type": "T2",
      "rta_transaction_no": "RTA001",
      "funds_payout_status": "NATIVE_UNCHARACTERIZED",
      "allotted_amount": "1000.00",
      "first_applicant_pan": "AAAAA0000A",
      "rta_scheme_code": "TEST",
      "funds_payout_date": "28 MAY 2025",
      "funds_transfer_date": " ",
    },
    "filters": {
      "from_date": "27-05-2025",
      "to_date": "28-05-2025",
      "report_type": "Order Date",
    },
  },
  {
    "api": "REDEMPTION_PAYOUT_NON_DEMAT",
    "source": {
      "operation_id": "10000000-0000-4000-8000-000000000002",
      "workspace_id": "10000000-0000-4000-8000-000000000004",
      "integration_account_id": "10000000-0000-4000-8000-000000000004",
      "api": "REDEMPTION_PAYOUT_NON_DEMAT",
      "client_code": "SYNTHETIC1",
      "pan": "AAAAA0000A",
      "selectors": {
        "mode": "order",
        "rows": [
          {
            "order_id": "451480000468",
            "member_unique_id": "SYNTHETICREF",
            "member_id": "05418",
            "scheme_code": "TEST-GR",
            "isin": "INF000000001",
            "transaction_type": "R",
            "order_date": "27/05/2025",
            "settlement_id": "2025105",
            "settlement_type": "T2",
            "folio_no": "SYNTHETIC/FOLIO",
          },
        ],
      },
      "request": {
        "from_date": "27-05-2025",
        "to_date": "28-05-2025",
        "report_type": "Order Date",
        "order_id": "451480000468",
      },
    },
    "row": {
      "order_id": "451480000468",
      "member_code": "05418",
      "client_code": "SYNTHETIC1",
      "member_unique_id": "SYNTHETICREF",
      "scheme_code": "TEST-GR",
      "isin": "INF000000001",
      "transaction_type": "R",
      "order_date": "27 MAY 2025",
      "settlement_id": "2025105",
      "settlement_type": "T2",
      "rta_transaction_no": "RTA001",
      "funds_payout_status": "NATIVE_UNCHARACTERIZED",
      "allotted_amount": "1000.00",
      "first_applicant_pan": "AAAAA0000A",
      "product_code": "TEST",
      "folio_number": "SYNTHETIC/FOLIO",
      "payout_desc": "PRIVATE",
      "mailed_date": "05/28/2025 12:00:00 AM",
      "funds_payout_date": "05/28/2025 12:00:00 AM",
      "despatch_status": " ",
      "instrm_no": " ",
      "instrm_bank": "PRIVATE",
      "payee_acno": "PRIVATE",
    },
    "filters": {
      "from_date": "27-05-2025",
      "to_date": "28-05-2025",
      "report_type": "Order Date",
    },
  },
  {
    "api": "REDEMPTION_STATEMENT",
    "source": {
      "operation_id": "10000000-0000-4000-8000-000000000002",
      "workspace_id": "10000000-0000-4000-8000-000000000004",
      "integration_account_id": "10000000-0000-4000-8000-000000000004",
      "api": "REDEMPTION_STATEMENT",
      "client_code": "SYNTHETIC1",
      "pan": "AAAAA0000A",
      "selectors": {
        "mode": "order",
        "rows": [
          {
            "order_id": "451480000468",
            "member_unique_id": "SYNTHETICREF",
            "member_id": "05418",
            "scheme_code": "TEST-GR",
            "isin": "INF000000001",
            "transaction_type": "R",
            "order_date": "27/05/2025",
            "settlement_id": "2025105",
            "settlement_type": "T2",
            "folio_no": "SYNTHETIC/FOLIO",
          },
        ],
      },
      "request": {
        "from_date": "27-05-2025",
        "to_date": "28-05-2025",
        "order_ids": "451480000468",
      },
    },
    "row": {
      "orderno": "451480000468",
      "member_unique_id": "SYNTHETICREF",
      "clientcode": "SYNTHETIC1",
      "schemecode": "TEST-GR",
      "isin": "INF000000001",
      "orderdate": "27-05-2025",
      "reportdate": "28-05-2025",
      "settlementid": "2025105",
      "settlementype": "T2",
      "rtatransactionno": "RTA001",
      "ordertype": "NRM",
      "ordersubtype": "NRM",
      "validflag": "NATIVE_UNCHARACTERIZED",
      "allottednav": "10",
      "allottedqty": "100",
      "dptrans": "N",
      "membercode": "05418",
      "allottedamt": "1000",
    },
    "filters": {
      "from_date": "27-05-2025",
      "to_date": "28-05-2025",
    },
  },
  {
    "api": "ALLOTMENT_STATEMENT",
    "source": {
      "operation_id": "10000000-0000-4000-8000-000000000002",
      "workspace_id": "10000000-0000-4000-8000-000000000004",
      "integration_account_id": "10000000-0000-4000-8000-000000000004",
      "api": "ALLOTMENT_STATEMENT",
      "client_code": "SYNTHETIC1",
      "pan": "AAAAA0000A",
      "selectors": {
        "mode": "order",
        "rows": [
          {
            "order_id": "451480000468",
            "member_unique_id": "SYNTHETICREF",
            "member_id": "05418",
            "scheme_code": "TEST-GR",
            "isin": "INF000000001",
            "transaction_type": "P",
            "order_date": "27/05/2025",
            "settlement_id": "2025105",
            "settlement_type": "T2",
            "folio_no": "SYNTHETIC/FOLIO",
          },
        ],
      },
      "request": {
        "from_date": "27-05-2025",
        "to_date": "28-05-2025",
        "date_type": "ORD_DATE",
        "order_ids": "451480000468",
      },
    },
    "row": {
      "orderno": "451480000468",
      "member_unique_id": "SYNTHETICREF",
      "clientcode": "SYNTHETIC1",
      "schemecode": "TEST-GR",
      "isin": "INF000000001",
      "orderdate": "2025-05-27",
      "reportdate": "2025-05-28",
      "settlementid": "2025105",
      "settlementype": "T2",
      "rtatransactionno": "RTA001",
      "ordertype": "NRM",
      "ordersubtype": "NRM",
      "validflag": "NATIVE_UNCHARACTERIZED",
      "allottednav": "10",
      "allottedqty": "100",
      "dptrans": "N",
      "memberid": "05418",
      "allotmentamt": "1000",
      "pgbankrefno": "PRIVATE",
    },
    "filters": {
      "from_date": "27-05-2025",
      "to_date": "28-05-2025",
      "date_type": "ORD_DATE",
    },
  },
] as unknown as {
  api: string;
  source: SettlementRedemptionSource;
  row: Record<string, string>;
  filters: Record<string, string>;
}[];
function body(rows: unknown[], extra: Record<string, unknown> = {}) {
  return JSON.stringify({
    response_status: "S",
    report_data_total: rows.length,
    report_data: rows,
    error_remark: "",
    ...extra,
  });
}
for (const { api, source: s, row } of fixtures) {
  Deno.test(`${api}: exact scoped fields, precedence, syntax, required and unknown input`, () => {
    assertEquals<unknown>(build(s), s.request);
    for (const k of Object.keys(s.request)) {
      const x = structuredClone(s);
      delete x.request[k];
      assertThrows(() => build(x));
      for (const v of [null, "", " "]) {
        const x = structuredClone(s);
        x.request[k] = v as never;
        assertThrows(() => build(x));
      }
    }
    for (
      const k of [
        "client_code",
        "amc_code",
        "order_type",
        "sub_order_type",
        "transaction_type",
        "order_status",
        "settlement_type",
        "order_id",
        "order_ids",
        "member_unique_ids",
        "PAN",
        "folio",
        "url",
        "report_type",
        "date_type",
      ]
    ) {
      if (k in s.request) continue;
      const x = structuredClone(s);
      x.request[k] = "FOREIGN";
      assertThrows(() => build(x));
    }
    for (const v of ["2025-05-27", "31-02-2025", "1-05-2025", "01-01-0000"]) {
      const x = structuredClone(s);
      x.request.from_date = v;
      assertThrows(() => build(x));
    }
    const x = structuredClone(s);
    x.request.to_date = "26-06-2025";
    assertEquals<unknown>(build(x), x.request);
    x.request.to_date = "27-06-2025";
    assertThrows(() => build(x));
    x.request.to_date = "26-05-2025";
    assertThrows(() => build(x));
    const m = structuredClone(s);
    m.selectors.mode = "member";
    delete m.request.order_id;
    delete m.request.order_ids;
    m.request.member_unique_ids = s.selectors.rows[0].member_unique_id;
    assertEquals<unknown>(build(m), m.request);
    m.request[api.includes("PAYOUT") ? "order_id" : "order_ids"] =
      s.selectors.rows[0].order_id;
    assertThrows(() => build(m));
    m.request.member_unique_ids = "FOREIGN";
    assertThrows(() => build(m));
    const dup = structuredClone(s);
    dup.selectors.rows.push(dup.selectors.rows[0]);
    assertThrows(() => build(dup));
    if (api.includes("PAYOUT")) {
      for (
        const report_type of ["Order Date", "Payout Date", "Fund Transfer Date"]
      ) {
        assertEquals<unknown>(
          build({ ...s, request: { ...s.request, report_type } }),
          { ...s.request, report_type },
        );
      }
    }
    if (api === "ALLOTMENT_STATEMENT") {
      assertEquals<unknown>(
        build({ ...s, request: { ...s.request, date_type: "ALT_DATE" } }),
        { ...s.request, date_type: "ALT_DATE" },
      );
      for (
        const date_type of [
          "ORDER DATE",
          "REQUEST DATE",
          "ORDER_DATE",
          "alt_date",
        ]
      ) {
        assertThrows(() =>
          build({ ...s, request: { ...s.request, date_type } })
        );
      }
    }
  });
  Deno.test(`${api}: independent row schema, encrypted-only native statuses, envelopes and diagnostics`, () => {
    assertEquals(parse(body([row]), s), {
      nativeStatus: "S",
      nativeRemarkCategory: "settlement_redemption_report_received",
      success: true,
      recordCount: 1,
    });
    assertEquals(
      parse(body([]), s).nativeRemarkCategory,
      "settlement_redemption_no_records",
    );
    for (
      const remark of [
        "No record(s) found.",
        "No record(s) found",
        "PRIVATE",
        " ",
      ]
    ) {
      for (const rows of [[], [row]]) {
        const result = parse(body(rows, { error_remark: remark }), s);
        assertEquals(result.success, false);
        assertEquals(
          JSON.stringify(result).includes(remark.trim() || "impossible"),
          false,
        );
      }
    }
    assertEquals(
      parse(
        JSON.stringify({
          response_status: "F",
          report_data_total: 0,
          report_data: "",
          error_remark: "PRIVATE",
        }),
        s,
      ).nativeRemarkCategory,
      "settlement_redemption_business_failed",
    );
    for (
      const raw of [
        "PRIVATE",
        "null",
        "[]",
        "{}",
        body([row], { report_data_total: 0 }),
        body([], { report_data_total: null }),
        body([], { report_data_total: "1.0" }),
        body([], { report_data: {} }),
        body([], { error_remark: null }),
        body([], { response_status: "X" }),
        body([], { response_status: ["S"] }),
        body([], { response_status: null }),
        body([], { response_status: "F", error_remark: "PRIVATE" }),
        body([row], { response_status: "F" }),
        '{"response_status":"S","report_data_total":0,"report_data":[],"error_remark":"","extra":1e309}',
      ]
    ) assertEquals(parse(raw, s).success, false);
    for (const k of Object.keys(row)) {
      const changed = { ...row };
      delete changed[k];
      assertEquals(parse(body([changed]), s).success, false, `required ${k}`);
    }
    assertEquals(parse(body([{ ...row, extra: "PRIVATE" }]), s).success, true);
    assertEquals(parse(body([{ ...row, extra: {} }]), s).success, false);
    const id = api.includes("PAYOUT") ? "order_id" : "orderno",
      client = api.includes("PAYOUT") ? "client_code" : "clientcode";
    for (
      const key of [
        id,
        client,
        "member_unique_id",
        "isin",
        api.includes("PAYOUT") ? "scheme_code" : "schemecode",
        api.includes("PAYOUT")
          ? "member_code"
          : api === "ALLOTMENT_STATEMENT"
          ? "memberid"
          : "membercode",
        api.includes("PAYOUT") ? "settlement_id" : "settlementid",
      ]
    ) {
      assertEquals(
        parse(body([{ ...row, [key]: "FOREIGN" }]), s).success,
        false,
      );
    }
    assertEquals(
      parse(body([row, row]), s).nativeRemarkCategory,
      "settlement_redemption_duplicate_rows",
    );
    const two = structuredClone(s);
    two.selectors.rows.push({
      ...two.selectors.rows[0],
      order_id: "451480000469",
      member_unique_id: "SECOND",
    });
    two.request[api.includes("PAYOUT") ? "order_id" : "order_ids"] +=
      ",451480000469";
    assertEquals(
      parse(body([row]), two).nativeRemarkCategory,
      "settlement_redemption_incomplete_selection",
    );
    const second = { ...row, [id]: "451480000469", member_unique_id: "SECOND" };
    assertEquals(
      parse(body([row, second]), two).nativeRemarkCategory,
      "settlement_redemption_duplicate_rows",
    );
    second[api.includes("PAYOUT") ? "rta_transaction_no" : "rtatransactionno"] =
      "RTA002";
    assertEquals(parse(body([row, second]), two).success, true);
    if (!api.includes("PAYOUT")) {
      assertEquals(
        parse(body([{ ...row, ordersubtype: "SWH" }]), s).success,
        false,
      );
    }
    assertEquals(
      parse(
        body([{
          ...row,
          [api.includes("PAYOUT") ? "order_date" : "orderdate"]: "31-02-2025",
        }]),
        s,
      ).success,
      false,
    );
    // Native strings are observations, not a settled/paid/complete enum.
    assertEquals(Object.keys(parse(body([row]), s)).sort(), [
      "nativeRemarkCategory",
      "nativeStatus",
      "recordCount",
      "success",
    ]);
  });
}
