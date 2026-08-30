import { inspectCamsDbf } from "./parser.ts";
import {
  assertNoTrustedPlaintextPayload,
  jsonResponse,
  sha256Hex,
  verifyInternalInvocation,
} from "./security.ts";
import { IngestionError } from "./types.ts";

const hostedDevUrl = "https://rskryngwzyuzmiwtriyy.supabase.co";
const targets = new Map([
  ["a03b93fcb2d5c8063863f2618cefdcb1666559ba1c918348a85350b01cd8d1b2", {
    size: 362750,
    path:
      "3c72a865-9c05-4054-b87f-f590c0b70766/53abd16f-7e77-4bd4-afb0-0512a801f3ce/a03b93fcb2d5c8063863f2618cefdcb1666559ba1c918348a85350b01cd8d1b2",
  }],
  ["4b5ddace0f496c0e7aed4e21476916e93f407cb9f3336c27c6439a1aa435d90c", {
    size: 71881,
    path:
      "3c72a865-9c05-4054-b87f-f590c0b70766/53abd16f-7e77-4bd4-afb0-0512a801f3ce/4b5ddace0f496c0e7aed4e21476916e93f407cb9f3336c27c6439a1aa435d90c",
  }],
]);

export function createHostedDevCamsDbfDiagnosticHandler(deps: {
  internalToken: string;
  projectUrl: string;
  readOriginal(input: { bucket: string; path: string }): Promise<Uint8Array>;
  /** Test seam. Production deliberately uses only the module's fixed allowlist. */
  targets?: ReadonlyMap<string, { size: number; path: string }>;
}): (req: Request) => Promise<Response> {
  return async (req) => {
    try {
      if (
        req.method !== "POST" ||
        deps.projectUrl.replace(/\/$/, "") !== hostedDevUrl
      ) throw new IngestionError("not_authorized");
      await verifyInternalInvocation(req, deps.internalToken);
      let body: { sha256?: unknown };
      try {
        body = await req.json();
      } catch (_error) {
        throw new IngestionError("not_authorized");
      }
      assertNoTrustedPlaintextPayload(body as Record<string, unknown>);
      if (
        typeof body.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(body.sha256)
      ) throw new IngestionError("not_authorized");
      const target = (deps.targets ?? targets).get(body.sha256);
      if (target == null) throw new IngestionError("not_authorized");
      const bytes = await deps.readOriginal({
        bucket: "ingested-documents",
        path: target.path,
      });
      if (
        bytes.byteLength !== target.size ||
        await sha256Hex(bytes) !== body.sha256
      ) throw new IngestionError("not_authorized");
      return jsonResponse({
        data: {
          size: target.size,
          sha256: body.sha256,
          ...inspectCamsDbf(bytes),
        },
      });
    } catch (_error) {
      return jsonResponse({ error: { code: "not_authorized" } }, 403);
    }
  };
}
