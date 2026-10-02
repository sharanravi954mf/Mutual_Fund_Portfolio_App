import { captureNseMasterDownload } from "../_shared/nse/nse_master_download.ts";
import type { NseConfig, NseFetch } from "../_shared/nse/nse_types.ts";
import { masterUuid } from "./adapters.ts";
import type { MasterPersistence } from "./types.ts";

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });
}
async function retryAcknowledgement<T>(call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch {
    return await call();
  }
}
export function createNseMasterDownloadHandler(deps: {
  internalToken: string;
  persistence: MasterPersistence;
  config: NseConfig;
  fetcher?: NseFetch;
  uuid?: () => string;
}) {
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    if (
      !deps.internalToken ||
      request.headers.get("authorization") !== `Bearer ${deps.internalToken}`
    ) return json({ error: "not_authorized" }, 403);
    // Do not accept a caller-selected connection, file type, URL, or NSE body.
    let input;
    try {
      const reader = request.body?.getReader();
      if (!reader) throw new Error();
      const chunks: Uint8Array[] = [];
      let length = 0;
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          length += value.length;
          if (length > 256) throw new Error();
          chunks.push(value);
        }
      } finally {
        await reader.cancel();
        reader.releaseLock();
      }
      const bytes = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      input = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      );
      if (
        input === null || typeof input !== "object" || Array.isArray(input) ||
        Object.keys(input).length !== 1 ||
        typeof input.event_outbox_id !== "string" ||
        !masterUuid.test(input.event_outbox_id)
      ) throw new Error();
    } catch {
      return json({ error: "invalid_request_body" }, 400);
    }
    try {
      const eventId = input.event_outbox_id;
      const token = (deps.uuid ?? (() => crypto.randomUUID()))();
      const claim = await retryAcknowledgement(() =>
        deps.persistence.claim(eventId, token)
      );
      if (claim.action === "DONE" || claim.action === "BUSY") {
        return json({ data: { outcome: claim.action } }, 202);
      }
      if (claim.eventId !== eventId) throw new Error();
      if (claim.action === "CAPTURE") {
        await captureNseMasterDownload(
          deps.config,
          claim.scope,
          deps.persistence.evidence(eventId, token),
          deps.fetcher,
        );
      }
      const result = await retryAcknowledgement(() =>
        deps.persistence.finalize(eventId, token)
      );
      // A staged layout is never communicated as published business reference data.
      return json({ data: { ...result, publication_gate: "BLOCKED" } });
    } catch {
      return json({ error: "nse_reference_worker_failed" }, 500);
    }
  };
}
