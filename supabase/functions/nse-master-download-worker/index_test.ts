import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createNseMasterDownloadHandler } from "./handler.ts";
import { createMasterPersistence } from "./adapters.ts";
import type { MasterClaim, MasterPersistence } from "./types.ts";
import type { NseMasterCapture } from "../_shared/nse/nse_master_download.ts";
const eventId = "b0620000-0000-4000-8000-000000000001";
const token = "b0620000-0000-4000-8000-000000000002";
const config = {
  baseUrl: "https://nse.example.test",
  memberCode: "05418",
  loginUserId: "SYNTHETIC",
  apiKeyMember: "SYNTHETIC",
  apiSecretUser: "SYNTHETIC",
  userAgent: "test",
};
const scope = {
  workspaceId: eventId,
  connectionId: eventId,
  callId: eventId,
  environment: "UAT" as const,
  fileType: "SCH" as const,
};
function fixture(action: MasterClaim["action"] = "CAPTURE") {
  const calls: string[] = [];
  const captures: NseMasterCapture[] = [];
  const persistence: MasterPersistence = {
    async claim(id, claimToken) {
      assertEquals(id, eventId);
      assertEquals(claimToken, token);
      calls.push("claim");
      return action === "DONE" || action === "BUSY"
        ? { action }
        : { action, eventId, scope };
    },
    evidence(id, claimToken) {
      assertEquals(id, eventId);
      assertEquals(claimToken, token);
      return {
        async begin(s) {
          calls.push("begin");
          return { download_id: s.callId, request_body: '{"file_type":"SCH"}' };
        },
        async append() {
          calls.push("append");
        },
        async finish(_s, capture) {
          calls.push("seal");
          captures.push(capture);
        },
      };
    },
    async finalize() {
      calls.push("finalize");
      return { outcome: "STAGED_VALIDATED", snapshot_id: eventId };
    },
  };
  const handler = () =>
    createNseMasterDownloadHandler({
      internalToken: "internal",
      config,
      persistence,
      uuid: () => token,
      fetcher: (_url, init) => {
        calls.push("http");
        assertEquals(init?.body, '{"file_type":"SCH"}');
        return Promise.resolve(
          new Response("a|b\n", {
            headers: { "content-type": "text/plain", "content-length": "4" },
          }),
        );
      },
    });
  const request = (
    body: unknown = { event_outbox_id: eventId },
    auth = "Bearer internal",
  ) =>
    new Request("https://worker.invalid", {
      method: "POST",
      headers: { authorization: auth },
      body: JSON.stringify(body),
    });
  return { calls, captures, persistence, handler, request };
}
Deno.test("master worker: exact evidence precedes SQL validation, publication blocked", async () => {
  const f = fixture();
  const response = await f.handler()(f.request());
  assertEquals(response.status, 200);
  assertEquals(f.calls, [
    "claim",
    "begin",
    "http",
    "append",
    "seal",
    "finalize",
  ]);
  assertEquals(f.captures[0].kind, "COMPLETE");
  assertEquals((await response.json()).data.publication_gate, "BLOCKED");
});
for (const action of ["DONE", "BUSY", "FINALIZE"] as const) {
  Deno.test(`master worker: ${action} never resends HTTP`, async () => {
    const f = fixture(action);
    await f.handler()(f.request());
    assertEquals(
      f.calls,
      action === "FINALIZE" ? ["claim", "finalize"] : ["claim"],
    );
  });
}
Deno.test("master worker: authorization and input limits before persistence", async () => {
  const f = fixture();
  assertEquals(
    (await f.handler()(f.request(undefined, "Bearer wrong"))).status,
    403,
  );
  for (
    const value of [
      null,
      [],
      {},
      { event_outbox_id: "bad" },
      { event_outbox_id: eventId, file_type: "NAV" },
      { event_outbox_id: eventId, connection_id: eventId },
      "x".repeat(257),
    ]
  ) assertEquals((await f.handler()(f.request(value))).status, 400);
  assertEquals(f.calls, []);
});
Deno.test("master worker: claim acknowledgement retries use same token", async () => {
  const f = fixture();
  const claim = f.persistence.claim;
  let n = 0;
  f.persistence.claim = async (...args) => {
    const r = await claim(...args);
    if (!n++) throw new Error("lost");
    return r;
  };
  assertEquals((await f.handler()(f.request())).status, 200);
  assertEquals(f.calls.filter((v) => v === "http").length, 1);
});
Deno.test("master worker: begin failure cannot call NSE and leaks no error text", async () => {
  const f = fixture();
  const evidence = f.persistence.evidence;
  f.persistence.evidence = (...args) => ({
    ...evidence(...args),
    begin: () => Promise.reject(new Error("provider secret")),
  });
  const r = await f.handler()(f.request());
  assertEquals(r.status, 500);
  assert(!f.calls.includes("http"));
  assert(!(await r.text()).includes("secret"));
});
Deno.test("master worker: failed evidence sealing never validates", async () => {
  const f = fixture();
  const evidence = f.persistence.evidence;
  f.persistence.evidence = (...args) => ({
    ...evidence(...args),
    finish: () => Promise.reject(new Error("lost")),
  });
  assertEquals((await f.handler()(f.request())).status, 500);
  assert(!f.calls.includes("finalize"));
  assertEquals(f.calls.filter((v) => v === "http").length, 1);
});
Deno.test("master worker: final acknowledgement retry never recaptures", async () => {
  const f = fixture();
  const finalize = f.persistence.finalize;
  let n = 0;
  f.persistence.finalize = async (...args) => {
    const r = await finalize(...args);
    if (!n++) throw new Error("lost");
    return r;
  };
  assertEquals((await f.handler()(f.request())).status, 200);
  assertEquals(f.calls.filter((v) => v === "http").length, 1);
  assertEquals(f.calls.filter((v) => v === "finalize").length, 2);
});
Deno.test("master adapter: SQL-loaded scope and lease wrappers only", async () => {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const p = createMasterPersistence({
    rpc(name, args) {
      calls.push({ name, args });
      return Promise.resolve({
        error: null,
        data: name === "claim_nse_master_download"
          ? {
            action: "CAPTURE",
            event_outbox_id: eventId,
            workspace_id: eventId,
            connection_id: eventId,
            download_id: eventId,
            file_type: "SCH",
            environment: "UAT",
          }
          : name === "begin_nse_master_job_capture"
          ? { download_id: eventId, request_body: '{"file_type":"SCH"}' }
          : { outcome: "REJECTED", snapshot_id: eventId },
      });
    },
  });
  assertEquals((await p.claim(eventId, token)).action, "CAPTURE");
  const e = p.evidence(eventId, token);
  await e.begin(scope, {
    memberCode: config.memberCode,
    baseUrl: config.baseUrl,
    captureToken: token,
  });
  await e.append(scope, 0, new Uint8Array([1, 2]), "abc");
  await e.finish(scope, {
    kind: "TRUNCATED",
    httpStatus: 200,
    mediaType: "TEXT",
    declaredBytes: 3,
    identityEncoding: true,
    eof: true,
    sha256: null,
  });
  await p.finalize(eventId, token);
  assertEquals(calls.map((x) => x.name), [
    "claim_nse_master_download",
    "begin_nse_master_job_capture",
    "append_nse_master_job_chunk",
    "finish_nse_master_job_capture",
    "finalize_nse_master_download",
  ]);
  for (const { args } of calls) {
    assertEquals(args.p_event_outbox_id, eventId);
    assertEquals(args.p_claim_token, token);
    for (
      const key of [
        "p_workspace_id",
        "p_connection_id",
        "p_download_id",
        "p_file_type",
        "p_call_id",
      ]
    ) assert(!(key in args));
  }
  assertEquals(calls[2].args.p_base64, "AQI=");
});
for (
  const patch of [
    { action: "unknown" },
    { environment: "PRODUCTION" },
    { file_type: "sch" },
    { workspace_id: "bad" },
    { event_outbox_id: token },
  ]
) {
  Deno.test(`master adapter: rejects bad claim ${JSON.stringify(patch)}`, async () => {
    const p = createMasterPersistence({
      rpc: () =>
        Promise.resolve({
          error: null,
          data: {
            action: "CAPTURE",
            event_outbox_id: eventId,
            workspace_id: eventId,
            connection_id: eventId,
            download_id: eventId,
            file_type: "SCH",
            environment: "UAT",
            ...patch,
          },
        }),
    });
    await assertRejects(() => p.claim(eventId, token));
  });
}
Deno.test("master adapter: rejects missing acknowledgement, RPC error and forged publication", async () => {
  for (
    const result of [
      { error: new Error("secret"), data: {} },
      { error: null, data: null },
      { error: null, data: { outcome: "PUBLISHED", snapshot_id: eventId } },
      { error: null, data: { outcome: "STAGED_VALIDATED", snapshot_id: null } },
    ]
  ) {
    const p = createMasterPersistence({ rpc: () => Promise.resolve(result) });
    await assertRejects(() => p.finalize(eventId, token));
  }
});
