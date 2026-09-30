import {
  buildNseOrderStatusRequest,
  NseOrderStatusValidationError,
  parseNseOrderStatusResponse,
} from "../_shared/nse/nse_order_status.ts";
import { createNseEvidenceCall } from "../_shared/nse/nse_evidence_call.ts";
import type { Claim } from "./adapters.ts";
type Persistence = {
  recoverExpired(max: number): Promise<void>;
  claim(id: string, max: number, lease: number): Promise<Claim>;
  source(id: string): Promise<unknown>;
  start(i: Record<string, unknown>): Promise<void>;
  finish(i: Record<string, unknown>): Promise<void>;
};
type Gateway = {
  headers(body: string): Record<string, string>;
  submit(body: string): Promise<any>;
};
export function createNseOrderStatusWorkerHandler(
  d: {
    internalToken: string;
    persistence: Persistence;
    gateway: Gateway;
    maxAttempts?: number;
    leaseSeconds?: number;
    now?: () => Date;
    uuid?: () => string;
  },
) {
  const now = d.now ?? (() => new Date()),
    uuid = d.uuid ?? (() => crypto.randomUUID()),
    max = d.maxAttempts ?? 3,
    lease = d.leaseSeconds ?? 120;
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { "content-type": "application/json" },
    });
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return new Response("ok");
    if (request.method !== "POST") {
      return json({ error: { code: "method_not_allowed" } }, 405);
    }
    if (
      request.headers.get("authorization") !== `Bearer ${d.internalToken}` ||
      !d.internalToken
    ) return json({ error: { code: "not_authorized" } }, 403);
    let body: any;
    try {
      body = await request.json();
    } catch {
      return json({ error: { code: "invalid_json" } }, 400);
    }
    const eventId = body?.event_outbox_id;
    if (typeof eventId !== "string") {
      return json({ error: { code: "event_outbox_id_required" } }, 400);
    }
    await d.persistence.recoverExpired(max);
    const event = await d.persistence.claim(eventId, max, lease);
    if (event.claim_state === "no_event" || !event.event_outbox_id) {
      return json({ data: { outcome: "no_event" } });
    }
    if (!event.integration_operation_id || !event.claim_token) {
      throw new Error("claim_shape_invalid");
    }
    let payload: string;
    try {
      payload = JSON.stringify(
        buildNseOrderStatusRequest(
          await d.persistence.source(event.integration_operation_id) as any,
        ),
      );
    } catch (error) {
      const code = error instanceof NseOrderStatusValidationError
        ? error.code
        : "order_status_source_invalid";
      return json({ error: { code } }, 422);
    }
    const callId = uuid(),
      started = now(),
      start = {
        p_event_outbox_id: event.event_outbox_id,
        p_claim_token: event.claim_token,
        p_call_id: callId,
        p_request_payload: payload,
        p_request_content_type: "application/json",
        p_request_header_metadata: d.gateway.headers(payload),
        p_started_at: started.toISOString(),
      };
    const evidence = createNseEvidenceCall(() => d.gateway.submit(payload));
    try {
      await evidence.persist(() => d.persistence.start(start));
    } catch {
      return json({ error: { code: "request_evidence_failed" } }, 500);
    }
    const response = await evidence.submit(),
      completed = now(),
      elapsed = Math.max(0, completed.getTime() - started.getTime());
    const finish = async (args: Record<string, unknown>) =>
      await evidence.persist(() =>
        d.persistence.finish({
          p_event_outbox_id: event.event_outbox_id,
          p_claim_token: event.claim_token,
          p_call_id: callId,
          p_completed_at: completed.toISOString(),
          p_elapsed_ms: elapsed,
          p_max_attempts: max,
          ...args,
        })
      );
    try {
      if (response.kind === "failure") {
        await finish({
          p_response_payload: "",
          p_response_content_type: null,
          p_response_header_metadata: {},
          p_http_status: null,
          p_native_status_value: null,
          p_observation_count: 0,
          p_invalid_observation_count: 0,
          p_normalized_outcome: "TRANSPORT_FAILURE",
          p_error_category: response.error,
          p_timeout_occurred: response.timeout,
          p_network_failure: response.network,
        });
        return json({
          error: { code: response.error },
          data: {
            outcome: event.attempt < max
              ? "safe_retry_available"
              : "submission_failed",
          },
        }, 503);
      }
      if (response.status < 200 || response.status > 299) {
        const retry = [408, 429, 500, 502, 503, 504].includes(response.status);
        await finish({
          p_response_payload: response.body,
          p_response_content_type: response.contentType,
          p_response_header_metadata: response.headers,
          p_http_status: response.status,
          p_native_status_value: null,
          p_observation_count: 0,
          p_invalid_observation_count: 0,
          p_normalized_outcome: retry ? "HTTP_RETRYABLE" : "HTTP_FAILURE",
          p_error_category: "nse_http_failure",
          p_timeout_occurred: false,
          p_network_failure: false,
        });
        return json({ error: { code: "nse_http_failure" } }, retry ? 503 : 502);
      }
      let parsed;
      try {
        parsed = parseNseOrderStatusResponse(response.body);
      } catch {
        await finish({
          p_response_payload: response.body,
          p_response_content_type: response.contentType,
          p_response_header_metadata: response.headers,
          p_http_status: response.status,
          p_native_status_value: null,
          p_observation_count: 0,
          p_invalid_observation_count: 0,
          p_normalized_outcome: "BUSINESS_FAILURE",
          p_error_category: "nse_response_contract_invalid",
          p_timeout_occurred: false,
          p_network_failure: false,
        });
        return json({ error: { code: "nse_response_contract_invalid" } }, 422);
      }
      const outcome = parsed.businessSuccess ? "SUCCESS" : "BUSINESS_FAILURE";
      await finish({
        p_response_payload: response.body,
        p_response_content_type: response.contentType,
        p_response_header_metadata: response.headers,
        p_http_status: response.status,
        p_native_status_value: parsed.nativeStatus,
        p_observation_count: parsed.observationCount,
        p_invalid_observation_count: parsed.invalidCount,
        p_normalized_outcome: outcome,
        p_error_category: parsed.businessSuccess
          ? null
          : "nse_order_status_business_failure",
        p_timeout_occurred: false,
        p_network_failure: false,
      });
      return json({
        data: {
          outcome: parsed.businessSuccess ? "success" : "business_failed",
          observation_count: parsed.observationCount,
        },
      }, parsed.businessSuccess ? 200 : 422);
    } catch {
      return json({ error: { code: "result_evidence_failed" } }, 500);
    }
  };
}
