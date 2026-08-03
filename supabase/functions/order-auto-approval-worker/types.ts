export type RpcError = {
  code?: string;
  message?: string;
};

export type ClaimedOrderEvent = {
  event_outbox_id: string | null;
  order_id: string | null;
  payload: Record<string, unknown> | null;
  correlation_id: string | null;
  attempt: number;
  claim_state:
    | "newly_claimed"
    | "retry_claimed"
    | "completed_replay"
    | "active_in_progress"
    | "terminal_failed"
    | "invalid_event"
    | "not_found"
    | "no_event";
  event_status: string | null;
  event_type: string | null;
  entity_type: string | null;
  claim_token: string | null;
  claim_expires_at: string | null;
};

export type OrderRecord = {
  id: string;
  workspace_id: string;
  investor_profile_id: string;
  scheme_code: string;
  type: "buy" | "sell" | "switch";
  amount: string | number | null;
  units: string | number | null;
  status: string;
  auto_approval_correlation_id?: string | null;
};

export type AutoApprovalRule = {
  id: string;
  workspace_id: string;
  transaction_type: "buy" | "sell" | "switch";
  min_amount: string | number | null;
  max_amount: string | number | null;
  trusted_client_only: boolean;
  category_restrictions: string[] | null;
  effective_from: string;
  effective_to: string | null;
  is_active: boolean;
  rule_version: number;
};

export type RuleEvaluationContext = {
  investor_is_trusted: boolean;
  scheme_category: string | null;
};

export type Decision = {
  decision: "auto_approved" | "pending_review";
  rule_id: string | null;
  rule_version: number | null;
};

export type Persistence = {
  claimEvent(input: {
    eventOutboxId: string | null;
    maxAttempts: number;
    leaseSeconds: number;
  }): Promise<ClaimedOrderEvent>;
  loadOrder(orderId: string): Promise<OrderRecord | null>;
  loadRuleEvaluationContext(input: {
    workspaceId: string;
    investorProfileId: string;
    schemeCode: string;
  }): Promise<RuleEvaluationContext>;
  listRules(input: {
    workspaceId: string;
    transactionType: OrderRecord["type"];
  }): Promise<AutoApprovalRule[]>;
  applyDecision(input: {
    orderId: string;
    decision: Decision["decision"];
    ruleId: string | null;
    ruleVersion: number | null;
    correlationId: string;
    claimToken: string;
  }): Promise<{ data: OrderRecord | null; error: RpcError | null }>;
  recordFailure(input: {
    eventOutboxId: string;
    claimToken: string;
    errorCode: string;
    errorMessage: string | null;
    retryable: boolean;
    maxAttempts: number;
  }): Promise<{ error: RpcError | null }>;
};
