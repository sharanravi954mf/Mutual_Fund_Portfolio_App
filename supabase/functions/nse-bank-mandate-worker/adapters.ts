import { assertNseUatWorkflow } from "../_shared/nse/nse_runtime.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { NseClient, NseClientError } from "../_shared/nse/nse_client.ts";
import type { NseConfig } from "../_shared/nse/nse_types.ts";
import {
  type Persistence,
  type Result,
  serializeRequest,
  type Source,
} from "./handler.ts";
export function persistence(client: SupabaseClient): Persistence {
  async function rpc(name: string, args: Record<string, unknown>) {
    const { data, error } = await client.rpc(name, args);
    if (error) throw new Error("b07_persistence_failed");
    return data;
  }
  return {
    claim: (id) => rpc("claim_nse_bank_mandate_write", { p_event_id: id }),
    source: (id) =>
      rpc("get_nse_bank_mandate_write_source", { p_operation_id: id }),
    start: ({ event, call, body, started }) =>
      rpc("start_nse_bank_mandate_write", {
        p_event_id: event.event_id,
        p_claim_token: event.claim_token,
        p_call_id: call,
        p_request: body,
        p_headers: {
          content_type: "application/json",
          accept: "application/json",
        },
        p_started_at: started,
      }),
    finish: ({ event, call, result, completed }) =>
      rpc("finish_nse_bank_mandate_write", {
        p_event_id: event.event_id,
        p_claim_token: event.claim_token,
        p_call_id: call,
        p_response_base64: result.bodyBase64,
        p_http_status: result.httpStatus,
        p_headers: result.headers,
        p_delivery: result.delivery,
        p_completed_at: completed,
      }),
    reconcile: (id) =>
      rpc("reconcile_nse_bank_mandate_write", { p_verification_id: id }),
  };
}
export function gateway(config: NseConfig, fetcher: typeof fetch = fetch) {
  assertNseUatWorkflow(config);
  // This candidate has no Production transport capability or redirect allowance.
  if (config.baseUrl !== "https://nseinvestuat.nseindia.com") {
    throw new Error("b07_uat_configuration_required");
  }
  const client = new NseClient(
    config,
    (url, init) => fetcher(url, { ...init, redirect: "error" }),
  );
  return async (body: string, source: Source): Promise<Result> => {
    try {
      if (body !== serializeRequest(source)) {
        return {
          delivery: "PROVEN_NOT_SENT",
          bodyBase64: "",
          httpStatus: null,
          headers: {},
        };
      }
      const r = await client.request({
        method: "POST",
        path: source.path,
        bodyText: body,
        contentType: "application/json",
        accept: "application/json",
        timeoutMs: 30000,
        maxResponseBytes: 1048576,
        acceptHttpErrors: true,
      });
      let binary = "";
      for (let n = 0; n < r.body.length; n += 32768) {
        binary += String.fromCharCode(...r.body.subarray(n, n + 32768));
      }
      return {
        delivery: "SENT_WITH_RESULT",
        bodyBase64: btoa(binary),
        httpStatus: r.status,
        headers: r.safeHeaderMetadata as Record<string, string>,
      };
    } catch (error) {
      return {
        delivery: error instanceof NseClientError &&
            error.code === "nse_request_invalid"
          ? "PROVEN_NOT_SENT"
          : "MAYBE_SENT",
        bodyBase64: "",
        httpStatus: null,
        headers: {},
      };
    }
  };
}
