import { NseMasterError } from "./nse_master_download.ts";

export type NseSetAssessment = Readonly<{
  snapshot_id: string;
  workspace_id: string;
  connection_id: string;
  download_id: string;
  snapshot_version: string;
  source_sha256: string;
  assessment_version: "NSE_SET_EVIDENCE_V1";
  status: "BLOCKED_LAYOUT_UNCHARACTERIZED";
  reason_code: "WEB77_API_COMPATIBILITY_AND_HEADER_UNCONFIRMED";
}>;
type RpcClient = {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<
    { data: unknown; error: unknown }
  >;
};
/** Separate SET evidence seam. It deliberately exposes no calendar row type or publisher. */
export function createNseSetService(client: RpcClient) {
  return {
    async assess(
      scope: { workspaceId: string; snapshotId: string },
    ): Promise<NseSetAssessment> {
      let data: unknown;
      try {
        const response = await client.rpc("assess_nse_set_snapshot", {
          p_workspace_id: scope.workspaceId,
          p_snapshot_id: scope.snapshotId,
        });
        if (response.error) throw new Error();
        data = response.data;
      } catch {
        throw new NseMasterError("nse_set_persistence_failed");
      }
      if (!data || typeof data !== "object" || Array.isArray(data)) {
        throw new NseMasterError("nse_set_response_invalid");
      }
      const a = data as Record<string, unknown>;
      if (
        a.snapshot_id !== scope.snapshotId ||
        a.workspace_id !== scope.workspaceId ||
        ![a.snapshot_id, a.workspace_id, a.connection_id, a.download_id].every((
          id,
        ) =>
          typeof id === "string" &&
          /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
            id,
          )
        ) || typeof a.snapshot_version !== "string" ||
        !/^[1-9][0-9]*$/.test(a.snapshot_version) ||
        typeof a.source_sha256 !== "string" ||
        !/^[0-9a-f]{64}$/.test(a.source_sha256) ||
        a.assessment_version !== "NSE_SET_EVIDENCE_V1" ||
        a.status !== "BLOCKED_LAYOUT_UNCHARACTERIZED" ||
        a.reason_code !== "WEB77_API_COMPATIBILITY_AND_HEADER_UNCONFIRMED"
      ) throw new NseMasterError("nse_set_response_invalid");
      return Object.freeze(a) as NseSetAssessment;
    },
  };
}
