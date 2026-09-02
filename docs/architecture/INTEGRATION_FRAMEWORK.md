# MoneyBowl integration framework

Status: first vertical slice implemented locally; no hosted deployment.

## Boundary

MoneyBowl core owns authentication, authorization, canonical investors, addresses, banks, schemes, folios, orders, transactions, business policy, and event_outbox. Integration modules translate that canonical state to external contracts. Current modules are NSEInvest, CAMS Mailback, and KFin Mailback; future BSE/NMF or data integrations follow the same boundary.

Shared outbound API infrastructure consists of integration_accounts (current external identity), integration_operations (current logical operation state), integration_api_interactions (immutable API communication evidence), and event_outbox (transactional handoff). The word integration is deliberate: provider is ambiguous in the financial domain. No registry table exists yet; integration keys and contract constants remain version controlled.

CAMS/KFin mailback remains inbound data ingestion. It is not forced into integration_api_interactions unless it performs an external API call. This slice does not refactor either ingestion module.

## Outbound call rules

Every call records one encrypted REQUEST row before transport and one encrypted RESULT row after transport, linked by call_id. Persistence is idempotent for identical evidence and rejects conflicts. UPDATE and DELETE are rejected at the database boundary; foreign keys use RESTRICT for evidence. Normalized operational fields remain queryable, but browser roles cannot read evidence or invoke privileged lifecycle RPCs.

Only safe allowlisted communication metadata is audited: request content_type, user_agent, accept; response content_type, x_request_id, x_correlation_id. Authorization, API keys/secrets, encrypted passwords, cookies, and tokens are prohibited recursively in payload/header metadata.

External writes are not blindly retried. A proven pre-transmission failure may use the bounded outbox retry budget. A failure after REQUEST evidence exists, a possibly transmitted network/timeout error, integration 5xx, or contract-invalid success requires reconciliation. Ambiguity implies reconciliation, but reconciliation is intentionally broader: a known integration-versus-local state discrepancy may require reconciliation without being ambiguous.

Shared transports remain endpoint-neutral. Each adapter explicitly resolves its own Accept and Content-Type values, and immutable request evidence is calculated from the exact pre-serialized bytes passed to transport. The safe header audit is derived from those resolved headers and never includes authorization, cookies, or session material.

Read-only calls use truthful, bounded recovery without write ambiguity. If a read REQUEST has no usable response, an immutable TRANSPORT_FAILURE RESULT closes that call. A safe retry uses a new call_id; it never overwrites the abandoned attempt.

## NSE module

The NSE module owns NseClient, authentication/configuration, the NNF v1.9.7 CLIENTCOMMON183 mapper, UCC worker, response distributor, and the read-only Client Master post-registration verification/ambiguous-write reconciliation adapter. It uses integration_key NSE_INVEST. The UCC-specific lifecycle is in [NSE UCC Vertical Slice](NSE_UCC_VERTICAL_SLICE.md).
