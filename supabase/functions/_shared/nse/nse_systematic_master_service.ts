import {
  NSE_MASTER_CHUNK_BYTES,
  NSE_MASTER_MAX_BYTES,
  NseMasterError,
  nseMasterSha256,
} from "./nse_master_download.ts";
import {
  NSE_SYSTEMATIC_PARSER_VERSION,
  type NseParsedSystematicMaster,
  type NseSystematicVariant,
  parseNseSystematicMaster,
} from "./nse_systematic_masters.ts";

type RpcClient = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
};
export type NseSystematicSnapshotScope = Readonly<{
  workspaceId: string;
  connectionId: string;
  snapshotId: string;
  fileType: NseSystematicVariant;
}>;
export type NseSystematicValidation = Readonly<{
  scope: NseSystematicSnapshotScope;
  downloadId: string;
  version: number;
  parsed: NseParsedSystematicMaster;
}>;
function invalid(): never {
  throw new NseMasterError("nse_systematic_manifest_mismatch");
}
function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalid();
  }
  return value as Record<string, unknown>;
}
function positiveInteger(value: unknown, max: number): number {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) || value < 1 ||
    value > max
  ) return invalid();
  return value;
}
function identifier(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      value,
    )
  ) return invalid();
  return value;
}
/** B06.2 wiring seam: only stored evidence/RPCs; no HTTP worker, event or route. */
export function createNseSystematicMasterService(client: RpcClient) {
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await client.rpc(name, args);
    if (error) throw new NseMasterError("nse_systematic_persistence_failed");
    return object(data);
  };
  const validate = async (
    input: NseSystematicSnapshotScope,
  ): Promise<NseSystematicValidation> => {
    const scope = Object.freeze({ ...input });
    identifier(scope.workspaceId);
    identifier(scope.connectionId);
    identifier(scope.snapshotId);
    if (!["SIP", "STP", "SWP"].includes(scope.fileType)) return invalid();
    const args = {
      p_workspace_id: scope.workspaceId,
      p_snapshot_id: scope.snapshotId,
    };
    const manifest = await rpc("get_nse_reference_snapshot", args);
    if (
      manifest.snapshot_id !== scope.snapshotId ||
      manifest.workspace_id !== scope.workspaceId ||
      manifest.connection_id !== scope.connectionId ||
      manifest.file_type !== scope.fileType ||
      manifest.stage !== "STAGED_UNVALIDATED"
    ) return invalid();
    const version = positiveInteger(manifest.version, Number.MAX_SAFE_INTEGER);
    const downloadId = identifier(manifest.download_id);
    const length = positiveInteger(
      manifest.response_bytes,
      NSE_MASTER_MAX_BYTES,
    );
    const count = positiveInteger(manifest.chunk_count, 64);
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (let ordinal = 0; ordinal < count; ordinal++) {
      const chunk = await rpc("read_nse_master_chunk", {
        p_workspace_id: scope.workspaceId,
        p_download_id: downloadId,
        p_ordinal: ordinal,
      });
      const chunkLength = positiveInteger(
        chunk.byte_count,
        NSE_MASTER_CHUNK_BYTES,
      );
      if (
        typeof chunk.base64 !== "string" || chunk.base64.length > 349528 ||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(chunk.base64) ||
        offset + chunkLength > length
      ) return invalid();
      let binary: string;
      try {
        binary = atob(chunk.base64);
      } catch {
        return invalid();
      }
      if (binary.length !== chunkLength) return invalid();
      const part = Uint8Array.from(binary, (c) => c.charCodeAt(0));
      if (await nseMasterSha256(part) !== chunk.sha256) return invalid();
      bytes.set(part, offset);
      offset += part.length;
    }
    if (
      offset !== length ||
      await nseMasterSha256(bytes) !== manifest.response_sha256
    ) return invalid();
    const parsed = await parseNseSystematicMaster(scope.fileType, bytes);
    const receipt = await rpc("validate_nse_systematic_snapshot", args);
    checkReceipt(receipt, scope, parsed, version, downloadId);
    return Object.freeze({ scope, downloadId, version, parsed });
  };
  return Object.freeze({
    validate,
    async publish(
      scope: NseSystematicSnapshotScope,
      expectedCurrentSnapshotId: string | null,
    ) {
      if (expectedCurrentSnapshotId !== null) {
        identifier(expectedCurrentSnapshotId);
      }
      const validated = await validate(scope);
      const receipt = await rpc("publish_nse_systematic_snapshot", {
        p_workspace_id: validated.scope.workspaceId,
        p_snapshot_id: validated.scope.snapshotId,
        p_expected_current_snapshot_id: expectedCurrentSnapshotId,
      });
      checkReceipt(
        receipt,
        validated.scope,
        validated.parsed,
        validated.version,
        validated.downloadId,
      );
      if (typeof receipt.is_current !== "boolean") return invalid();
      return Object.freeze({ ...validated, isCurrent: receipt.is_current });
    },
  });
}
function checkReceipt(
  receipt: Record<string, unknown>,
  scope: NseSystematicSnapshotScope,
  parsed: NseParsedSystematicMaster,
  version: number,
  downloadId: string,
) {
  if (
    receipt.snapshot_id !== scope.snapshotId ||
    receipt.workspace_id !== scope.workspaceId ||
    receipt.connection_id !== scope.connectionId ||
    receipt.file_type !== scope.fileType ||
    receipt.parser_version !== NSE_SYSTEMATIC_PARSER_VERSION ||
    receipt.layout_id !== parsed.layoutId ||
    receipt.source_sha256 !== parsed.sourceSha256 ||
    receipt.source_bytes !== parsed.sourceBytes ||
    receipt.row_count !== parsed.rows.length || receipt.rejected_rows !== 0 ||
    receipt.authority !== "REFERENCE_ONLY" ||
    receipt.version !== version || receipt.download_id !== downloadId
  ) invalid();
}
