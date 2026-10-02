import { createNseMasterEvidenceStore } from "../_shared/nse/nse_master_evidence.ts";
import {
  NSE_MASTER_FILE_TYPES,
  type NseMasterFileType,
} from "../_shared/nse/nse_master_download.ts";
import type { MasterPersistence } from "./types.ts";

type RpcClient = {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<{
    data: unknown;
    error: unknown;
  }>;
};
export const masterUuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("nse_reference_ack_invalid");
  }
  return value as Record<string, unknown>;
}
function id(value: unknown): string {
  if (typeof value !== "string" || !masterUuid.test(value)) {
    throw new Error("nse_reference_ack_invalid");
  }
  return value;
}
export function createMasterPersistence(client: RpcClient): MasterPersistence {
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await client.rpc(name, args);
    if (error) throw new Error("nse_reference_persistence_failed");
    return record(data);
  };
  return {
    async claim(eventId, token) {
      const result = await rpc("claim_nse_master_download", {
        p_event_outbox_id: eventId,
        p_claim_token: token,
      });
      if (result.action === "DONE" || result.action === "BUSY") {
        return { action: result.action };
      }
      if (
        (result.action !== "CAPTURE" && result.action !== "FINALIZE") ||
        result.event_outbox_id !== eventId || result.environment !== "UAT" ||
        !NSE_MASTER_FILE_TYPES.includes(result.file_type as NseMasterFileType)
      ) throw new Error("nse_reference_ack_invalid");
      return {
        action: result.action,
        eventId,
        scope: {
          workspaceId: id(result.workspace_id),
          connectionId: id(result.connection_id),
          callId: id(result.download_id),
          environment: "UAT",
          fileType: result.file_type as NseMasterFileType,
        },
      };
    },
    evidence(eventId, token) {
      // Keep B06.1 serialization and capture unchanged. The job wrappers derive
      // every scope identifier from SQL and fence each write with the lease.
      const routes: Record<string, string> = {
        begin_nse_master_download: "begin_nse_master_job_capture",
        append_nse_master_chunk: "append_nse_master_job_chunk",
        finish_nse_master_download: "finish_nse_master_job_capture",
      };
      return createNseMasterEvidenceStore({
        rpc(name, args) {
          if (!routes[name]) throw new Error("nse_reference_rpc_invalid");
          const parameters = { ...args };
          for (
            const key of [
              "p_workspace_id",
              "p_connection_id",
              "p_download_id",
              "p_call_id",
              "p_file_type",
            ]
          ) delete parameters[key];
          return client.rpc(routes[name], {
            ...parameters,
            p_event_outbox_id: eventId,
            p_claim_token: token,
          });
        },
      });
    },
    async finalize(eventId, token) {
      const result = await rpc("finalize_nse_master_download", {
        p_event_outbox_id: eventId,
        p_claim_token: token,
      });
      const outcome = result.outcome;
      if (
        outcome !== "STAGED_VALIDATED" && outcome !== "REJECTED" &&
        outcome !== "CAPTURE_FAILED" && outcome !== "ABANDONED"
      ) throw new Error("nse_reference_ack_invalid");
      const staged = outcome === "STAGED_VALIDATED" || outcome === "REJECTED";
      if (!staged && result.snapshot_id !== null) {
        throw new Error("nse_reference_ack_invalid");
      }
      return {
        outcome,
        snapshot_id: staged ? id(result.snapshot_id) : null,
      };
    },
  };
}
