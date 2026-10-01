import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseOrderFundingRequest as build,
  ORDER_FUNDING_ENDPOINTS,
  type OrderFundingApi,
  type OrderFundingSource,
  parseNseOrderFundingResponse as parse,
} from "./nse_order_funding.ts";
const dates = {
  from_date: "21-01-2025",
  to_date: "28-01-2025",
  client_code: "SYNTHETIC1",
};
const fixtures = [
  {
    api: "ORDER_LIFECYCLE",
    path: "order_lifecycle",
    request: dates,
    row: {
      client_code: "SYNTHETIC1",
      product_type: "PUR",
      product_id: "450170000001",
      order_status: "VALID",
      payment_status: "SUCCESS",
      reconciliation_status: "SUCCESS",
      payment_account_no: "PRIVATE",
    },
  },
  {
    api: "TRANSACTION_DETAIL",
    path: "TRANSACTION_DETAIL_REPORT",
    request: { ...dates, date_type: "REQUEST_DATE" },
    row: {
      client_code: "SYNTHETIC1",
      primary_holder_pan: "AAAAA0000A",
      product_type: "NORMAL PURCHASE",
      product_id: "453530000107",
      sip_registration_no: " ",
      order_status: "VALID",
      payment_status: " ",
      reconciliation_status: " ",
      order_remark: "PRIVATE",
    },
  },
  {
    api: "FUND_ORDER",
    path: "MEMBER_FUND_ALLOCATION/ORDER_WISE",
    request: { ...dates, from_date: "10-11-2023", to_date: "10-11-2024" },
    row: {
      clientcode: "SYNTHETIC1",
      cfppgbankrefno: "080420241306423594511",
      utrno: "080420241304067310811",
      id: "486",
      totalamount: "10000",
      totalallocatedamount: "0",
      remainingamount: "10000",
      mappedorders: "",
      settledorders: "",
      allotmentorders: "",
      remitteraccountno: "PRIVATE",
    },
  },
  {
    api: "FUND_AGE",
    path: "MEMBER_FUND_ALLOCATION/AGE_WISE",
    request: {
      date: "30-04-2024",
      client_code: "SYNTHETIC1",
      settlement_type: "all",
    },
    row: {
      clientcode: "SYNTHETIC1",
      orderno: "440080000030",
      date: "30/04/2024",
      schemecode: "AXIOGP-GR",
      orderstatus: "INVALID",
      funds_received_status: "I",
      accountno: "PRIVATE",
    },
  },
] as const;
function source(f: typeof fixtures[number]): OrderFundingSource {
  return {
    operation_id: "local-op",
    workspace_id: "local-workspace",
    integration_account_id: "local-account",
    client_code: "SYNTHETIC1",
    pan: "AAAAA0000A",
    selectors: {},
    api: f.api,
    request: { ...f.request },
  };
}
function envelope(rows: unknown[], remark = "") {
  return {
    response_status: "S",
    report_data_total: String(rows.length),
    report_data: rows,
    error_remark: remark,
  };
}
for (const f of fixtures) {
  Deno.test(`${f.api}: independently specified route and exact request`, () => {
    assertEquals(
      ORDER_FUNDING_ENDPOINTS[f.api],
      `/nsemfdesk/api/v2/reports/${f.path}`,
    );
    assertEquals(build(source(f)), f.request);
  });
  Deno.test(`${f.api}: required fields, null/blank and arbitrary provider selectors fail closed`, () => {
    const s = source(f);
    for (const key of Object.keys(s.request)) {
      for (const value of [undefined, null, ""]) {
        const request = { ...s.request, [key]: value };
        if (value === undefined) {
          delete (request as Record<string, unknown>)[key];
        }
        assertThrows(
          () => build({ ...s, request } as unknown as OrderFundingSource),
          Error,
          "order_funding_request_invalid",
        );
      }
    }
    for (
      const key of [
        "order_ids",
        "order_id",
        "systematic_reg_id",
        "product_id",
        "Product_type",
        "product_type",
        "pg_bank_refno",
        "pan",
        "Pan",
        "applicant_name",
        "amc_code",
        "scheme_code",
        "member_code",
        "url",
      ]
    ) {
      assertThrows(() =>
        build(
          {
            ...s,
            request: { ...s.request, [key]: "FOREIGN" },
          } as unknown as OrderFundingSource,
        )
      );
    }
    assertThrows(() =>
      build({ ...s, request: { ...s.request, client_code: "FOREIGN" } })
    );
    assertThrows(() => build({ ...s, api: "UNKNOWN" as OrderFundingApi }));
  });
  Deno.test(`${f.api}: empty/nonempty read success exposes count only, never funding truth`, () => {
    const s = source(f);
    for (const rows of [[], [f.row]]) {
      const result = parse(JSON.stringify(envelope(rows)), s);
      assertEquals(result, {
        nativeStatus: "S",
        nativeRemarkCategory: "order_funding_report_received",
        success: true,
        recordCount: rows.length,
      });
      for (
        const secret of [
          "PRIVATE",
          "AAAAA0000A",
          "SYNTHETIC1",
          (f.row as Record<string, string>)[
            f.api === "FUND_AGE" ? "orderno" : "product_id"
          ],
        ]
      ) {
        if (secret) {
          assertEquals(JSON.stringify(result).includes(secret), false);
        }
      }
    }
  });
  Deno.test(`${f.api}: endpoint-specific diagnostic and failure semantics`, () => {
    const s = source(f);
    assertEquals(
      parse(JSON.stringify(envelope([], "PRIVATE")), s).success,
      f.api === "FUND_AGE",
    );
    assertEquals(
      parse(JSON.stringify(envelope([f.row], "PRIVATE")), s).success,
      false,
    );
    const failed = parse(
      JSON.stringify({
        response_status: "F",
        report_data_total: "0",
        report_data: "",
        error_remark: "PRIVATE",
      }),
      s,
    );
    assertEquals(failed, {
      nativeStatus: "F",
      nativeRemarkCategory: "order_funding_business_failed",
      success: false,
      recordCount: 0,
    });
    assertEquals(
      parse(JSON.stringify({ ...envelope([f.row]), response_status: "F" }), s)
        .success,
      false,
    );
    const missing = envelope([]) as Record<string, unknown>;
    delete missing.error_remark;
    assertEquals(parse(JSON.stringify(missing), s).success, false);
  });
  Deno.test(`${f.api}: malformed counts, mixed/foreign/duplicate rows, unknown types and privacy`, () => {
    const s = source(f);
    const body = envelope([f.row]);
    for (
      const bad of [
        "{",
        "\ufeff{}",
        "[]",
        "null",
        ...[null, "", -1, 1.5, "1.0", " 1", 2, 10001, {}, []].map((n) =>
          JSON.stringify({ ...body, report_data_total: n })
        ),
        ...["s", ["S"], null, ""].map((n) =>
          JSON.stringify({ ...body, response_status: n })
        ),
        ...[null, "", {}].map((n) =>
          JSON.stringify({ ...body, report_data: n })
        ),
        JSON.stringify(envelope([f.row, f.row])),
        JSON.stringify(
          envelope([f.row, {
            ...f.row,
            [f.api.startsWith("FUND_") ? "clientcode" : "client_code"]:
              "FOREIGN",
          }]),
        ),
        JSON.stringify(envelope([{ ...f.row, unknown: { value: "PRIVATE" } }])),
        JSON.stringify(envelope([{ ...f.row, unknown: null }])),
        JSON.stringify({ ...body, unknown: "\u0000" }),
        JSON.stringify({ ...body, unknown: "\ud800" }),
        JSON.stringify(body).replace(
          '"report_data_total":"1"',
          '"report_data_total":1e999',
        ),
      ]
    ) {
      const result = parse(bad, s);
      assertEquals(result.success, false);
      assertEquals(result.recordCount, 0);
      assertEquals(JSON.stringify(result).includes("PRIVATE"), false);
    }
  });
}

Deno.test("ORDER_LIFECYCLE: live UAT no-records diagnostic is exact, empty-only and private", () => {
  const f = fixtures[0];
  const s = source(f);
  const observed = parse(
    JSON.stringify(envelope([], "No record(s) found.")),
    s,
  );
  assertEquals(observed, {
    nativeStatus: "S",
    nativeRemarkCategory: "order_funding_no_records",
    success: true,
    recordCount: 0,
  });
  assertEquals(JSON.stringify(observed).includes("No record(s) found."), false);
  assertEquals(
    parse(JSON.stringify(envelope([], "No record found.")), s).success,
    false,
  );
  assertEquals(
    parse(JSON.stringify(envelope([f.row], "No record(s) found.")), s).success,
    false,
  );
});

Deno.test("B02 dates: seven-day gap, transaction three-day activity gap, FUND_ORDER no invented window", () => {
  for (const f of fixtures) {
    const s = source(f);
    const field = f.api === "FUND_AGE" ? "date" : "to_date";
    for (
      const value of ["2025-01-28", "31-02-2025", "01-01-0000", "1-01-2025"]
    ) {
      assertThrows(() =>
        build({ ...s, request: { ...s.request, [field]: value } })
      );
    }
    if (f.api !== "FUND_AGE") {
      assertThrows(() =>
        build({ ...s, request: { ...s.request, to_date: "01-01-2023" } })
      );
    }
  }
  for (const f of fixtures.slice(0, 2)) {
    assertThrows(() =>
      build({
        ...source(f),
        request: {
          ...dates,
          to_date: "29-01-2025",
          ...(f.api === "TRANSACTION_DETAIL"
            ? { date_type: "REQUEST_DATE" as const }
            : {}),
        },
      })
    );
  }
  const s = source(fixtures[1]);
  for (
    const date_type of [
      "REQUEST_DATE",
      "ORDER_DATE",
      "LAST_ACTIVITY_DATE",
    ] as const
  ) {
    build({ ...s, request: { ...dates, to_date: "24-01-2025", date_type } });
    if (date_type === "LAST_ACTIVITY_DATE") {
      assertThrows(() =>
        build({ ...s, request: { ...dates, to_date: "25-01-2025", date_type } })
      );
    }
  }
  for (
    const date_type of [
      "LAST ACTIVITY DATE",
      "last_activity_date",
      "REQUEST DATE",
      null,
      "",
    ]
  ) {
    assertThrows(() =>
      build(
        {
          ...s,
          request: { ...dates, date_type },
        } as unknown as OrderFundingSource,
      )
    );
  }
  assertThrows(() =>
    build(
      {
        ...source(fixtures[3]),
        request: { ...fixtures[3].request, settlement_type: "ALL" },
      } as unknown as OrderFundingSource,
    )
  );
});
Deno.test("ORDER_LIFECYCLE: exact Product_type, owned selection overrides dates but syntax remains required", () => {
  const selectors = {
    Product_type: "PUR",
    product_id: "450170000001",
  } as const;
  const s = {
    ...source(fixtures[0]),
    selectors,
    request: { ...dates, ...selectors },
  };
  assertEquals(build(s), {
    ...dates,
    Product_type: "PUR",
    product_id: "450170000001",
  });
  assertEquals(
    parse(JSON.stringify(envelope([fixtures[0].row])), s).success,
    true,
  );
  assertEquals(
    parse(
      JSON.stringify(envelope([{ ...fixtures[0].row, product_id: "OTHER" }])),
      s,
    ).success,
    false,
  );
  for (const Product_type of ["pur", "MANDATE", "XSIP CANCEL", ""]) {
    assertThrows(() =>
      build(
        {
          ...s,
          selectors: { ...selectors, Product_type },
          request: { ...s.request, Product_type },
        } as unknown as OrderFundingSource,
      )
    );
  }
  for (const product_id of ["", ",", "a,a", "a,".repeat(50) + "a", "a, b"]) {
    assertThrows(() =>
      build({
        ...s,
        selectors: { ...selectors, product_id },
        request: { ...s.request, product_id },
      })
    );
  }
  assertThrows(() =>
    build({ ...s, request: { ...s.request, to_date: "29-01-2025" } })
  );
});
Deno.test("TRANSACTION_DETAIL: owned order_id wins; systematic variant is explicitly unsupported", () => {
  const selectors = { order_id: "453530000107" };
  const s = {
    ...source(fixtures[1]),
    selectors,
    request: { ...dates, date_type: "REQUEST_DATE" as const, ...selectors },
  };
  assertEquals((build(s) as { order_id: string }).order_id, "453530000107");
  assertEquals(
    parse(JSON.stringify(envelope([fixtures[1].row])), s).success,
    true,
  );
  for (
    const row of [{ ...fixtures[1].row, product_id: "OTHER" }, {
      ...fixtures[1].row,
      primary_holder_pan: "BBBBB1111B",
    }]
  ) assertEquals(parse(JSON.stringify(envelope([row])), s).success, false);
  for (
    const request of [{ ...s.request, systematic_reg_id: "REG" }, {
      ...dates,
      date_type: "REQUEST_DATE",
      systematic_reg_id: "REG",
    }]
  ) {
    assertThrows(() =>
      build({ ...s, request } as unknown as OrderFundingSource)
    );
  }
});
Deno.test("FUND_AGE: documented date/identity columns, native status strings remain observations", () => {
  const s = source(fixtures[3]);
  assertEquals(
    parse(
      JSON.stringify(
        envelope([{
          ...fixtures[3].row,
          orderstatus: "payment_not_initiated",
          funds_received_status: "C",
        }]),
      ),
      s,
    ).success,
    true,
  );
  assertEquals(
    parse(
      JSON.stringify(envelope([{ ...fixtures[3].row, date: "01/05/2024" }])),
      s,
    ).success,
    false,
  );
});
