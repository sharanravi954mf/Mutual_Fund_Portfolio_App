import { createNseBasicAuthorization } from "./nse_auth.ts";
import type {
  NseConfig,
  NseFetch,
  NseRequestOptions,
  NseResponse,
  SafeIntegrationHeaderMetadata,
} from "./nse_types.ts";

const defaultTimeoutMs = 30_000;
const defaultMaxResponseBytes = 10 * 1024 * 1024;

export class NseClientError extends Error {
  readonly code: string;
  readonly nseStatus: number | null;

  constructor(code: string, nseStatus: number | null = null) {
    super("NSE request failed");
    this.name = "NseClientError";
    this.code = code;
    this.nseStatus = nseStatus;
  }
}

function positiveBoundedInteger(
  value: number | undefined,
  fallback: number,
): number {
  const resolved = value ?? fallback;
  if (!Number.isInteger(resolved) || resolved <= 0) {
    throw new NseClientError("nse_request_invalid");
  }
  return resolved;
}

function endpointUrl(baseUrl: string, path: string): URL {
  if (/^[a-z][a-z\d+.-]*:/i.test(path)) {
    throw new NseClientError("nse_request_invalid");
  }

  const base = new URL(`${baseUrl}/`);
  const endpoint = new URL(path, base);
  if (endpoint.origin !== base.origin || endpoint.protocol !== "https:") {
    throw new NseClientError("nse_request_invalid");
  }
  return endpoint;
}

async function readBoundedBody(
  response: Response,
  maximumBytes: number,
): Promise<Uint8Array> {
  const contentLength = response.headers.get("content-length");
  if (contentLength != null) {
    const parsedLength = Number(contentLength);
    if (Number.isFinite(parsedLength) && parsedLength > maximumBytes) {
      await response.body?.cancel();
      throw new NseClientError("nse_response_too_large", response.status);
    }
  }

  if (response.body == null) return new Uint8Array();

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    totalBytes += value.byteLength;
    if (totalBytes > maximumBytes) {
      await reader.cancel();
      throw new NseClientError("nse_response_too_large", response.status);
    }
    chunks.push(value);
  }

  const body = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

function boundedHeader(headers: Headers, name: string): string | undefined {
  const value = headers.get(name)?.trim();
  return value != null && value.length > 0 && value.length <= 512
    ? value
    : undefined;
}

export function safeNseResponseHeaderMetadata(
  headers: Headers,
): SafeIntegrationHeaderMetadata {
  const metadata: Record<string, string> = {};
  const contentType = boundedHeader(headers, "content-type");
  const requestId = boundedHeader(headers, "x-request-id");
  const correlationId = boundedHeader(headers, "x-correlation-id");
  if (contentType != null) metadata.content_type = contentType;
  if (requestId != null) metadata.x_request_id = requestId;
  if (correlationId != null) metadata.x_correlation_id = correlationId;
  return metadata;
}

export class NseClient {
  readonly #config: NseConfig;
  readonly #fetch: NseFetch;

  constructor(config: NseConfig, fetcher: NseFetch = fetch) {
    this.#config = config;
    this.#fetch = fetcher;
  }

  safeRequestHeaderMetadata(
    options: Pick<
      NseRequestOptions,
      "jsonBody" | "bodyText" | "contentType" | "accept" | "headers"
    >,
  ): SafeIntegrationHeaderMetadata {
    const headers = this.#resolvedHeaders(options);
    const metadata: Record<string, string> = {
      user_agent: this.#config.userAgent,
    };
    const contentType = headers.get("content-type")?.trim();
    const accept = headers.get("accept")?.trim();
    if (contentType) metadata.content_type = contentType;
    if (accept) metadata.accept = accept;
    return metadata;
  }

  #resolvedHeaders(
    options: Pick<
      NseRequestOptions,
      "jsonBody" | "bodyText" | "contentType" | "accept" | "headers"
    >,
  ): Headers {
    if (options.jsonBody !== undefined && options.bodyText !== undefined) {
      throw new NseClientError("nse_request_invalid");
    }
    const headers = new Headers(options.headers);
    if (options.accept != null) headers.set("Accept", options.accept);
    if (options.jsonBody !== undefined) {
      headers.set("Content-Type", options.contentType ?? "application/json");
    } else if (options.contentType != null) {
      headers.set("Content-Type", options.contentType);
    }
    headers.set("Accept-Language", "en-US");
    headers.set("User-Agent", this.#config.userAgent);
    headers.set("Referer", "www.google.com");
    headers.set("memberId", this.#config.memberCode);
    return headers;
  }

  async request(options: NseRequestOptions): Promise<NseResponse> {
    const timeoutMs = positiveBoundedInteger(
      options.timeoutMs,
      defaultTimeoutMs,
    );
    const maxResponseBytes = positiveBoundedInteger(
      options.maxResponseBytes,
      defaultMaxResponseBytes,
    );
    const endpoint = endpointUrl(this.#config.baseUrl, options.path);
    const headers = this.#resolvedHeaders(options);
    headers.set(
      "Authorization",
      await createNseBasicAuthorization(this.#config),
    );

    let body: string | undefined;
    if (options.jsonBody !== undefined) body = JSON.stringify(options.jsonBody);
    if (options.bodyText !== undefined) body = options.bodyText;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      let response: Response;
      try {
        response = await this.#fetch(endpoint, {
          method: options.method,
          headers,
          body,
          signal: controller.signal,
        });
      } catch (_error) {
        throw new NseClientError(
          controller.signal.aborted
            ? "nse_request_timeout"
            : "nse_network_error",
        );
      }

      let responseBody: Uint8Array;
      try {
        responseBody = await readBoundedBody(response, maxResponseBytes);
      } catch (error) {
        if (controller.signal.aborted) {
          throw new NseClientError("nse_request_timeout", response.status);
        }
        if (error instanceof NseClientError) throw error;
        throw new NseClientError("nse_response_invalid", response.status);
      }

      if (!response.ok && !options.acceptHttpErrors) {
        throw new NseClientError("nse_http_error", response.status);
      }

      return {
        status: response.status,
        headers: response.headers,
        body: responseBody,
        safeHeaderMetadata: safeNseResponseHeaderMetadata(response.headers),
      };
    } finally {
      clearTimeout(timeout);
    }
  }
}
