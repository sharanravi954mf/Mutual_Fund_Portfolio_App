import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { CamsParser, KfintechParser, ParserRegistry } from "./parser.ts";
import {
  camsDbfFixture,
  kfintechDbfFixture,
  syntheticCasPdfFixture,
} from "./fixtures.ts";

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
});

Deno.test("CAS PDF fixture uses Edge-compatible text extractor", async () => {
  const parser = new CamsParser({
    extractText: () =>
      Promise.resolve(
        new TextDecoder().decode(syntheticCasPdfFixture()).replace(
          "%PDF-1.7\n",
          "",
        ).replace("\n%%EOF", ""),
      ),
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
