import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  CamsParser,
  createSyntheticDbf,
  KfintechParser,
  ParserRegistry,
} from "./parser.ts";
import {
  camsDbfFixture,
  camsDbfFixtureWithRows,
  genuineCamsDbfFixture,
  kfintechDbfFixture,
  syntheticCasPdfFixture,
} from "./fixtures.ts";

const camsAcceptedCodes = [
  ["BUY", "BUY", "INFLOW", "12.5000", "250.00"],
  ["PURCHASE", "BUY", "INFLOW", "12.5000", "250.00"],
  ["PUR", "BUY", "INFLOW", "12.5000", "250.00"],
  ["SIP", "BUY", "INFLOW", "12.5000", "250.00"],
  ["SELL", "SELL", "OUTFLOW", "-5.0000", "-50.00"],
  ["REDEMPTION", "SELL", "OUTFLOW", "-5.0000", "-50.00"],
  ["RED", "SELL", "OUTFLOW", "-5.0000", "-50.00"],
  ["SWITCH_IN", "SWITCH", "INFLOW", "7.0000", "70.00"],
  ["SWITCH_OUT", "SWITCH", "OUTFLOW", "-7.0000", "-70.00"],
] as const;

const kfintechAcceptedCodes = [
  ["P", "BUY", "INFLOW", "12.5000", "250.00"],
  ["PURCHASE", "BUY", "INFLOW", "12.5000", "250.00"],
  ["ADDITIONAL_PURCHASE", "BUY", "INFLOW", "12.5000", "250.00"],
  ["SIP", "BUY", "INFLOW", "12.5000", "250.00"],
  ["R", "SELL", "OUTFLOW", "-5.0000", "-50.00"],
  ["REDEMPTION", "SELL", "OUTFLOW", "-5.0000", "-50.00"],
  ["FULL_REDEMPTION", "SELL", "OUTFLOW", "-5.0000", "-50.00"],
  ["SI", "SWITCH", "INFLOW", "7.0000", "70.00"],
  ["SO", "SWITCH", "OUTFLOW", "-7.0000", "-70.00"],
] as const;

const genuineCamsAcceptedCodes = [
  ["Additional Purchase", "BUY", "INFLOW"],
  ["Additional Purchase Systematic", "BUY", "INFLOW"],
  ["Fresh Purchase Systematic", "BUY", "INFLOW"],
  ["NFO FP", "BUY", "INFLOW"],
  ["Full Redemption", "SELL", "OUTFLOW"],
  ["Partial Switch Out", "SWITCH", "OUTFLOW"],
] as const;

Deno.test("CAMS DBF fixture produces deterministic normalized transaction", async () => {
  const parser = new CamsParser();
  const rows = await parser.parse({
    registrar: "CAMS",
    fileType: "DBF",
    filename: "cams.dbf",
    bytes: camsDbfFixture(),
  });

  assertEquals(rows.length, 1);
  assertEquals(rows[0].registrar, "CAMS");
  assertEquals(rows[0].clientPan, "ABCDE1234F");
  assertEquals(rows[0].folioNumber, "FOLIO1001");
  assertEquals(rows[0].schemeCode, "CAMS001");
  assertEquals(rows[0].transactionType, "BUY");
  assertEquals(rows[0].transactionDirection, "INFLOW");
  assertEquals(rows[0].registrarTransactionCode, "BUY");
  assertEquals(rows[0].amount, 250);
  assertEquals(rows[0].date, "2026-07-29");
});

Deno.test("KFintech DBF fixture produces deterministic normalized transaction", async () => {
  const parser = new KfintechParser();
  const rows = await parser.parse({
    registrar: "KFINTECH",
    fileType: "DBF",
    filename: "kfintech.dbf",
    bytes: kfintechDbfFixture(),
  });

  assertEquals(rows.length, 1);
  assertEquals(rows[0].registrar, "KFINTECH");
  assertEquals(rows[0].clientPan, "FGHIJ5678K");
  assertEquals(rows[0].folioNumber, "KFOLIO1001");
  assertEquals(rows[0].schemeCode, "KFIN001");
  assertEquals(rows[0].transactionType, "SELL");
  assertEquals(rows[0].transactionDirection, "OUTFLOW");
  assertEquals(rows[0].registrarTransactionCode, "R");
  assertEquals(rows[0].units, 5);
  assertEquals(rows[0].amount, 50);
});

Deno.test("CAS PDF fixture uses Edge-compatible text extractor", async () => {
  const parser = new CamsParser({
    extractRows: () =>
      Promise.resolve([{
        PAN: "ABCDE1234F",
        INV_NAME: "Issue Investor",
        FOLIO_NO: "FOLIO1001",
        SCHEME_CD: "CAMS001",
        SCHEME_NM: "CAMS Equity Fund",
        FUND_HOUSE: "CAMS AMC",
        CATEGORY: "Equity",
        TRX_TYPE: "BUY",
        UNITS: "12.5000",
        NAV: "20.0000",
        AMOUNT: "250.00",
        TRX_DATE: "20260729",
      }]),
  });

  const rows = await parser.parse({
    registrar: "CAMS",
    fileType: "CAS_PDF",
    filename: "cas.pdf",
    bytes: syntheticCasPdfFixture(),
  });

  assertEquals(rows.length, 1);
  assertEquals(rows[0].schemeCode, "CAMS001");
});

for (
  const [code, expectedType, expectedDirection, units, amount]
    of camsAcceptedCodes
) {
  Deno.test(`CAMS transaction code ${code} maps explicitly`, async () => {
    const [row] = await new CamsParser().parse({
      registrar: "CAMS",
      fileType: "DBF",
      filename: "cams.dbf",
      bytes: camsDbfFixture({ TRX_TYPE: code, UNITS: units, AMOUNT: amount }),
    });
    assertEquals(row.transactionType, expectedType);
    assertEquals(row.transactionDirection, expectedDirection);
    assertEquals(row.registrarTransactionCode, code);
    assertEquals(row.units > 0, true);
    assertEquals(row.amount > 0, true);
  });
}

for (
  const [code, expectedType, expectedDirection, units, amount]
    of kfintechAcceptedCodes
) {
  Deno.test(`KFintech transaction code ${code} maps explicitly`, async () => {
    const [row] = await new KfintechParser().parse({
      registrar: "KFINTECH",
      fileType: "DBF",
      filename: "kfintech.dbf",
      bytes: kfintechDbfFixture({
        TD_TRTYPE: code,
        TD_UNITS: units,
        TD_AMT: amount,
      }),
    });
    assertEquals(row.transactionType, expectedType);
    assertEquals(row.transactionDirection, expectedDirection);
    assertEquals(row.registrarTransactionCode, code);
    assertEquals(row.units > 0, true);
    assertEquals(row.amount > 0, true);
  });
}

for (
  const [code, expectedType, expectedDirection] of genuineCamsAcceptedCodes
) {
  Deno.test(
    "genuine-style CAMS transaction description " + code + " maps explicitly",
    async () => {
      const [row] = await new CamsParser().parse({
        registrar: "CAMS",
        fileType: "DBF",
        filename: "synthetic-genuine-cams.dbf",
        bytes: genuineCamsDbfFixture({ TRXN_TYPE_: code }),
      });
      assertEquals(row.transactionType, expectedType);
      assertEquals(row.transactionDirection, expectedDirection);
      assertEquals(
        row.registrarTransactionCode,
        code.toUpperCase().replaceAll(" ", "_"),
      );
      assertEquals(row.units, 12.5);
      assertEquals(row.amount, 250);
      assertEquals(row.date, "2026-07-29");
    },
  );
}

Deno.test("switch legs preserve direction after magnitude normalization", async () => {
  const [camsIn] = await new CamsParser().parse({
    registrar: "CAMS",
    fileType: "DBF",
    filename: "cams-switch-in.dbf",
    bytes: camsDbfFixture({
      TRX_TYPE: "SWITCH_IN",
      UNITS: "7.0000",
      AMOUNT: "70.00",
    }),
  });
  const [camsOut] = await new CamsParser().parse({
    registrar: "CAMS",
    fileType: "DBF",
    filename: "cams-switch-out.dbf",
    bytes: camsDbfFixture({
      TRX_TYPE: "SWITCH_OUT",
      UNITS: "-7.0000",
      AMOUNT: "-70.00",
    }),
  });
  const [kfinIn] = await new KfintechParser().parse({
    registrar: "KFINTECH",
    fileType: "DBF",
    filename: "kfin-switch-in.dbf",
    bytes: kfintechDbfFixture({
      TD_TRTYPE: "SI",
      TD_UNITS: "7.0000",
      TD_AMT: "70.00",
    }),
  });
  const [kfinOut] = await new KfintechParser().parse({
    registrar: "KFINTECH",
    fileType: "DBF",
    filename: "kfin-switch-out.dbf",
    bytes: kfintechDbfFixture({
      TD_TRTYPE: "SO",
      TD_UNITS: "-7.0000",
      TD_AMT: "-70.00",
    }),
  });

  assertEquals(camsIn.transactionType, camsOut.transactionType);
  assertEquals(camsIn.units, camsOut.units);
  assertEquals(camsIn.amount, camsOut.amount);
  assertEquals(camsIn.transactionDirection, "INFLOW");
  assertEquals(camsOut.transactionDirection, "OUTFLOW");
  assertEquals(camsIn.registrarTransactionCode, "SWITCH_IN");
  assertEquals(camsOut.registrarTransactionCode, "SWITCH_OUT");
  assertEquals(kfinIn.transactionDirection, "INFLOW");
  assertEquals(kfinOut.transactionDirection, "OUTFLOW");
  assertEquals(kfinIn.registrarTransactionCode, "SI");
  assertEquals(kfinOut.registrarTransactionCode, "SO");
});

Deno.test("unknown and ambiguous transaction codes fail closed", async () => {
  const parser = new CamsParser();
  for (const code of ["UNKNOWN", "BUY_OR_SELL"]) {
    await assertRejects(
      () =>
        parser.parse({
          registrar: "CAMS",
          fileType: "DBF",
          filename: "bad.dbf",
          bytes: camsDbfFixture({ TRX_TYPE: code }),
        }),
      Error,
      "parse_failed",
    );
  }
});

Deno.test("sign semantics are action-specific", async () => {
  await assertRejects(
    () =>
      new CamsParser().parse({
        registrar: "CAMS",
        fileType: "DBF",
        filename: "bad-purchase.dbf",
        bytes: camsDbfFixture({
          TRX_TYPE: "BUY",
          UNITS: "-1.0000",
          AMOUNT: "-20.00",
        }),
      }),
    Error,
    "parse_failed",
  );
  const [redemption] = await new CamsParser().parse({
    registrar: "CAMS",
    fileType: "DBF",
    filename: "redemption.dbf",
    bytes: camsDbfFixture({
      TRX_TYPE: "REDEMPTION",
      UNITS: "-1.0000",
      AMOUNT: "-20.00",
    }),
  });
  assertEquals(redemption.transactionType, "SELL");
  assertEquals(redemption.units, 1);
  assertEquals(redemption.amount, 20);
});

Deno.test("genuine CAMS outflow descriptions require positive source magnitudes", async () => {
  for (
    const [code, expectedType] of [
      ["Full Redemption", "SELL"],
      ["Partial Switch Out", "SWITCH"],
    ] as const
  ) {
    const [row] = await new CamsParser().parse({
      registrar: "CAMS",
      fileType: "DBF",
      filename: "synthetic-genuine-cams-outflow.dbf",
      bytes: genuineCamsDbfFixture({ TRXN_TYPE_: code }),
    });
    assertEquals(row.transactionType, expectedType);
    assertEquals(row.transactionDirection, "OUTFLOW");
    assertEquals(row.units, 12.5);
    assertEquals(row.amount, 250);

    await assertRejects(
      () =>
        new CamsParser().parse({
          registrar: "CAMS",
          fileType: "DBF",
          filename: "synthetic-genuine-cams-invalid-outflow.dbf",
          bytes: genuineCamsDbfFixture({
            TRXN_TYPE_: code,
            UNITS: "-12.5000",
            AMOUNT: "-250.00",
          }),
        }),
      Error,
      "parse_failed",
    );
  }
});

Deno.test("negative units amount and invalid NAV fail where unsupported", async () => {
  const invalidOverrides: Record<string, string>[] = [
    { UNITS: "-1.0000" },
    { AMOUNT: "-20.00" },
    { NAV: "0" },
    { NAV: "-1.0000" },
  ];
  for (const override of invalidOverrides) {
    await assertRejects(
      () =>
        new CamsParser().parse({
          registrar: "CAMS",
          fileType: "DBF",
          filename: "bad.dbf",
          bytes: camsDbfFixture(override),
        }),
      Error,
      "parse_failed",
    );
  }
});

Deno.test("calendar dates are round-trip validated", async () => {
  for (const date of ["20260230", "20260015", "20261315", "20250229"]) {
    await assertRejects(
      () =>
        new CamsParser().parse({
          registrar: "CAMS",
          fileType: "DBF",
          filename: "bad-date.dbf",
          bytes: camsDbfFixture({ TRX_DATE: date }),
        }),
      Error,
      "parse_failed",
    );
  }
});

Deno.test("canonical PAN format is required", async () => {
  await assertRejects(
    () =>
      new CamsParser().parse({
        registrar: "CAMS",
        fileType: "DBF",
        filename: "bad-pan.dbf",
        bytes: camsDbfFixture({ PAN: "BADPAN123" }),
      }),
    Error,
    "parse_failed",
  );
});

Deno.test("actual CAMS and KFintech field aliases are independent", async () => {
  const camsRows = await new CamsParser().parse({
    registrar: "CAMS",
    fileType: "DBF",
    filename: "cams-alias.dbf",
    bytes: createSyntheticDbf([{
      INV_PAN: "ABCDE1234F",
      INV_NAME: "Issue Investor",
      FOLIOCHK: "FOLIO1001",
      PRODCODE: "CAMS001",
      SCHEME_NAME: "CAMS Equity Fund",
      AMC_NAME: "CAMS AMC",
      SCHEME_CAT: "Equity",
      TRXN_TYPE: "PURCHASE",
      TRXN_UNITS: "3.0000",
      TRXN_AMOUNT: "33.00",
      PURPRICE: "11.0000",
      TRXN_DATE: "20260729",
      TRXNNO: "CAMS-ALIAS-1",
    }], [
      { name: "INV_PAN", type: "C", length: 10 },
      { name: "INV_NAME", type: "C", length: 24 },
      { name: "FOLIOCHK", type: "C", length: 16 },
      { name: "PRODCODE", type: "C", length: 12 },
      { name: "SCHEME_NAME", type: "C", length: 32 },
      { name: "AMC_NAME", type: "C", length: 28 },
      { name: "SCHEME_CAT", type: "C", length: 18 },
      { name: "TRXN_TYPE", type: "C", length: 22 },
      { name: "TRXN_UNITS", type: "N", length: 14 },
      { name: "PURPRICE", type: "N", length: 12 },
      { name: "TRXN_AMOUNT", type: "N", length: 14 },
      { name: "TRXN_DATE", type: "C", length: 8 },
      { name: "TRXNNO", type: "C", length: 16 },
    ]),
  });
  const kfintechRows = await new KfintechParser().parse({
    registrar: "KFINTECH",
    fileType: "DBF",
    filename: "kfintech-alias.dbf",
    bytes: createSyntheticDbf([{
      IHNO: "FGHIJ5678K",
      NAME: "KFin Investor",
      FOLIO: "KFOLIO1001",
      SCH_CODE: "KFIN001",
      SCH_NAME: "KFin Debt Fund",
      FUND_HOUSE: "KFin AMC",
      CATEGORY: "Debt",
      TRTYPE: "R",
      TR_UNITS: "-3.0000",
      TR_AMT: "-33.00",
      PRICE: "11.0000",
      TR_DATE: "20260729",
      TRNO: "KFIN-ALIAS-1",
    }], [
      { name: "IHNO", type: "C", length: 10 },
      { name: "NAME", type: "C", length: 24 },
      { name: "FOLIO", type: "C", length: 16 },
      { name: "SCH_CODE", type: "C", length: 12 },
      { name: "SCH_NAME", type: "C", length: 32 },
      { name: "FUND_HOUSE", type: "C", length: 28 },
      { name: "CATEGORY", type: "C", length: 18 },
      { name: "TRTYPE", type: "C", length: 22 },
      { name: "TR_UNITS", type: "N", length: 14 },
      { name: "PRICE", type: "N", length: 12 },
      { name: "TR_AMT", type: "N", length: 14 },
      { name: "TR_DATE", type: "C", length: 8 },
      { name: "TRNO", type: "C", length: 16 },
    ]),
  });

  assertEquals(camsRows[0].registrarTransactionId, "CAMS-ALIAS-1");
  assertEquals(kfintechRows[0].registrarTransactionId, "KFIN-ALIAS-1");
});

Deno.test("duplicate source row fixtures preserve row numbers for persistence validation", async () => {
  const rows = await new CamsParser().parse({
    registrar: "CAMS",
    fileType: "DBF",
    filename: "multi.dbf",
    bytes: camsDbfFixtureWithRows([
      { TRX_ID: "ROW-1" },
      { FOLIO_NO: "FOLIO2002", TRX_ID: "ROW-2" },
    ]),
  });
  assertEquals(rows.map((row) => row.sourceRowNumber), [1, 2]);
});

Deno.test("malformed numeric fields fail closed", async () => {
  const parser = new CamsParser();
  await assertRejects(
    () =>
      parser.parse({
        registrar: "CAMS",
        fileType: "DBF",
        filename: "bad.dbf",
        bytes: camsDbfFixture({ AMOUNT: "not-number" }),
      }),
    Error,
    "parse_failed",
  );
});

Deno.test("unsupported registrar is rejected by parser registry", async () => {
  const registry = new ParserRegistry([new CamsParser()]);
  await assertRejects(
    () =>
      registry.parse({
        registrar: "KFINTECH",
        fileType: "DBF",
        filename: "kfintech.dbf",
        bytes: kfintechDbfFixture(),
      }),
    Error,
    "unsupported_registrar",
  );
});
