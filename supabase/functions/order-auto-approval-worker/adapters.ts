import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.8";
import type {
  AutoApprovalRule,
  ClaimedOrderEvent,
  OrderRecord,
  Persistence,
  RpcError,
} from "./types.ts";

function rpcCode(
  error: { code?: string; message?: string } | null,
): RpcError | null {
  return error == null ? null : { code: error.code, message: error.message };
}

export function createSupabasePersistence(client: SupabaseClient): Persistence {
  return {
    async claimEvent(input) {
      const { data, error } = await client.rpc(
        "claim_order_auto_approval_event",
        {
          p_event_outbox_id: input.eventOutboxId,
          p_max_attempts: input.maxAttempts,
          p_lease_seconds: input.leaseSeconds,
        },
      );
      if (error != null) throw new Error(error.message);
      const rows = data as ClaimedOrderEvent[] | null;
      if (rows == null || rows.length === 0) {
        return {
          event_outbox_id: null,
          order_id: null,
          payload: null,
          correlation_id: null,
          attempt: 0,
          claim_state: "no_event",
          event_status: null,
          event_type: null,
          entity_type: null,
          claim_token: null,
          claim_expires_at: null,
        };
      }
      return rows[0];
    },

    async loadRuleEvaluationContext(input) {
      const { data: fund, error: fundError } = await client
        .from("mutual_funds")
        .select("category")
        .eq("scheme_code", input.schemeCode)
        .maybeSingle();
      if (fundError != null) throw new Error(fundError.message);

      const { data: trust, error: trustError } = await client
        .from("workspace_trusted_investors")
        .select("workspace_id")
        .eq("workspace_id", input.workspaceId)
        .eq("investor_profile_id", input.investorProfileId)
        .eq("is_active", true)
        .maybeSingle();
      if (trustError != null) throw new Error(trustError.message);

      return {
        investor_is_trusted: trust != null,
        scheme_category: typeof fund?.category === "string"
          ? fund.category
          : null,
      };
    },

    async loadOrder(orderId) {
      const { data, error } = await client
        .from("order_requests")
        .select(
          "id, workspace_id, investor_profile_id, scheme_code, type, amount, units, status, auto_approval_correlation_id",
        )
        .eq("id", orderId)
        .maybeSingle();
      if (error != null) throw new Error(error.message);
      return data as OrderRecord | null;
    },

    async listRules(input) {
      const now = new Date().toISOString();
      const { data, error } = await client
        .from("auto_approval_rules")
        .select(
          "id, workspace_id, transaction_type, min_amount, max_amount, trusted_client_only, category_restrictions, effective_from, effective_to, is_active, rule_version",
        )
        .eq("workspace_id", input.workspaceId)
        .eq("transaction_type", input.transactionType)
        .eq("is_active", true)
        .lte("effective_from", now)
        .or(`effective_to.is.null,effective_to.gt.${now}`)
        .order("effective_from", { ascending: false })
        .order("rule_version", { ascending: false })
        .order("id", { ascending: true });
      if (error != null) throw new Error(error.message);
      return (data ?? []) as AutoApprovalRule[];
    },

    async applyDecision(input) {
      const { data, error } = await client.rpc("apply_auto_approval_decision", {
        p_order_id: input.orderId,
        p_decision: input.decision,
        p_rule_id: input.ruleId,
        p_rule_version: input.ruleVersion,
        p_correlation_id: input.correlationId,
        p_claim_token: input.claimToken,
      });
      return { data: data as OrderRecord | null, error: rpcCode(error) };
    },

    async recordFailure(input) {
      const { error } = await client.rpc(
        "record_order_auto_approval_claim_failure",
        {
          p_event_outbox_id: input.eventOutboxId,
          p_claim_token: input.claimToken,
          p_error_code: input.errorCode,
          p_error_message: input.errorMessage,
          p_retryable: input.retryable,
          p_max_attempts: input.maxAttempts,
        },
      );
      return { error: rpcCode(error) };
    },
  };
}
