import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  buildNseClientReadinessRequest as build,
  parseNseClientReadinessResponse as parse,
  READINESS_ENDPOINTS,
  type ReadinessApi,
  type ReadinessSource,
} from "./nse_client_readiness.ts";

const pan = "AAAAA0000A", client = "SYNTHETIC1";
const dates = { from_date: "21-01-2025", to_date: "28-01-2025" };
// Independent fixtures follow the six sections, not an ORDER_STATUS envelope.
const cases: {
  api: ReadinessApi;
  path: string;
  request: ReadinessSource["request"];
  row: Record<string, string>;
  remark: boolean;
}[] = [
  {
    api: "CLIENT_AUTHORIZATION",
    path: "client_authorization",
    request: { ...dates, client_code: client, date_type: "AUTH_SENT_DATE" },
    remark: true,
    row: {
      client_code: client,
      primary_holder_pan: pan,
      auth_status: "SUCCESS",
      first_holder_auth_status: "SUCCESS",
      bank1_account_no: "PRIVATE",
      third_holder_aof_elog_remakrs: "",
    },
  },
  {
    api: "CLIENT_DETAIL",
    path: "CLIENT_DETAIL_REPORT",
    request: { ...dates, client_code: client, date_type: "MODIFIED_DATE" },
    remark: true,
    row: {
      client_code: client,
      primary_holder_pan: pan,
      auth_status: "-",
      ucc_status: "Inactive",
      primary_holder_kyc_checked: "N",
      primary_holder_kyc_status: " - ",
      first_holder_eLog_exists: "N",
      first_holder_email: "PRIVATE",
    },
  },
  {
    api: "TWO_FA",
    path: "2fa",
    request: { ...dates, client_code: client },
    remark: true,
    row: {
      client_code: client,
      product_type: "PUR",
      product_id: "100",
      primary_holder_authentication_status: "SUCCESS",
      primary_holder_mobile: "PRIVATE",
    },
  },
  {
    api: "CLIENT_KYC_REPORT",
    path: "CLIENT_KYC_REPORT",
    request: { pan_no: pan },
    remark: false,
    row: {
      client_code: client,
      client_pan: pan,
      holding_type: "",
      holder_name: "PRIVATE",
      holder_dob: "",
      kyc_status: "",
      status_remark: "PRIVATE",
    },
  },
  {
    api: "FATCA_REPORT",
    path: "FATCA_REPORT",
    request: { pan_pkern_no: pan },
    remark: false,
    row: {
      pan_rp: pan,
      pekrn: "",
      camsuploadstatus: "NOT UPLOADED",
      camsresponsestatus: "PENDING",
      kfinuploadstatus: "NOT UPLOADED",
      kfinresponsestatus: "PENDING",
      aadhaar_rp: "PRIVATE",
      "po_bir_inc ": "IN",
    },
  },
  {
    api: "ELOG_REPORT",
    path: "ELOG_UPLOAD_REPORT",
    request: { client_code: client },
    remark: false,
    row: {
      client_code: client,
      pan,
      pan_type: "F",
      elog_type: "NSELM",
      cams_status: "Uploaded - Ready to invest",
      kfin_status: "Uploaded - Ready to invest",
      applicant_name: "PRIVATE",
    },
  },
];
for (const c of cases) {
  const source: ReadinessSource = {
    operation_id: "op",
    workspace_id: "workspace",
    integration_account_id: "account",
    api: c.api,
    client_code: client,
    pan,
    request: c.request,
  };
  const envelope = (rows: unknown[] = [c.row]) => ({
    response_status: "S",
    report_data_total: String(rows.length),
    report_data: rows,
    ...(c.remark ? { error_remark: "" } : {}),
  });
  const classify = (body: unknown) => parse(JSON.stringify(body), source);
  Deno.test(`${c.api}: independent path, exact request and selector rejection`, () => {
    assertEquals(
      READINESS_ENDPOINTS[c.api],
      `/nsemfdesk/api/v2/reports/${c.path}`,
    );
    assertEquals(build(source), c.request);
    for (const key of Object.keys(c.request)) {
      assertThrows(() =>
        build({
          ...source,
          request: Object.fromEntries(
            Object.entries(c.request).filter(([k]) => k !== key),
          ) as never,
        })
      );
    }
    for (
      const key of [
        "PAN",
        "product_id",
        "product_type",
        "Product_type",
        "order_ids",
        "member_unique_ids",
        "url",
        "pan_pkern_no",
        "pan_no",
        "client_code",
      ]
    ) {
      if (key in c.request) continue;
      assertThrows(() =>
        build({
          ...source,
          request: { ...c.request, [key]: "FOREIGN" } as never,
        })
      );
    }
    for (
      const request of [{ ...c.request, client_code: "FOREIGN" }, {
        ...c.request,
        pan_no: "BBBBB1111B",
      }]
    ) assertThrows(() => build({ ...source, request }));
  });
  Deno.test(`${c.api}: empty/nonempty success, native states stay private, no diagnostic exception`, () => {
    for (const rows of [[], [c.row]]) {
      const result = classify(envelope(rows));
      assertEquals(result.success, true);
      assertEquals(result.recordCount, rows.length);
      assertEquals(JSON.stringify(result).includes("PRIVATE"), false);
      assertEquals(JSON.stringify(result).includes(pan), false);
    }
    assertEquals(
      classify({ ...envelope(), report_data_total: 1 }).success,
      true,
    );
    assertEquals(
      classify({ ...envelope(), error_remark: "PRIVATE" }).success,
      false,
    );
    if (c.remark) {
      const body: Record<string, unknown> = envelope();
      delete body.error_remark;
      assertEquals(classify(body).success, false);
    }
    assertEquals(
      classify({ ...envelope(), response_status: "F", error_remark: "PRIVATE" })
        .nativeRemarkCategory,
      "client_readiness_business_failed",
    );
  });
  Deno.test(`${c.api}: malformed, mixed scope, duplicate rows and counts fail closed`, () => {
    for (
      const raw of [
        "PRIVATE",
        "null",
        "[]",
        "{}",
        "{",
        '{"response_status":"s"}',
      ]
    ) assertEquals(parse(raw, source).success, false);
    for (
      const count of [-1, 0, 1.5, "1.0", "-1", null, {}, "99999999999999999999"]
    ) {
      assertEquals(
        classify({ ...envelope(), report_data_total: count }).success,
        false,
      );
    }
    for (
      const row of [null, [], {}, {
        ...c.row,
        [c.api === "FATCA_REPORT" ? "pan_rp" : "client_code"]: "FOREIGN",
      }, { ...c.row, extra: { private: true } }]
    ) {
      assertEquals(classify(envelope([row])).success, false);
      assertEquals(classify(envelope([c.row, row])).success, false);
    }
    assertEquals(
      classify(envelope([c.row, { ...c.row }])).nativeRemarkCategory,
      "client_readiness_duplicate_rows",
    );
    if (c.api !== "TWO_FA") {
      const field = c.api === "CLIENT_KYC_REPORT"
        ? "client_pan"
        : c.api === "FATCA_REPORT"
        ? "pan_rp"
        : c.api === "ELOG_REPORT"
        ? "pan"
        : "primary_holder_pan";
      assertEquals(
        classify(envelope([{ ...c.row, [field]: "BBBBB1111B" }])).success,
        false,
      );
    }
  });
  if (
    c.api === "CLIENT_AUTHORIZATION" || c.api === "CLIENT_DETAIL" ||
    c.api === "TWO_FA"
  ) {
    Deno.test(`${c.api}: seven-day GAP, DD-MM-YYYY, real dates and exact enums`, () => {
      for (
        const to_date of [
          "29-01-2025",
          "20-01-2025",
          "2025-01-28",
          "31-02-2025",
          "01-01-0000",
        ]
      ) {
        assertThrows(() =>
          build({ ...source, request: { ...c.request, to_date } })
        );
      }
      assertEquals(
        (build({
          ...source,
          request: {
            ...c.request,
            from_date: "28-02-2024",
            to_date: "01-03-2024",
          },
        }) as { from_date: string }).from_date,
        "28-02-2024",
      );
      for (
        const auth_status of ["AUTHORIZED", "pending", "", null, ["PENDING"]]
      ) {
        assertThrows(() =>
          build({ ...source, request: { ...c.request, auth_status } as never })
        );
      }
      for (const date_type of ["MODIFIED _DATE", "auth_sent_date", "", null]) {
        assertThrows(() =>
          build({ ...source, request: { ...c.request, date_type } as never })
        );
      }
      if (c.api === "CLIENT_AUTHORIZATION") {
        assertThrows(() =>
          build({
            ...source,
            request: { ...c.request, date_type: "MODIFIED_DATE" },
          })
        );
      }
      if (c.api !== "TWO_FA") {
        for (const auth_status of ["PENDING", "AUTHORIZE", "REVIEW"] as const) {
          assertEquals(
            (build({ ...source, request: { ...c.request, auth_status } }) as {
              auth_status: string;
            }).auth_status,
            auth_status,
          );
        }
      }
    });
  }
}

Deno.test("B01 rejects JSON strings PostgreSQL cannot retain as parsed jsonb", () => {
  const source: ReadinessSource = {
    operation_id: "op",
    workspace_id: "w",
    integration_account_id: "a",
    api: "CLIENT_KYC_REPORT",
    client_code: "SYNTHETIC1",
    pan: "AAAAA0000A",
    request: { pan_no: "AAAAA0000A" },
  };
  for (const extra of ['"\\u0000"', '"\\ud800"', '"\\udc00"', "1e999"]) {
    assertEquals(
      parse(
        `{"response_status":"S","report_data_total":0,"report_data":[],"extra":${extra}}`,
        source,
      ).success,
      false,
    );
  }
});
