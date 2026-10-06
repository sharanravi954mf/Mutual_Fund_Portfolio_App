import { createNseEvidenceCall } from "../_shared/nse/nse_evidence_call.ts";

export type Action = "MANDATE" | "BANK_ADD" | "BANK_DEL";
export type Source = {
  operation_id: string;
  action: Action;
  kind: "WRITE" | "READ";
  request: Record<string, unknown>;
  path: string;
};
export type Claim = {
  event_id: string;
  operation_id: string;
  claim_token: string;
  attempt: number;
};
export type Result = {
  delivery: "PROVEN_NOT_SENT" | "MAYBE_SENT" | "SENT_WITH_RESULT";
  bodyBase64: string;
  httpStatus: number | null;
  headers: Record<string, string>;
};
export type Persistence = {
  claim(id: string): Promise<Claim | null>;
  source(id: string): Promise<Source>;
  start(
    input: { event: Claim; call: string; body: string; started: string },
  ): Promise<unknown>;
  finish(
    input: { event: Claim; call: string; result: Result; completed: string },
  ): Promise<{ outcome: string }>;
  reconcile(id: string): Promise<unknown>;
};
export const PATHS = {
  MANDATE: "/nsemfdesk/api/v2/registration/product/MANDATE",
  BANK_ADD: "/nsemfdesk/api/v2/registration/CLIENTBANKDTL",
  BANK_DEL: "/nsemfdesk/api/v2/registration/CLIENTBANKDTL",
} as const;
const readPath = (action: Action) =>
  action === "MANDATE"
    ? "/nsemfdesk/api/v2/reports/MANDATE_STATUS"
    : "/nsemfdesk/api/v2/reports/client_master_report";
function object(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
export function serializeRequest(source: Source): string {
  const fail = () => {
    throw new Error("b07_source_invalid");
  };
  if (
    !Object.hasOwn(PATHS, source.action) ||
    !["WRITE", "READ"].includes(source.kind) ||
    source.path !==
      (source.kind === "WRITE"
        ? PATHS[source.action]
        : readPath(source.action)) ||
    !object(source.request)
  ) return fail();
  if (source.kind === "READ") {
    const keys = source.action === "MANDATE"
      ? ["memberMandateIds"]
      : ["client_code", "PAN", "from_date", "to_date"];
    if (
      Object.keys(source.request).sort().join() !== keys.sort().join() ||
      !Object.values(source.request).every((x) => typeof x === "string")
    ) return fail();
    if (source.action === "MANDATE") {
      if (!/^MB[0-9a-f]{18}$/.test(String(source.request.memberMandateIds))) {
        return fail();
      }
    } else if (
      !/^[A-Za-z0-9_-]{1,20}$/.test(String(source.request.client_code)) ||
      source.request.PAN !== "" || source.request.from_date !== "" ||
      source.request.to_date !== ""
    ) return fail();
  } else {
    const wrapper = source.action === "MANDATE" ? "reg_data" : "bank_dtl";
    const rows = source.request[wrapper];
    if (
      Object.keys(source.request).join() !== wrapper || !Array.isArray(rows) ||
      rows.length !== 1 || !object(rows[0])
    ) return fail();
    const row = rows[0];
    const keys = source.action === "MANDATE"
      ? [
        "client_code",
        "amount",
        "mandate_type",
        "account_no",
        "ac_type",
        "ifsc_code",
        "start_date",
        "end_date",
        "member_mandate_no",
        ...(Object.hasOwn(row, "registration_date")
          ? ["registration_date"]
          : []),
      ]
      : [
        "client_code",
        "action_type",
        "account_type",
        "account_no",
        "micr_no",
        "ifsc_code",
        "default_bank_flag",
      ];
    if (
      Object.keys(row).sort().join() !== keys.sort().join() ||
      !Object.values(row).every((x) => typeof x === "string") ||
      !/^[A-Za-z0-9_-]{1,20}$/.test(String(row.client_code)) ||
      !/^[A-Z0-9]{1,40}$/.test(String(row.account_no)) ||
      !/^[A-Z]{4}0[A-Z0-9]{6}$/.test(String(row.ifsc_code))
    ) return fail();
    if (source.action === "MANDATE") {
      if (
        String(row.client_code).length > 10 ||
        !["X", "E"].includes(String(row.mandate_type)) ||
        !["SB", "CB", "NE", "NO"].includes(String(row.ac_type)) ||
        !/^MB[0-9a-f]{18}$/.test(String(row.member_mandate_no)) ||
        !/^[0-9]{1,13}(\.[0-9]{1,2})?$/.test(String(row.amount)) ||
        Number(row.amount) <= 0
      ) return fail();
    } else if (
      row.action_type !== (source.action === "BANK_ADD" ? "ADD" : "DEL") ||
      !["SB", "CB", "NE", "NO"].includes(String(row.account_type)) ||
      !/^(|[0-9]{9})$/.test(String(row.micr_no)) ||
      !["Y", "N"].includes(String(row.default_bank_flag)) ||
      (source.action === "BANK_DEL" && row.default_bank_flag !== "N")
    ) return fail();
  }
  return JSON.stringify(source.request);
}
export function createHandler(deps: {
  token: string;
  persistence: Persistence;
  submit(body: string, source: Source): Promise<Result>;
  uuid?: () => string;
  now?: () => Date;
}) {
  const json = (code: string, status: number) =>
    new Response(JSON.stringify({ outcome: code }), {
      status,
      headers: {
        "content-type": "application/json",
        "cache-control": "no-store",
      },
    });
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") return json("method_not_allowed", 405);
    if (
      !deps.token ||
      request.headers.get("authorization") !== `Bearer ${deps.token}`
    ) return json("not_authorized", 403);
    try {
      const input: unknown = await request.json();
      if (
        !object(input) || Object.keys(input).join() !== "event_outbox_id" ||
        typeof input.event_outbox_id !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          .test(input.event_outbox_id)
      ) return json("invalid_request_body", 400);
      const event = await deps.persistence.claim(input.event_outbox_id);
      if (!event) return json("event_unavailable", 404);
      if (event.event_id !== input.event_outbox_id) {
        return json("claim_invalid", 500);
      }
      const source = await deps.persistence.source(event.operation_id);
      if (source.operation_id !== event.operation_id) {
        return json("source_invalid", 500);
      }
      const body = serializeRequest(source);
      const call = (deps.uuid ?? (() => crypto.randomUUID()))();
      const now = deps.now ?? (() => new Date());
      const started = now().toISOString();
      const evidence = createNseEvidenceCall(async () => {
        try {
          return await deps.submit(body, source);
        } catch {
          return {
            delivery: "MAYBE_SENT" as const,
            bodyBase64: "",
            httpStatus: null,
            headers: {},
          };
        }
      });
      await evidence.persist(() =>
        deps.persistence.start({ event, call, body, started })
      );
      const result = await evidence.submit();
      const completed = now().toISOString();
      await evidence.persist(() =>
        deps.persistence.finish({ event, call, result, completed })
      );
      if (source.kind === "READ") {
        await deps.persistence.reconcile(event.operation_id);
      }
      return json("evidence_recorded", 200);
    } catch {
      return json("b07_worker_failed", 500);
    }
  };
}
