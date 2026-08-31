import { NseClientError } from "../_shared/nse/nse_client.ts";
import { NseConfigError } from "../_shared/nse/nse_config.ts";
import type { NseResponse } from "../_shared/nse/nse_types.ts";

export type NseUatSmokeTestDependencies = {
  smokeTestToken: string;
  execute: () => Promise<NseResponse>;
};

const previewByteLimit = 256;
const previewCharacterLimit = 200;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function stripControlCharacters(
  value: string,
  preserveWhitespace: boolean,
): string {
  return Array.from(value).filter((character) => {
    const code = character.charCodeAt(0);
    if (code === 127) return false;
    if (code >= 32) return true;
    return preserveWhitespace && (code === 9 || code === 10 || code === 13);
  }).join("");
}

function safeContentType(headers: Headers): string {
  const contentType = headers.get("content-type")?.trim() ?? "";
  if (contentType.length === 0 || contentType.length > 128) {
    return "application/octet-stream";
  }
  return stripControlCharacters(contentType, false);
}

function safePreview(body: Uint8Array): string {
  const decoded = new TextDecoder().decode(body.slice(0, previewByteLimit));
  return stripControlCharacters(decoded, true)
    .slice(0, previewCharacterLimit);
}

export function createNseUatSmokeTestHandler(
  dependencies: NseUatSmokeTestDependencies,
): (request: Request) => Promise<Response> {
  return async (request: Request) => {
    if (request.method !== "POST") {
      return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
    }

    const token = request.headers.get("X-NSE-Smoke-Token");
    if (
      dependencies.smokeTestToken.length === 0 || token == null ||
      token !== dependencies.smokeTestToken
    ) {
      return jsonResponse({ error: { code: "not_authorized" } }, 403);
    }

    try {
      const result = await dependencies.execute();
      return jsonResponse({
        success: true,
        nseStatus: result.status,
        responseBytes: result.body.byteLength,
        contentType: safeContentType(result.headers),
        preview: safePreview(result.body),
      });
    } catch (error) {
      if (error instanceof NseConfigError) {
        return jsonResponse({
          success: false,
          nseStatus: null,
          error: { code: error.code },
        }, 500);
      }

      if (error instanceof NseClientError) {
        const status = error.code === "nse_request_timeout" ? 504 : 502;
        return jsonResponse({
          success: false,
          nseStatus: error.nseStatus,
          error: { code: error.code },
        }, status);
      }

      return jsonResponse({
        success: false,
        nseStatus: null,
        error: { code: "nse_smoke_test_failed" },
      }, 500);
    }
  };
}
