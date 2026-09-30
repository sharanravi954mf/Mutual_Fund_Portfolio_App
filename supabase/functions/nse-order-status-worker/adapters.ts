import { NseClient, NseClientError } from "../_shared/nse/nse_client.ts";
import { NSE_ORDER_STATUS_ENDPOINT } from "../_shared/nse/nse_order_status.ts";
export type Claim = {
  event_outbox_id: string | null;
  integration_operation_id: string | null;
  attempt: number;
  claim_state: string;
  claim_token: string | null;
};
type RpcClient = {
  rpc(
    name: string,
    arguments_: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message?: string } | null }>;
};
function fail(error: { message?: string } | null): never {
  throw new Error(error?.message ?? "integration_persistence_failed");
}
export function createOrderStatusPersistence(client: RpcClient) {
  return {
    async recoverExpired(maxAttempts: number) {
      const { error } = await client.rpc(
        "recover_expired_nse_order_status_events",
        { p_max_attempts: maxAttempts },
      );
      if (error) fail(error);
    },
    async claim(
      eventOutboxId: string,
      maxAttempts: number,
      leaseSeconds: number,
    ): Promise<Claim> {
      const { data, error } = await client.rpc("claim_nse_order_status_event", {
        p_event_outbox_id: eventOutboxId,
        p_max_attempts: maxAttempts,
        p_lease_seconds: leaseSeconds,
      });
      if (error) fail(error);
      if (!Array.isArray(data)) throw new Error("claim_shape_invalid");
      return data[0] ??
        {
          event_outbox_id: null,
          integration_operation_id: null,
          attempt: 0,
          claim_state: "no_event",
          claim_token: null,
        };
    },
    async source(id: string) {
      const { data, error } = await client.rpc("get_nse_order_status_source", {
        p_integration_operation_id: id,
      });
      if (error || data == null || typeof data !== "object") fail(error);
      return data;
    },
    async start(input: Record<string, unknown>) {
      const { error } = await client.rpc("start_nse_order_status", input);
      if (error) fail(error);
    },
    async finish(input: Record<string, unknown>) {
      const { error } = await client.rpc("finish_nse_order_status", input);
      if (error) fail(error);
    },
  };
}
export function createNseOrderStatusGateway(client: NseClient) {
  const options = (bodyText: string) => ({
    method: "POST",
    path: NSE_ORDER_STATUS_ENDPOINT,
    bodyText,
    contentType: "application/json",
    accept: "application/json",
    timeoutMs: 30_000,
    maxResponseBytes: 1024 * 1024,
    acceptHttpErrors: true,
  } as const);
  return {
    headers: (body: string) => client.safeRequestHeaderMetadata(options(body)),
    async submit(body: string) {
      try {
        const response = await client.request(options(body));
        return {
          kind: "response" as const,
          status: response.status,
          contentType: response.headers.get("content-type"),
          headers: response.safeHeaderMetadata,
          body: new TextDecoder().decode(response.body),
        };
      } catch (error) {
        const clientError = error instanceof NseClientError ? error : null;
        return {
          kind: "failure" as const,
          error: clientError?.code ?? "nse_transport_unexpected_error",
          timeout: clientError?.code === "nse_request_timeout",
          network: clientError?.code === "nse_network_error",
        };
      }
    },
  };
}
