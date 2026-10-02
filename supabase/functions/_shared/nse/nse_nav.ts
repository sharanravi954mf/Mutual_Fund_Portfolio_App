import { NseMasterError } from "./nse_master_download.ts";

export const NSE_NAV_PARSER = "NSE_NAV_WEB83_V1";
export const NSE_NAV_LAYOUT_SHA256 =
  "67ee2e34c7cf776a2731e950837bd3aa6f2e6f7e5f521cbdbbce5cc60aae307d";
export const NSE_NAV_PUBLICATION = "BLOCKED_CROSSWALK_AND_SOURCE_POLICY";

export type NseNavScope = Readonly<{
  workspaceId: string;
  snapshotId: string;
}>;
export type NseNavValidation = Readonly<
  & {
    snapshot_id: string;
    workspace_id: string;
    connection_id: string;
    download_id: string;
    snapshot_version: string;
    parser_version: typeof NSE_NAV_PARSER;
    source_sha256: string;
    layout_sha256: typeof NSE_NAV_LAYOUT_SHA256;
    api_compatibility: "UNCOMMISSIONED";
    publication_state: typeof NSE_NAV_PUBLICATION;
  }
  & (
    | {
      status: "VALIDATED_OBSERVATIONS";
      row_count: number;
      rejection_code: null;
      rejected_line: null;
    }
    | {
      status: "REJECTED";
      row_count: 0;
      rejection_code: string;
      rejected_line: number | null;
    }
  )
>;
/** Exchange identity only. No MoneyBowl fund identity or valuation authority. */
export type NseNavObservation = Readonly<{
  line_number: number;
  nav_date: string;
  nse_scheme_code: string;
  scheme_name: string;
  rta_scheme_code: string;
  dividend_reinvestment: "Y" | "N" | "Z";
  isin: string;
  // Exact positive decimal lexeme, never a binary floating-point conversion.
  nav_value: string;
  rta_code: string;
}>;
export type NseNavPage = Readonly<{
  snapshot_id: string;
  parser_version: typeof NSE_NAV_PARSER;
  source_sha256: string;
  row_count: number;
  publication_state: typeof NSE_NAV_PUBLICATION;
  observations: readonly NseNavObservation[];
  next_after_line: number | null;
}>;
type RpcClient = {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<
    { data: unknown; error: unknown }
  >;
};
const rejections = [
  "nse_nav_encoding_invalid",
  "nse_nav_framing_invalid",
  "nse_nav_column_count",
  "nse_nav_field_invalid",
  "nse_nav_date_invalid",
  "nse_nav_value_invalid",
  "nse_nav_duplicate_identity",
];
function fail(): never {
  throw new NseMasterError("nse_nav_response_invalid");
}
function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail();
  return value as Record<string, unknown>;
}
function integer(value: unknown, minimum: number): value is number {
  return Number.isSafeInteger(value) && (value as number) >= minimum;
}
function text(value: unknown, max: number): value is string {
  return typeof value === "string" && value.length > 0 &&
    [...value].length <= max && value.trim() === value &&
    !/[\x00-\x1f\x7f|\ufeff]/.test(value);
}
function uuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      value,
    );
}
function digest(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}
function validation(value: unknown, scope: NseNavScope): NseNavValidation {
  const v = record(value);
  if (
    v.snapshot_id !== scope.snapshotId ||
    v.workspace_id !== scope.workspaceId ||
    !uuid(v.snapshot_id) || !uuid(v.workspace_id) || !uuid(v.connection_id) ||
    !uuid(v.download_id) || typeof v.snapshot_version !== "string" ||
    !/^[1-9][0-9]*$/.test(v.snapshot_version) ||
    v.parser_version !== NSE_NAV_PARSER || !digest(v.source_sha256) ||
    v.layout_sha256 !== NSE_NAV_LAYOUT_SHA256 ||
    v.api_compatibility !== "UNCOMMISSIONED" ||
    v.publication_state !== NSE_NAV_PUBLICATION
  ) fail();
  if (v.status === "VALIDATED_OBSERVATIONS") {
    if (
      !integer(v.row_count, 1) || v.rejection_code !== null ||
      v.rejected_line !== null
    ) fail();
  } else if (v.status === "REJECTED") {
    if (
      v.row_count !== 0 || !rejections.includes(v.rejection_code as string) ||
      !(v.rejected_line === null || integer(v.rejected_line, 1))
    ) fail();
  } else fail();
  return Object.freeze(v) as NseNavValidation;
}
function observation(value: unknown, expectedLine: number): NseNavObservation {
  const o = record(value);
  if (
    o.line_number !== expectedLine || typeof o.nav_date !== "string" ||
    !/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(o.nav_date) ||
    !text(o.nse_scheme_code, 30) || !text(o.scheme_name, 200) ||
    !text(o.rta_scheme_code, 10) ||
    !["Y", "N", "Z"].includes(o.dividend_reinvestment as string) ||
    typeof o.isin !== "string" || !/^[A-Z]{2}[A-Z0-9]{9}[0-9]$/.test(o.isin) ||
    typeof o.nav_value !== "string" || o.nav_value.length > 14 ||
    !/^(0|[1-9][0-9]*)(\.[0-9]+)?$/.test(o.nav_value) ||
    !/[1-9]/.test(o.nav_value) || !text(o.rta_code, 10)
  ) fail();
  const date = new Date(o.nav_date + "T00:00:00Z");
  if (
    !Number.isFinite(date.getTime()) ||
    date.toISOString().slice(0, 10) !== o.nav_date
  ) fail();
  return Object.freeze(o) as NseNavObservation;
}

/** B06.2 calls this after staging. SQL is the sole parser of encrypted evidence.
 * No HTTP, outbox, route, crosswalk inference or current_nav write occurs here.
 */
export function createNseNavService(client: RpcClient) {
  async function rpc(name: string, args: Record<string, unknown>) {
    try {
      const result = await client.rpc(name, args);
      if (result.error) throw new Error();
      return result.data;
    } catch {
      throw new NseMasterError("nse_nav_persistence_failed");
    }
  }
  return {
    async validate(scope: NseNavScope): Promise<NseNavValidation> {
      return validation(
        await rpc("validate_nse_nav_snapshot", {
          p_workspace_id: scope.workspaceId,
          p_snapshot_id: scope.snapshotId,
        }),
        scope,
      );
    },
    async readPage(
      receipt: NseNavValidation,
      afterLine = 0,
      limit = 500,
    ): Promise<NseNavPage> {
      validation(receipt, {
        workspaceId: receipt.workspace_id,
        snapshotId: receipt.snapshot_id,
      });
      if (receipt.status !== "VALIDATED_OBSERVATIONS") fail();
      if (
        !integer(afterLine, 0) || afterLine > receipt.row_count ||
        !integer(limit, 1) || limit > 1000
      ) fail();
      const data = record(
        await rpc("read_nse_nav_observations", {
          p_workspace_id: receipt.workspace_id,
          p_snapshot_id: receipt.snapshot_id,
          p_after_line: afterLine,
          p_limit: limit,
        }),
      );
      const expectedCount = Math.min(limit, receipt.row_count - afterLine);
      const next = afterLine + expectedCount < receipt.row_count
        ? afterLine + expectedCount
        : null;
      if (
        data.snapshot_id !== receipt.snapshot_id ||
        data.parser_version !== receipt.parser_version ||
        data.source_sha256 !== receipt.source_sha256 ||
        data.row_count !== receipt.row_count ||
        data.publication_state !== NSE_NAV_PUBLICATION ||
        data.next_after_line !== next ||
        !Array.isArray(data.observations) ||
        data.observations.length !== expectedCount
      ) fail();
      const observations = Object.freeze(
        data.observations.map((o, i) => observation(o, afterLine + i + 1)),
      );
      return Object.freeze({ ...data, observations }) as NseNavPage;
    },
  };
}
