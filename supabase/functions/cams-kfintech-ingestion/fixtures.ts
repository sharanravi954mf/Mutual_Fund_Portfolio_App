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

export function kfintechDbfFixture(
  overrides: Record<string, string> = {},
): Uint8Array {
  return createSyntheticDbf([{
    PAN: "FGHIJ5678K",
    INV_NAME: "KFin Investor",
    FOLIO_NO: "KFOLIO1001",
    SCHEME_CD: "KFIN001",
    SCHEME_NM: "KFin Debt Fund",
    FUND_HOUSE: "KFin AMC",
    CATEGORY: "Debt",
    TRX_TYPE: "SELL",
    UNITS: "5.0000",
    NAV: "10.0000",
    AMOUNT: "50.00",
    TRX_DATE: "20260729",
    ...overrides,
  }]);
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
