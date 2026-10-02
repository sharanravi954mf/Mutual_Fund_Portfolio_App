import type { NseMasterEvidenceStore } from "./nse_master_download.ts";
import { NseMasterError } from "./nse_master_download.ts";

type RpcClient = {
  rpc(
    name: string,
    args: Record<string, unknown>,
  ): PromiseLike<{ data: unknown; error: unknown }>;
};
function base64(bytes: Uint8Array): string {
  let text = "";
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    text += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return btoa(text);
}
/** No secrets, raw headers, provider URLs in metadata, or generic JSON payloads. */
export function createNseMasterEvidenceStore(
  client: RpcClient,
): NseMasterEvidenceStore {
  const rpc = async (name: string, args: Record<string, unknown>) => {
    const { data, error } = await client.rpc(name, args);
    if (error) throw new NseMasterError("nse_reference_persistence_failed");
    return data;
  };
  return {
    async begin(scope, binding) {
      const data = await rpc("begin_nse_master_download", {
        p_workspace_id: scope.workspaceId,
        p_connection_id: scope.connectionId,
        p_file_type: scope.fileType,
        p_call_id: scope.callId,
        p_capture_token: binding.captureToken,
        p_environment: scope.environment,
        p_member_code: binding.memberCode,
        p_api_base_url: binding.baseUrl,
      });
      if (
        data === null || typeof data !== "object" || !("download_id" in data) ||
        !("request_body" in data) ||
        typeof data.download_id !== "string" ||
        typeof data.request_body !== "string"
      ) throw new NseMasterError("nse_reference_request_mismatch");
      return { download_id: data.download_id, request_body: data.request_body };
    },
    async append(scope, ordinal, bytes, sha256) {
      await rpc("append_nse_master_chunk", {
        p_workspace_id: scope.workspaceId,
        p_download_id: scope.callId,
        p_ordinal: ordinal,
        p_base64: base64(bytes),
        p_sha256: sha256,
      });
    },
    async finish(scope, capture) {
      await rpc("finish_nse_master_download", {
        p_workspace_id: scope.workspaceId,
        p_download_id: scope.callId,
        p_capture_kind: capture.kind,
        p_http_status: capture.httpStatus,
        p_media_type: capture.mediaType,
        p_declared_bytes: capture.declaredBytes,
        p_identity_encoding: capture.identityEncoding,
        p_eof: capture.eof,
        p_sha256: capture.sha256,
      });
    },
  };
}
