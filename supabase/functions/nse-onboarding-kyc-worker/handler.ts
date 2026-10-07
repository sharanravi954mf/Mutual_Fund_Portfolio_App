import { createNseEvidenceCall } from "../_shared/nse/nse_evidence_call.ts";

export type Claim = {
  operation_id: string;
  claim_token: string;
  call_id: string;
  api: "CLIENT_KYC_REPORT" | "EKYCREG";
  request: string;
};
export type Result = {
  bytes: Uint8Array;
  status: number | null;
  transmission: "PROVEN_NOT_SENT" | "MAYBE_SENT" | "SENT_WITH_RESULT";
};
export type Dependencies = {
  token: string;
  claim: (event: string) => Promise<Claim | null>;
  start: (claim: Claim) => Promise<unknown>;
  finish: (claim: Claim, result: Result) => Promise<unknown>;
  submit: (claim: Claim) => Promise<Result>;
};
export function createOnboardingKycHandler(deps: Dependencies) {
  const reply = (status: number, code: string) =>
    new Response(JSON.stringify({ code }), {
      status,
      headers: {
        "content-type": "application/json",
        "cache-control": "no-store",
      },
    });
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return reply(405, "method_not_allowed");
    if (
      !deps.token ||
      request.headers.get("authorization") !== `Bearer ${deps.token}`
    ) return reply(403, "not_authorized");
    let input;
    try {
      input = await request.json();
    } catch {
      return reply(400, "invalid_request");
    }
    if (
      !input || typeof input !== "object" || Array.isArray(input) ||
      Object.keys(input).join() !== "event_outbox_id" ||
      typeof input.event_outbox_id !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        input.event_outbox_id,
      )
    ) return reply(400, "invalid_request");
    try {
      const claim = await deps.claim(input.event_outbox_id);
      if (!claim) return reply(200, "no_dispatchable_operation");
      const call = createNseEvidenceCall(() => deps.submit(claim));
      await call.persist(() => deps.start(claim));
      let result: Result;
      try {
        result = await call.submit();
      } catch {
        result = {
          bytes: new Uint8Array(),
          status: null,
          transmission: "MAYBE_SENT",
        };
      }
      await call.persist(() => deps.finish(claim, result));
      return reply(200, "evidence_recorded");
    } catch {
      // Never serialize provider errors, contacts or the workflow link.
      return reply(503, "onboarding_worker_unavailable");
    }
  };
}
