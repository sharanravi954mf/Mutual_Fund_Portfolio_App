import { createSyntheticDbf } from "./parser.ts";

const encoder = new TextEncoder();

export function streamFromBytes(bytes: Uint8Array): ReadableStream<Uint8Array> {
  return new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(bytes);
      controller.close();
    },
  });
}

export function chunkedStream(
  chunkCount: number,
  chunkSize: number,
  onPull?: (count: number) => void,
): ReadableStream<Uint8Array> {
  let emitted = 0;
  return new ReadableStream<Uint8Array>({
    pull(controller) {
      emitted += 1;
      onPull?.(emitted);
      controller.enqueue(new Uint8Array(chunkSize).fill(0x41));
      if (emitted >= chunkCount) {
        controller.close();
      }
    },
  });
}

export function camsDbfFixture(
  overrides: Record<string, string> = {},
): Uint8Array {
  return createSyntheticDbf([{
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
    ...overrides,
  }]);
}

export function camsDbfFixtureWithRows(
  records: Record<string, string>[],
): Uint8Array {
  return createSyntheticDbf(records.map((record) => ({
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
    ...record,
  })));
}

export function genuineCamsDbfFixture(
  overrides: Record<string, string> = {},
): Uint8Array {
  return createSyntheticDbf([{
    PAN: "ABCDE1234F",
    INV_NAME: "Synthetic Investor",
    FOLIO_NO: "SYNTHFOLIO1",
    PRODCODE: "SYNTH001",
    TRXN_TYPE_: "Additional Purchase",
    UNITS: "12.5000",
    AMOUNT: "250.00",
    PURPRICE: "20.0000",
    POSTDATE: "20260729",
    ...overrides,
  }], [
    { name: "TRXN_TYPE_", type: "C", length: 32 },
    { name: "UNITS", type: "N", length: 14 },
    { name: "AMOUNT", type: "N", length: 14 },
    { name: "PURPRICE", type: "N", length: 12 },
    { name: "POSTDATE", type: "D", length: 8 },
    { name: "PAN", type: "C", length: 10 },
    { name: "FOLIO_NO", type: "C", length: 16 },
    { name: "PRODCODE", type: "C", length: 12 },
    { name: "INV_NAME", type: "C", length: 24 },
  ]);
}

export function kfintechDbfFixture(
  overrides: Record<string, string> = {},
): Uint8Array {
  return createSyntheticDbf([{
    PAN1: "FGHIJ5678K",
    INVNAME: "KFin Investor",
    ACNO: "KFOLIO1001",
    FUNDCODE: "KFIN001",
    FUND_DESC: "KFin Debt Fund",
    AMC_CODE: "KFin AMC",
    ASSETTYPE: "Debt",
    TD_TRTYPE: "R",
    TD_UNITS: "-5.0000",
    TD_NAV: "10.0000",
    TD_AMT: "-50.00",
    TD_TRDATE: "20260729",
    TD_TRNO: "KFIN-TXN-1",
    ...overrides,
  }], [
    { name: "PAN1", type: "C", length: 10 },
    { name: "INVNAME", type: "C", length: 24 },
    { name: "ACNO", type: "C", length: 16 },
    { name: "FUNDCODE", type: "C", length: 12 },
    { name: "FUND_DESC", type: "C", length: 32 },
    { name: "AMC_CODE", type: "C", length: 28 },
    { name: "ASSETTYPE", type: "C", length: 18 },
    { name: "TD_TRTYPE", type: "C", length: 22 },
    { name: "TD_UNITS", type: "N", length: 14 },
    { name: "TD_NAV", type: "N", length: 12 },
    { name: "TD_AMT", type: "N", length: 14 },
    { name: "TD_TRDATE", type: "C", length: 8 },
    { name: "TD_TRNO", type: "C", length: 16 },
  ]);
}

export function syntheticCasPdfFixture(): Uint8Array {
  return encoder.encode(`%PDF-1.7
PAN,INV_NAME,FOLIO_NO,SCHEME_CD,SCHEME_NM,FUND_HOUSE,CATEGORY,TRX_TYPE,UNITS,NAV,AMOUNT,TRX_DATE
ABCDE1234F,Issue Investor,FOLIO1001,CAMS001,CAMS Equity Fund,CAMS AMC,Equity,BUY,12.5000,20.0000,250.00,20260729
%%EOF`);
}

export const workspaceId = "aaaaaaaa-0000-4000-8000-000000000001";
export const mailboxConnectionId = "aaaaaaaa-0000-4000-8000-000000000002";
export const correlationId = "aaaaaaaa-0000-4000-8000-000000000003";
