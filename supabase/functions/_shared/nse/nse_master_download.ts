import { createNseBasicAuthorization } from "./nse_auth.ts";
import type { NseConfig, NseFetch } from "./nse_types.ts";

export const NSE_MASTER_PATH = "/nsemfdesk/api/v2/reports/MASTER_DOWNLOAD";
export const NSE_MASTER_MAX_BYTES = 16 * 1024 * 1024;
export const NSE_MASTER_CHUNK_BYTES = 256 * 1024;
export const NSE_MASTER_FILE_TYPES = [
  "SCH",
  "SIP",
  "STP",
  "SWP",
  "NAV",
  "SET",
] as const;
export type NseMasterFileType = typeof NSE_MASTER_FILE_TYPES[number];
// Independent extension points: none of these is a parser or publication approval.
export const NSE_MASTER_VARIANTS = Object.freeze(
  {
    SCH: {
      parser: "SCH",
      publication: "scheme_catalog",
      header: "uncharacterized",
    },
    SIP: {
      parser: "SIP",
      publication: "sip_eligibility",
      header: "uncharacterized",
    },
    STP: {
      parser: "STP",
      publication: "stp_eligibility",
      header: "uncharacterized",
    },
    SWP: {
      parser: "SWP",
      publication: "swp_eligibility",
      header: "uncharacterized",
    },
    NAV: { parser: "NAV", publication: "nav_observations", header: "absent" },
    SET: {
      parser: "SET",
      publication: "settlement_calendar",
      header: "uncharacterized",
    },
  } as const,
);
export type NseMasterScope = Readonly<{
  workspaceId: string;
  connectionId: string;
  callId: string;
  environment: "UAT";
  fileType: NseMasterFileType;
}>;
export type NseMasterCapture = {
  kind:
    | "COMPLETE"
    | "OVERSIZE"
    | "TRUNCATED"
    | "TRANSPORT_FAILED"
    | "UNVERIFIABLE";
  httpStatus: number | null;
  mediaType: "TEXT" | "OCTET_STREAM" | "JSON" | "OTHER" | "UNKNOWN";
  declaredBytes: number | null;
  identityEncoding: boolean;
  eof: boolean;
  sha256: string | null;
};
export interface NseMasterEvidenceStore {
  begin(
    scope: NseMasterScope,
    binding: { memberCode: string; baseUrl: string; captureToken: string },
  ): Promise<{ download_id: string; request_body: string }>;
  append(
    scope: NseMasterScope,
    ordinal: number,
    bytes: Uint8Array,
    sha256: string,
  ): Promise<void>;
  finish(scope: NseMasterScope, capture: NseMasterCapture): Promise<void>;
}
export class NseMasterError extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "NseMasterError";
  }
}
export function nseMasterRequest(fileType: unknown): string {
  if (!NSE_MASTER_FILE_TYPES.includes(fileType as NseMasterFileType)) {
    throw new NseMasterError("nse_reference_request_invalid");
  }
  return JSON.stringify({ file_type: fileType });
}
export async function nseMasterSha256(bytes: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return Array.from(
    new Uint8Array(hash),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}
async function persist<T>(call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch {
    try {
      return await call();
    } catch {
      throw new NseMasterError("nse_reference_persistence_failed");
    }
  }
}

/**
 * Attempt-local capture primitive for later variant workers. No deployed handler,
 * automatic retry, parser or publication. The same callId cannot send twice:
 * begin binds a fresh process-local token; only its acknowledgement can retry.
 */
export async function captureNseMasterDownload(
  config: NseConfig,
  scope: NseMasterScope,
  store: NseMasterEvidenceStore,
  fetcher: NseFetch = fetch,
): Promise<NseMasterCapture> {
  const requestBody = nseMasterRequest(scope.fileType);
  const base = new URL(config.baseUrl);
  if (
    scope.environment !== "UAT" || base.protocol !== "https:" ||
    base.origin !== config.baseUrl || base.username || base.password
  ) {
    throw new NseMasterError("nse_reference_runtime_binding_mismatch");
  }
  const captureToken = crypto.randomUUID();
  const request = await persist(() =>
    store.begin(scope, {
      memberCode: config.memberCode,
      baseUrl: config.baseUrl,
      captureToken,
    })
  );
  if (
    request.download_id !== scope.callId || request.request_body !== requestBody
  ) throw new NseMasterError("nse_reference_request_mismatch");
  const capture: NseMasterCapture = {
    kind: "TRANSPORT_FAILED",
    httpStatus: null,
    mediaType: "UNKNOWN",
    declaredBytes: null,
    identityEncoding: false,
    eof: false,
    sha256: null,
  };
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 120_000);
  let response: Response | undefined;
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let persistenceFailed = false;
  const chunks: Uint8Array[] = [];
  let total = 0;
  let pending = new Uint8Array(NSE_MASTER_CHUNK_BYTES);
  let used = 0;
  const flush = async () => {
    if (!used) return;
    const bytes = pending.slice(0, used);
    const hash = await nseMasterSha256(bytes);
    try {
      await persist(() => store.append(scope, chunks.length, bytes, hash));
    } catch (error) {
      persistenceFailed = true;
      throw error;
    }
    chunks.push(bytes);
    pending = new Uint8Array(NSE_MASTER_CHUNK_BYTES);
    used = 0;
  };
  try {
    response = await fetcher(new URL(NSE_MASTER_PATH, base), {
      method: "POST",
      redirect: "error",
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        Accept: "text/plain, application/octet-stream, application/json",
        "Accept-Encoding": "identity",
        "Accept-Language": "en-US",
        "User-Agent": config.userAgent,
        Referer: "www.google.com",
        memberId: config.memberCode,
        Authorization: await createNseBasicAuthorization(config),
      },
      body: requestBody,
    });
    capture.httpStatus = response.status;
    const media = response.headers.get("content-type")?.split(";")[0].trim()
      .toLowerCase();
    capture.mediaType = media === "text/plain"
      ? "TEXT"
      : media === "application/octet-stream"
      ? "OCTET_STREAM"
      : media === "application/json"
      ? "JSON"
      : media
      ? "OTHER"
      : "UNKNOWN";
    const encoding = response.headers.get("content-encoding");
    capture.identityEncoding = encoding === null ||
      encoding.trim().toLowerCase() === "identity";
    const length = response.headers.get("content-length");
    const lengthHeaderInvalid = length !== null &&
      (!/^(0|[1-9][0-9]{0,15})$/.test(length) ||
        !Number.isSafeInteger(Number(length)));
    if (length !== null && !lengthHeaderInvalid) {
      capture.declaredBytes = Number(length);
    }
    // NSE UAT MASTER_DOWNLOAD was observed on 2026-10-07 returning HTTP 200
    // text/plain with identity encoding and no Content-Length. Preserve strict
    // rejection for malformed framing/compression, but allow a bounded identity
    // body to prove completion by reaching EOF. The 16 MiB cap still applies.
    if (!capture.identityEncoding || lengthHeaderInvalid) {
      capture.kind = "UNVERIFIABLE";
      await response.body?.cancel();
    } else if (
      capture.declaredBytes !== null &&
      capture.declaredBytes > NSE_MASTER_MAX_BYTES
    ) {
      capture.kind = "OVERSIZE";
      await response.body?.cancel();
    } else {
      reader = response.body?.getReader();
      while (reader) {
        const { done, value } = await reader.read();
        if (done) break;
        if (total + value.byteLength > NSE_MASTER_MAX_BYTES) {
          capture.kind = "OVERSIZE";
          break;
        }
        if (
          capture.declaredBytes !== null &&
          total + value.byteLength > capture.declaredBytes
        ) {
          capture.kind = "TRUNCATED";
          break;
        }
        total += value.byteLength;
        let offset = 0;
        while (offset < value.byteLength) {
          const take = Math.min(
            pending.length - used,
            value.byteLength - offset,
          );
          pending.set(value.subarray(offset, offset + take), used);
          used += take;
          offset += take;
          if (used === pending.length) await flush();
        }
      }
      await flush();
      if (capture.kind !== "OVERSIZE" && capture.kind !== "TRUNCATED") {
        capture.eof = true;
        if (
          capture.declaredBytes !== null &&
          total !== capture.declaredBytes
        ) capture.kind = "TRUNCATED";
        else {
          const body = new Uint8Array(total);
          let offset = 0;
          for (const chunk of chunks) {
            body.set(chunk, offset);
            offset += chunk.length;
          }
          capture.sha256 = await nseMasterSha256(body);
          capture.kind = "COMPLETE";
        }
      }
    }
  } catch (error) {
    if (persistenceFailed) throw error;
    // Keep only already acknowledged chunks. No error text or headers can leak
    // through diagnostics, and a failed stream never claims a complete body.
    capture.kind = "TRANSPORT_FAILED";
    capture.sha256 = null;
    capture.eof = false;
  } finally {
    clearTimeout(timeout);
    controller.abort();
    try {
      await reader?.cancel();
    } catch { /* the stream may already have failed */ }
    reader?.releaseLock();
  }
  await persist(() => store.finish(scope, capture));
  return capture;
}
