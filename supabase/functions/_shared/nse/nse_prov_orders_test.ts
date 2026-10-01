import {
  buildNseOrderStatusRequest,
  type NseOrderStatusSource,
  parseNseOrderStatusResponse,
} from "./nse_order_status.ts";
import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseProvOrdersRequest,
  parseNseProvOrdersResponse,
} from "./nse_prov_orders.ts";
import type {
  NseProvOrdersRequest,
  NseProvOrdersSource,
} from "./nse_prov_orders.ts";

const request: NseProvOrdersRequest = {
  from_date: "2023-11-10",
  to_date: "2023-11-16",
  trans_type: "ALL",
  order_type: "ALL",
  sub_order_type: "ALL",
  client_code: "SYNTHETIC1",
  order_status: "",
  settlement_type: "",
  order_ids: "",
  member_unique_ids: "",
  date_type: "REQUEST DATE",
};
function build(patch: Record<string, unknown> = {}) {
  return buildNseProvOrdersRequest(
    { request: { ...request, ...patch } } as NseProvOrdersSource,
  );
}
const row = {
  client_code: "SYNTHETIC1",
  order_id: "123456789012",
  member_unique_id: "SYNTHETICMEMBER1",
  request_date: "14/11/2023",
  order_status: "INVALID",
  order_remark: "SYNTHETIC PRIVATE REMARK",
  first_applicant_name: "SYNTHETIC NAME",
  email: "private@moneybowl.invalid",
  mobile_no: "0000000000",
  account_no: "SYNTHETIC BANK",
  DP_Folio_No: "SYNTHETIC FOLIO",
  amount: "200000",
  quantity: "0.000",
};
function report(rows: unknown[] = [row], total: unknown = String(rows.length)) {
  return JSON.stringify({
    response_status: "S",
    report_data_total: total,
    report_data: rows,
    error_remark: "",
  });
}
Deno.test("PROV_ORDERS: exact fields, inclusive seven dates, provisional date_type", () => {
  assertEquals(build(), request);
  assertEquals(build().date_type, "REQUEST DATE");
  assertEquals(
    build({ from_date: "2024-02-29", to_date: "2024-02-29" }).from_date,
    "2024-02-29",
  );
  assertEquals(
    build({
      order_ids: Array.from({ length: 50 }, (_, i) => String(i)).join(","),
    }).order_ids.split(",").length,
    50,
  );
  assertEquals(
    build({ member_unique_ids: "x".repeat(25) }).member_unique_ids.length,
    25,
  );
});
for (
  const patch of [
    { date_type: "" },
    { date_type: "request date" },
    { date_type: false },
    { from_date: "" },
    { to_date: "2023-11-17" },
    { to_date: "2023-11-09" },
    { from_date: "2023-02-29" },
    { from_date: "0000-01-01" },
    { trans_type: "BUY" },
    { order_type: "SO" },
    { sub_order_type: "SIP" },
    { order_status: "ALL" },
    { settlement_type: "T3" },
    { client_code: "" },
    { client_code: "x".repeat(21) },
    { order_ids: "1,,2" },
    { order_ids: "1, 2" },
    { member_unique_ids: "x".repeat(26) },
    { member_unique_ids: null },
    { order_ids: Array.from({ length: 51 }, (_, i) => String(i)).join(",") },
    {
      member_unique_ids: Array.from({ length: 51 }, (_, i) => String(i)).join(
        ",",
      ),
    },
    { from_date: "", order_ids: "123" },
  ]
) {
  Deno.test(`PROV_ORDERS rejects invalid request case ${JSON.stringify(Object.keys(patch))} ${JSON.stringify(patch).length}`, () => {
    assertThrows(() => build(patch), Error, "prov_orders_request_invalid");
  });
}
Deno.test("PROV_ORDERS: all documented request enums remain distinct from row statuses", () => {
  for (const trans_type of ["P", "R", "ALL"]) build({ trans_type });
  for (const order_type of ["ALL", "NRM", "SIP", "XSP", "STP"]) {
    build({ order_type });
  }
  for (const sub_order_type of ["ALL", "NRM", "SPOR", "SWH", "STP"]) {
    build({ sub_order_type });
  }
  for (const order_status of ["", "All", "VALID", "INVALID"]) {
    build({ order_status });
  }
  for (const settlement_type of ["", "ALL", "L0", "L1", "OTHERS"]) {
    build({ settlement_type });
  }
});
Deno.test("PROV_ORDERS: report success includes INVALID orders and excludes all PII", () => {
  assertEquals(parseNseProvOrdersResponse(report(), request), {
    nativeStatus: "S",
    nativeRemarkCategory: "prov_orders_report_received",
    success: true,
    recordCount: 1,
    validCount: 0,
    invalidCount: 1,
    otherCount: 0,
  });
  assertEquals(
    parseNseProvOrdersResponse(
      report([{ ...row, order_status: "VALID" }, row, {
        ...row,
        order_status: "NEW PRIVATE NATIVE TEXT",
      }], 3),
      request,
    ).otherCount,
    1,
  );
});
Deno.test("PROV_ORDERS: empty success is a successful read, not reconciliation", () => {
  assertEquals(parseNseProvOrdersResponse(report([]), request), {
    nativeStatus: "S",
    nativeRemarkCategory: "prov_orders_no_records",
    success: true,
    recordCount: 0,
    validCount: 0,
    invalidCount: 0,
    otherCount: 0,
  });
});

Deno.test("PROV_ORDERS: failure envelope never copies error_remark", () => {
  const observation = parseNseProvOrdersResponse(
    JSON.stringify({
      response_status: "F",
      report_data_total: "0",
      report_data: "",
      error_remark: "PRIVATE",
    }),
    request,
  );
  assertEquals(
    observation.nativeRemarkCategory,
    "prov_orders_vendor_rejected",
  );
  assertEquals(observation.success, false);
  assertEquals(JSON.stringify(observation).includes("PRIVATE"), false);
});
Deno.test("PROV_ORDERS: ID precedence and client correlation apply to every row", () => {
  const selected = build({
    order_ids: row.order_id,
    member_unique_ids: "IGNORED",
  });
  assertEquals(parseNseProvOrdersResponse(report(), selected).success, true);
  assertEquals(
    parseNseProvOrdersResponse(
      report(),
      build({ member_unique_ids: row.member_unique_id }),
    ).success,
    true,
  );
  for (
    const req of [
      build({ order_ids: "OTHER" }),
      build({ member_unique_ids: "OTHER" }),
      build({ client_code: "OTHER" }),
    ]
  ) {
    assertEquals(
      parseNseProvOrdersResponse(report(), req).nativeRemarkCategory,
      "prov_orders_scope_mismatch",
    );
  }
  const mixed = parseNseProvOrdersResponse(
    report([row, { ...row, client_code: "OTHER" }]),
    request,
  );
  assertEquals(mixed.success, false);
  assertEquals(mixed.recordCount, 0);
});
for (
  const raw of [
    "not json",
    "null",
    "[]",
    "{}",
    report([row], "2"),
    report([row], true),
    report([row], -1),
    report([row], "1.0"),
    report([null]),
    report([{ ...row, client_code: null }]),
    report([{ ...row, order_id: 123 }]),
    report([{ ...row, order_status: "" }]),
    JSON.stringify({
      response_status: "PRIVATE",
      report_data_total: "0",
      report_data: [],
      error_remark: "",
    }),
    JSON.stringify({
      response_status: "S",
      report_data_total: "0",
      report_data: {},
      error_remark: "",
    }),
  ]
) {
  Deno.test(`PROV_ORDERS malformed envelope ${raw.slice(0, 18)} ${raw.length}`, () => {
    const parsed = parseNseProvOrdersResponse(raw, request);
    assertEquals(parsed.success, false);
    assertEquals(parsed.nativeRemarkCategory, "prov_orders_response_invalid");
    assertEquals(JSON.stringify(parsed).includes("PRIVATE"), false);
  });
}

Deno.test("PROV_ORDERS PostgreSQL-incompatible JSON remains an invalid response", () => {
  for (const email of ["\u0000", "\ud800", "\udfff"]) {
    assertEquals(
      parseNseProvOrdersResponse(report([{ ...row, email }]), request)
        .nativeStatus,
      null,
    );
    assertEquals(
      parseNseProvOrdersResponse(report([{ ...row, email }]), request).success,
      false,
    );
  }
});

Deno.test("PROV_ORDERS: date_type is optional, null defaults, ORDER_STATUS stays distinct", () => {
  for (const date_type of [undefined, null, "REQUEST DATE", "ORDER DATE"]) {
    const built = build({ date_type });
    assertEquals(built.date_type, date_type ?? "REQUEST DATE");
    assertEquals(Object.keys(built).sort(), Object.keys(request).sort());
    assertThrows(() =>
      buildNseOrderStatusRequest({ request: built } as NseOrderStatusSource)
    );
  }
  const { date_type: _date, ...common } = request;
  assertEquals(
    buildNseProvOrdersRequest({ request: common } as NseProvOrdersSource),
    request,
  );
  assertEquals(
    buildNseOrderStatusRequest({ request: common } as NseOrderStatusSource),
    common,
  );
});
Deno.test("PROV_ORDERS: historical request 20 empty success retains diagnostic only in evidence", () => {
  // live_uat_results.json ordinal 20: success_like, nonempty_diagnostic,
  // string count, and an empty array. Safe evidence retains no literal values.
  const raw = JSON.stringify({
    response_status: "S",
    report_data_total: "0",
    report_data: [],
    error_remark: "SYNTHETIC PRIVATE UAT DIAGNOSTIC",
  });
  assertEquals(parseNseProvOrdersResponse(raw, request), {
    nativeStatus: "S",
    nativeRemarkCategory: "prov_orders_no_records",
    success: true,
    recordCount: 0,
    validCount: 0,
    invalidCount: 0,
    otherCount: 0,
  });
  assertEquals(
    JSON.stringify(parseNseProvOrdersResponse(raw, request)).includes(
      "PRIVATE",
    ),
    false,
  );
  assertEquals(parseNseOrderStatusResponse(raw, request).success, true);
});
Deno.test("PROV_ORDERS: success diagnostic does not change row counts or expose PII", () => {
  const raw = JSON.stringify({
    ...JSON.parse(report([row, { ...row, order_status: "VALID" }])),
    error_remark: "SYNTHETIC PRIVATE UAT DIAGNOSTIC",
  });
  assertEquals(parseNseProvOrdersResponse(raw, request), {
    nativeStatus: "S",
    nativeRemarkCategory: "prov_orders_report_received",
    success: true,
    recordCount: 2,
    validCount: 1,
    invalidCount: 1,
    otherCount: 0,
  });
});
Deno.test("PROV_ORDERS: nonempty diagnostic never bypasses envelope or account/ID checks", () => {
  const valid = {
    ...JSON.parse(report()),
    error_remark: "SYNTHETIC PRIVATE UAT DIAGNOSTIC",
  };
  for (
    const patch of [
      { response_status: "F" },
      { response_status: "UNKNOWN" },
      { report_data: {} },
      { report_data: "" },
      { report_data: [null] },
      { report_data_total: "0" },
      { report_data_total: "2" },
      { report_data_total: "1.0" },
      { report_data_total: -1 },
      { report_data: [{ ...row, client_code: "OTHER" }] },
      { error_remark: null },
      { error_remark: 123 },
      { error_remark: undefined },
    ]
  ) {
    const parsed = parseNseProvOrdersResponse(
      JSON.stringify({ ...valid, ...patch }),
      request,
    );
    assertEquals(parsed.success, false);
    assertEquals(parsed.recordCount, 0);
    assertEquals(JSON.stringify(parsed).includes("PRIVATE"), false);
  }
  for (
    const selected of [
      build({ order_ids: "OTHER" }),
      build({ member_unique_ids: "OTHER" }),
    ]
  ) {
    const parsed = parseNseProvOrdersResponse(JSON.stringify(valid), selected);
    assertEquals(parsed.nativeRemarkCategory, "prov_orders_scope_mismatch");
    assertEquals(parsed.success, false);
  }
});
Deno.test("PROV_ORDERS: p80-81 response enums and request_date are not request enums/order_date", () => {
  const raw = report([
    {
      ...row,
      request_date: "14/11/2023",
      order_type: "SO",
      settlement_type: "T3",
      order_status: "VALID",
    },
    {
      ...row,
      request_date: "14/11/2023",
      order_type: "SI",
      settlement_type: "T1",
      order_status: "VALID",
    },
  ]);
  assertEquals(parseNseProvOrdersResponse(raw, request).validCount, 2);
  assertEquals(raw.includes('"order_date"'), false);
  // No mandatory date field is invented from an illustrative row.
  const { request_date: _date, ...withoutDate } = row;
  assertEquals(
    parseNseProvOrdersResponse(report([withoutDate]), request).success,
    true,
  );
});
