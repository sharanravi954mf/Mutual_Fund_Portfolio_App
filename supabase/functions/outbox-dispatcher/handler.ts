import type { Config } from "./config.ts";
import { ROUTES } from "./routes.generated.ts";

export const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export type Notification = {
  version: 1;
  request_id: string;
  issued_at: number;
  environment: string;
  project_url: string;
  kind: "event" | "recovery";
  event_outbox_id: string | null;
  hop: number;
};
export type Candidate = { event_outbox_id: string; event_type: string };
export function signingInput(n: Notification): string {
  return [
    n.version,
    n.request_id,
    n.issued_at,
    n.environment,
    n.project_url,
    n.kind,
    n.event_outbox_id ?? "-",
    n.hop,
  ].join("|");
}
export async function sign(n: Notification, key: string): Promise<string> {
  const encoder = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return Array.from(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        cryptoKey,
        encoder.encode(signingInput(n)),
      ),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
function equal(a: string, b: string): boolean {
  let difference = a.length ^ b.length;
  for (let i = 0; i < b.length; i++) {
    difference |= (a.charCodeAt(i) || 0) ^ b.charCodeAt(i);
  }
  return difference === 0;
}
export async function boundedText(
  body: ReadableStream<Uint8Array> | null,
  limit: number,
  signal?: AbortSignal,
): Promise<string> {
  if (!body || signal?.aborted) throw Error();
  const reader = body.getReader();
  const cancel = () => {
    void reader.cancel().catch(() => {});
  };
  signal?.addEventListener("abort", cancel, { once: true });
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (signal?.aborted) throw Error();
      if (done) break;
      size += value.length;
      if (size > limit) throw Error();
      chunks.push(value);
    }
  } catch {
    await reader.cancel().catch(() => {});
    throw Error("outbox_body_invalid");
  } finally {
    signal?.removeEventListener("abort", cancel);
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}
const response = (status: number, code: string, extra = {}) =>
  Response.json(
    { code, ...extra },
    { status, headers: { "Cache-Control": "no-store" } },
  );
export function createHandler(config: Config, deps: {
  fetch?: typeof fetch;
  now?: () => number;
  log?: (entry: Record<string, string | number>) => void;
} = {}) {
  const transport = deps.fetch ?? fetch;
  const now = deps.now ?? Date.now;
  const log = deps.log ?? (() => {});
  async function rpc(
    name: string,
    args: Record<string, unknown>,
  ): Promise<unknown> {
    const timer = new AbortController();
    const timeout = setTimeout(() => timer.abort(), 8000);
    try {
      const result = await transport(`${config.origin}/rest/v1/rpc/${name}`, {
        method: "POST",
        redirect: "error",
        signal: timer.signal,
        headers: {
          "Content-Type": "application/json",
          apikey: config.databaseKey,
          Authorization: `Bearer ${config.databaseKey}`,
        },
        body: JSON.stringify(args),
      });
      if (!result.ok) {
        await result.body?.cancel();
        throw Error();
      }
      return JSON.parse(await boundedText(result.body, 16384, timer.signal));
    } finally {
      clearTimeout(timeout);
    }
  }
  return async (req: Request): Promise<Response> => {
    if (req.method !== "POST") return response(405, "outbox_method_invalid");
    const path = new URL(req.url).pathname;
    const kind = path === "/outbox-dispatcher/event" ||
        path === "/functions/v1/outbox-dispatcher/event"
      ? "event"
      : path === "/outbox-dispatcher/recovery" ||
          path === "/functions/v1/outbox-dispatcher/recovery"
      ? "recovery"
      : null;
    if (!kind || new URL(req.url).search) {
      return response(404, "outbox_path_invalid");
    }
    if (
      !/^application\/json(?:;\s*charset=utf-8)?$/i.test(
        req.headers.get("content-type") ?? "",
      )
    ) {
      return response(415, "outbox_content_type_invalid");
    }
    const signature = req.headers.get("x-outbox-signature") ?? "";
    if (!/^[0-9a-f]{64}$/.test(signature)) {
      return response(401, "outbox_unauthorized");
    }
    let notification: Notification;
    try {
      const length = req.headers.get("content-length");
      if (length && (!/^\d+$/.test(length) || Number(length) > 2048)) {
        throw Error();
      }
      // A slow input stream cannot occupy the function indefinitely.
      const inputController = new AbortController();
      const inputTimeout = setTimeout(() => inputController.abort(), 2000);
      try {
        notification = JSON.parse(
          await boundedText(req.body, 2048, inputController.signal),
        );
      } finally {
        clearTimeout(inputTimeout);
      }
      const n = notification;
      if (
        !n || Object.keys(n).sort().join(",") !==
          "environment,event_outbox_id,hop,issued_at,kind,project_url,request_id,version" ||
        n.version !== 1 || !UUID.test(n.request_id) || n.kind !== kind ||
        n.environment !== config.environment ||
        n.project_url !== config.origin ||
        !Number.isSafeInteger(n.issued_at) ||
        Math.abs(now() / 1000 - n.issued_at) > 300 ||
        !Number.isInteger(n.hop) || n.hop < 0 || n.hop > 15 ||
        (kind === "event"
          ? typeof n.event_outbox_id !== "string" ||
            !UUID.test(n.event_outbox_id) || n.hop !== 0
          : n.event_outbox_id !== null)
      ) throw Error();
      if (!equal(signature, await sign(n, config.signingKey))) {
        return response(401, "outbox_unauthorized");
      }
    } catch {
      return response(400, "outbox_notification_invalid");
    }
    if (config.mode === "disabled") return response(503, "outbox_disabled");
    try {
      const n = notification;
      const admission = await rpc("admit_outbox_dispatch", {
        p_environment: config.environment,
        p_project_url: config.origin,
        p_mode: config.mode,
        p_request_id: n.request_id,
        p_event_id: n.event_outbox_id,
        p_event_types: Object.keys(ROUTES),
      }) as { code: string; batch_token?: string; candidates?: Candidate[] };
      if (["disabled", "busy", "replay"].includes(admission.code)) {
        return response(202, `outbox_${admission.code}`);
      }
      if (
        admission.code !== "admitted" ||
        !UUID.test(admission.batch_token ?? "") ||
        !Array.isArray(admission.candidates) || admission.candidates.length > 4
      ) throw Error();
      const candidates = admission.candidates;
      if (
        candidates.some((c) =>
          !UUID.test(c.event_outbox_id) || !Object.hasOwn(ROUTES, c.event_type)
        ) ||
        new Set(candidates.map((c) => c.event_outbox_id)).size !==
          candidates.length ||
        (n.event_outbox_id !== null &&
          candidates.some((c) => c.event_outbox_id !== n.event_outbox_id))
      ) throw Error();
      let uncertain = false;
      await Promise.all(candidates.map(async (candidate) => {
        let outcome = "observed";
        let status = 0;
        if (config.mode === "active") {
          // Recheck the DB switch immediately before sending; never persist event state here.
          const allowed = await rpc("authorize_outbox_dispatch", {
            p_batch_token: admission.batch_token,
            p_event_id: candidate.event_outbox_id,
            p_environment: config.environment,
            p_project_url: config.origin,
          });
          if (allowed !== true) return;
          const controller = new AbortController();
          const timeout = setTimeout(() => controller.abort(), 45000);
          try {
            const result = await transport(
              `${config.origin}/functions/v1/${ROUTES[candidate.event_type]}`,
              {
                method: "POST",
                redirect: "error",
                signal: controller.signal,
                headers: {
                  "Content-Type": "application/json",
                  Authorization: `Bearer ${config.workerToken}`,
                },
                body: JSON.stringify({
                  event_outbox_id: candidate.event_outbox_id,
                }),
              },
            );
            status = result.status;
            await result.body?.cancel();
            outcome = result.ok ? "worker_accepted" : "worker_rejected";
          } catch {
            outcome = "transport_uncertain";
            uncertain = true;
          } finally {
            clearTimeout(timeout);
          }
        }
        log({
          event: "outbox_dispatch",
          event_outbox_id: candidate.event_outbox_id,
          event_type: candidate.event_type,
          outcome,
          worker_status: status,
        });
      }));
      // Timeout != not sent. Leave admission lease until expiry and rely on workers/Cron.
      if (!uncertain) {
        await rpc("finish_outbox_dispatch", {
          p_batch_token: admission.batch_token,
          p_next_hop:
            config.mode === "active" && candidates.length > 0 && n.hop < 15
              ? n.hop + 1
              : null,
        });
      }
      return response(200, "outbox_processed", { count: candidates.length });
    } catch {
      return response(503, "outbox_dependency_unavailable");
    }
  };
}
