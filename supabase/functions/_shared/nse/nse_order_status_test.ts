import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseOrderStatusRequest,
  parseNseOrderStatusResponse,
} from "./nse_order_status.ts";
import type {
  NseOrderStatusRequest,
  NseOrderStatusSource,
} from "./nse_order_status.ts";

const request: NseOrderStatusRequest = {
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
};
function build(patch: Record<string, unknown> = {}) {
  return buildNseOrderStatusRequest(
    { request: { ...request, ...patch } } as NseOrderStatusSource,
  );
}
const row = {
  client_code: "SYNTHETIC1",
  order_id: "123456789012",
  member_unique_id: "SYNTHETICMEMBER1",
  order_date: "14/11/2023",
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
Deno.test("ORDER_STATUS: exact fields, inclusive seven dates, no provisional date_type", () => {
  assertEquals(build(), request);
  assertEquals(Object.hasOwn(build(), "date_type"), false);
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
    { date_type: "REQUEST DATE" },
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
  Deno.test(`ORDER_STATUS rejects invalid request case ${JSON.stringify(Object.keys(patch))} ${JSON.stringify(patch).length}`, () => {
    assertThrows(() => build(patch), Error, "order_status_request_invalid");
  });
}
Deno.test("ORDER_STATUS: all documented request enums remain distinct from row statuses", () => {
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
Deno.test("ORDER_STATUS: report success includes INVALID orders and excludes all PII", () => {
  assertEquals(parseNseOrderStatusResponse(report(), request), {
    nativeStatus: "S",
    nativeRemarkCategory: "order_status_report_received",
    success: true,
    recordCount: 1,
    validCount: 0,
    invalidCount: 1,
    otherCount: 0,
  });
  assertEquals(
    parseNseOrderStatusResponse(
      report([{ ...row, order_status: "VALID" }, row, {
        ...row,
        order_status: "NEW PRIVATE NATIVE TEXT",
      }], 3),
      request,
    ).otherCount,
    1,
  );
});
Deno.test("ORDER_STATUS: empty success is a successful read, not reconciliation", () => {
  assertEquals(parseNseOrderStatusResponse(report([]), request), {
    nativeStatus: "S",
    nativeRemarkCategory: "order_status_no_records",
    success: true,
    recordCount: 0,
    validCount: 0,
    invalidCount: 0,
    otherCount: 0,
  });
});
Deno.test("ORDER_STATUS: failure envelope never copies error_remark", () => {
  const observation = parseNseOrderStatusResponse(
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
    "order_status_vendor_rejected",
  );
  assertEquals(observation.success, false);
  assertEquals(JSON.stringify(observation).includes("PRIVATE"), false);
});
Deno.test("ORDER_STATUS: ID precedence and client correlation apply to every row", () => {
  const selected = build({
    order_ids: row.order_id,
    member_unique_ids: "IGNORED",
  });
  assertEquals(parseNseOrderStatusResponse(report(), selected).success, true);
  assertEquals(
    parseNseOrderStatusResponse(
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
      parseNseOrderStatusResponse(report(), req).nativeRemarkCategory,
      "order_status_scope_mismatch",
    );
  }
  const mixed = parseNseOrderStatusResponse(
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
  Deno.test(`ORDER_STATUS malformed envelope ${raw.slice(0, 18)} ${raw.length}`, () => {
    const parsed = parseNseOrderStatusResponse(raw, request);
    assertEquals(parsed.success, false);
    assertEquals(parsed.nativeRemarkCategory, "order_status_response_invalid");
    assertEquals(JSON.stringify(parsed).includes("PRIVATE"), false);
  });
}

Deno.test("ORDER_STATUS PostgreSQL-incompatible JSON remains an invalid response", () => {
  for (const email of ["\u0000", "\ud800", "\udfff"]) {
    assertEquals(
      parseNseOrderStatusResponse(report([{ ...row, email }]), request)
        .nativeStatus,
      null,
    );
    assertEquals(
      parseNseOrderStatusResponse(report([{ ...row, email }]), request).success,
      false,
    );
  }
});
