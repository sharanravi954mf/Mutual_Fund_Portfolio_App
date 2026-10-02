import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  NSE_MASTER_MAX_BYTES,
  NseMasterError,
  nseMasterSha256,
} from "./nse_master_download.ts";
import {
  type NseSystematicVariant,
  parseNseSipMaster,
  parseNseStpMaster,
  parseNseSwpMaster,
  parseNseSystematicMaster,
} from "./nse_systematic_masters.ts";
import {
  SIP_CELLS,
  SIP_HEADER,
  STP_CELLS,
  STP_HEADER,
  SWP_CELLS,
  SWP_HEADER,
} from "./nse_systematic_masters_fixtures.ts";
const encode = (s: string) => new TextEncoder().encode(s);
const fixtures = [
  ["SIP", SIP_HEADER, SIP_CELLS],
  ["STP", STP_HEADER, STP_CELLS],
  ["SWP", SWP_HEADER, SWP_CELLS],
] as const;
for (const [kind, header, cells] of fixtures) {
  Deno.test(`${kind} documented profile preserves typed source values and immutable exact lineage`, async () => {
    const body = `\ufeff${header}\r\n${cells.join("|")}\r\n`;
    const result = await parseNseSystematicMaster(kind, encode(body));
    assertEquals(result.fileType, kind);
    assertEquals(result.authority, "REFERENCE_ONLY");
    assertEquals(result.sourceSha256, await nseMasterSha256(encode(body)));
    assertEquals(result.rows.length, 1);
    assertEquals(result.rows[0].sourceLine, 2);
    assertEquals(
      result.rows[0].sourceRowSha256,
      await nseMasterSha256(encode(cells.join("|"))),
    );
    assertEquals(result.rows[0].schemeCode, "NSE_TEST_001");
    assert(Object.isFrozen(result));
    assert(Object.isFrozen(result.rows));
    assert(Object.isFrozen(result.rows[0]));
  });
  const malformed: [string, string][] = [
    [
      "header reorder",
      header.split("|").reverse().join("|") + "\n" + cells.join("|"),
    ],
    [
      "header alias",
      header.replace("AMC CODE", "AMC_CODE") + "\n" + cells.join("|"),
    ],
    ["header only", header + "\n"],
    ["missing column", header + "\n" + cells.slice(0, -1).join("|")],
    ["extra column", header + "\n" + cells.join("|") + "|"],
    ["duplicate row", header + "\n" + cells.join("|") + "\n" + cells.join("|")],
    ["blank row", header + "\n" + cells.join("|") + "\n\n"],
    ["interior BOM", header + "\n\ufeff" + cells.join("|")],
    ["bare CR", header + "\r" + cells.join("|")],
    [
      "tab",
      header + "\n" +
      cells.join("|").replace("Synthetic AMC", "Synthetic\tAMC"),
    ],
    ["JSON failure", '{"response_status":"F"}'],
    ["HTML", "<html>error|failure</html>"],
    [
      "empty name",
      header + "\n" + cells.map((v, i) => i === 1 ? "" : v).join("|"),
    ],
    [
      "leading space",
      header + "\n" + cells.map((v, i) => i === 2 ? " " + v : v).join("|"),
    ],
    [
      "oversize identity",
      header + "\n" +
      cells.map((v, i) => i === 2 ? "A".repeat(31) : v).join("|"),
    ],
  ];
  for (const [label, body] of malformed) {
    Deno.test(`${kind} rejects ${label}`, async () => {
      await assertRejects(
        () => parseNseSystematicMaster(kind, encode(body)),
        NseMasterError,
      );
    });
  }
  for (const [other, otherHeader, otherCells] of fixtures) {
    if (other !== kind) {
      Deno.test(`${kind} rejects ${other} layout`, async () => {
        await assertRejects(
          () =>
            parseNseSystematicMaster(
              kind,
              encode(otherHeader + "\n" + otherCells.join("|")),
            ),
          NseMasterError,
          "layout_unknown",
        );
      });
    }
  }
  const amountIndex = kind === "SIP" ? 11 : 7;
  for (
    const value of [
      "",
      "-1",
      "1e3",
      "1,000",
      "1.001",
      "10000000000",
      "NaN",
      "Infinity",
      "1.",
      " 1",
      "+1",
    ]
  ) {
    Deno.test(`${kind} rejects invalid amount ${JSON.stringify(value)}`, async () => {
      const changed = [...cells];
      changed[amountIndex] = value;
      await assertRejects(
        () =>
          parseNseSystematicMaster(
            kind,
            encode(header + "\n" + changed.join("|")),
          ),
        NseMasterError,
        "number_invalid",
      );
    });
  }
  Deno.test(`${kind} preserves multiple source rows for the same scheme without guessing identity`, async () => {
    const changed = [...cells];
    changed[kind === "SIP" ? 5 : kind === "STP" ? 20 : 15] = "WEEKLY";
    const result = await parseNseSystematicMaster(
      kind,
      encode(header + "\n" + cells.join("|") + "\n" + changed.join("|")),
    );
    assertEquals(result.rows.length, 2);
    assertEquals(result.rows[1].sourceLine, 3);
  });
}
Deno.test("SIP explicit reserved columns and unsupported pause fail closed", async () => {
  for (let i = 18; i < 27; i++) {
    const cells = [...SIP_CELLS];
    cells[i] = i === 18 ? "Y" : "1";
    await assertRejects(
      () => parseNseSipMaster(encode(SIP_HEADER + "\n" + cells.join("|"))),
      NseMasterError,
    );
  }
});
Deno.test("STP in/out amounts, registration codes and units remain distinct", async () => {
  const cells = [...STP_CELLS];
  cells[7] = "100";
  cells[10] = "200";
  cells[18] = "8";
  cells[19] = "9";
  const r =
    (await parseNseStpMaster(encode(STP_HEADER + "\n" + cells.join("|"))))
      .rows[0];
  assertEquals(r.inMinimumInstallmentAmount, "100.00");
  assertEquals(r.outMinimumInstallmentAmount, "200.00");
  assertEquals(r.registrationIn, 8);
  assertEquals(r.registrationOut, 9);
  cells[13] = "1.125";
  await assertRejects(
    () => parseNseStpMaster(encode(STP_HEADER + "\n" + cells.join("|"))),
    NseMasterError,
    "number_invalid",
  );
});
Deno.test("SWP supports three-place units without rounding", async () => {
  const r =
    (await parseNseSwpMaster(encode(SWP_HEADER + "\n" + SWP_CELLS.join("|"))))
      .rows[0];
  assertEquals(r.minimumInstallmentUnits, "100.125");
  assertEquals(r.minimumInstallmentAmount, "100.25");
});
Deno.test("file bytes are frozen before asynchronous digests", async () => {
  const bytes = encode(SIP_HEADER + "\n" + SIP_CELLS.join("|"));
  const expected = await nseMasterSha256(bytes);
  const pending = parseNseSipMaster(bytes);
  bytes.fill(0);
  assertEquals((await pending).sourceSha256, expected);
});
Deno.test("reject invalid UTF-8, oversize, unsupported variant and NUL", async () => {
  await assertRejects(
    () => parseNseSipMaster(new Uint8Array([0xff])),
    NseMasterError,
    "encoding_invalid",
  );
  await assertRejects(
    () => parseNseSipMaster(new Uint8Array(NSE_MASTER_MAX_BYTES + 1)),
    NseMasterError,
    "size_invalid",
  );
  await assertRejects(
    () =>
      parseNseSipMaster(encode(SIP_HEADER + "\n" + SIP_CELLS.join("|") + "\0")),
    NseMasterError,
    "framing_invalid",
  );
  // Invalid variants throw synchronously before there is a parser promise.
  try {
    parseNseSystematicMaster("SCH" as NseSystematicVariant, encode("a|b"));
    throw new Error("accepted");
  } catch (e) {
    assert(e instanceof NseMasterError);
  }
});
