import {
  assert,
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  captureNseMasterDownload,
  NSE_MASTER_CHUNK_BYTES,
  NSE_MASTER_FILE_TYPES,
  NSE_MASTER_MAX_BYTES,
  NSE_MASTER_PATH,
  NSE_MASTER_VARIANTS,
  type NseMasterCapture,
  NseMasterError,
  type NseMasterEvidenceStore,
  nseMasterRequest,
  type NseMasterScope,
  nseMasterSha256,
} from "./nse_master_download.ts";
import { createNseMasterEvidenceStore } from "./nse_master_evidence.ts";
import { NseClient } from "./nse_client.ts";
const config = {
  environment: "DEV" as const,
  allowedReadApis: [],
  baseUrl: "https://nseinvestuat.nseindia.com",
  memberCode: "05418",
  loginUserId: "SYNTHETIC_LOGIN",
  apiKeyMember: "SYNTHETIC_KEY",
  apiSecretUser: "SYNTHETIC_SECRET",
  userAgent: "MoneyBowl",
};
const scope: NseMasterScope = {
  workspaceId: "workspace-one",
  connectionId: "connection-one",
  callId: "call-one",
  environment: "UAT",
  fileType: "SCH",
};
function memoryStore() {
  const chunks: Uint8Array[] = [];
  const results: NseMasterCapture[] = [];
  let beginCount = 0;
  const store: NseMasterEvidenceStore = {
    async begin(s) {
      beginCount++;
      return {
        download_id: s.callId,
        request_body: nseMasterRequest(s.fileType),
      };
    },
    async append(_s, ordinal, bytes, hash) {
      assertEquals(hash, await nseMasterSha256(bytes));
      assertEquals(ordinal, chunks.length);
      chunks.push(bytes.slice());
    },
    async finish(_s, result) {
      results.push({ ...result });
    },
  };
  return { store, chunks, results, begins: () => beginCount };
}
function response(
  bytes: Uint8Array,
  headers: Record<string, string> = {},
  status = 200,
) {
  return new Response(new Uint8Array(bytes), {
    status,
    headers: {
      "content-type": "text/plain",
      "content-length": String(bytes.length),
      ...headers,
    },
  });
}
const encoder = new TextEncoder();
for (const fileType of NSE_MASTER_FILE_TYPES) {
  Deno.test(`MASTER_DOWNLOAD ${fileType}: exact request and independent parser/publication identity`, async () => {
    const mem = memoryStore();
    let sends = 0;
    const raw = encoder.encode("\ufeffscheme|value\r\nA|12.00\r\n");
    const result = await captureNseMasterDownload(
      config,
      { ...scope, fileType },
      mem.store,
      (url, init) => {
        sends++;
        assertEquals(String(url), config.baseUrl + NSE_MASTER_PATH);
        assertEquals(init?.method, "POST");
        assertEquals(init?.redirect, "error");
        assertEquals(init?.body, `{"file_type":"${fileType}"}`);
        const headers = new Headers(init?.headers);
        assert(headers.get("Authorization")?.startsWith("Basic "));
        assertEquals(headers.get("memberId"), config.memberCode);
        assertEquals(headers.get("Accept-Encoding"), "identity");
        return Promise.resolve(response(raw));
      },
    );
    assertEquals(sends, 1);
    assertEquals(result.kind, "COMPLETE");
    assertEquals(mem.chunks[0], raw);
    assertEquals(result.sha256, await nseMasterSha256(raw));
    assertEquals(NSE_MASTER_VARIANTS[fileType].parser, fileType);
    assertEquals(
      new Set(Object.values(NSE_MASTER_VARIANTS).map((v) => v.publication))
        .size,
      6,
    );
  });
}
Deno.test("MASTER_DOWNLOAD allowlist rejects normalization, extra fields and unknown variants", () => {
  for (
    const value of ["nav", "SCH ", "SCH|NAV", "", null, {}, {
      file_type: "SCH",
      investor: "dummy",
    }]
  ) assertThrows(() => nseMasterRequest(value), NseMasterError);
  assertEquals(NSE_MASTER_VARIANTS.NAV.header, "absent");
  assertEquals(NSE_MASTER_VARIANTS.SET.header, "uncharacterized");
});
for (const length of [4_057_995, NSE_MASTER_MAX_BYTES]) {
  Deno.test(`MASTER_DOWNLOAD exact ${length} bytes survives multibyte and arbitrary stream splits`, async () => {
    const raw = new Uint8Array(length).fill(65);
    raw.set(encoder.encode("₹|\r\n"), 262142);
    let offset = 0;
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (offset === raw.length) {
          controller.close();
          return;
        }
        const end = Math.min(offset + 177777, raw.length);
        controller.enqueue(raw.slice(offset, end));
        offset = end;
      },
    });
    const mem = memoryStore();
    const result = await captureNseMasterDownload(
      config,
      scope,
      mem.store,
      () =>
        Promise.resolve(
          new Response(stream, {
            headers: { "content-length": String(length) },
          }),
        ),
    );
    assertEquals(result.kind, "COMPLETE");
    assertEquals(result.sha256, await nseMasterSha256(raw));
    assertEquals(mem.chunks.reduce((sum, b) => sum + b.length, 0), length);
    assert(mem.chunks.every((b) => b.length <= NSE_MASTER_CHUNK_BYTES));
    assertEquals(mem.chunks.length, Math.ceil(length / NSE_MASTER_CHUNK_BYTES));
  });
}
Deno.test("MASTER_DOWNLOAD declared oversize cancels before reading or persisting body", async () => {
  let cancelled = false;
  const mem = memoryStore();
  const stream = new ReadableStream<Uint8Array>({
    cancel() {
      cancelled = true;
    },
  });
  const result = await captureNseMasterDownload(
    config,
    scope,
    mem.store,
    () =>
      Promise.resolve(
        new Response(stream, {
          headers: { "content-length": String(NSE_MASTER_MAX_BYTES + 1) },
        }),
      ),
  );
  assertEquals(result.kind, "OVERSIZE");
  assertEquals(result.sha256, null);
  assertEquals(mem.chunks.length, 0);
  assert(cancelled);
});
Deno.test("MASTER_DOWNLOAD observed oversize never seals a partial prefix as complete", async () => {
  const mem = memoryStore();
  const result = await captureNseMasterDownload(
    config,
    scope,
    mem.store,
    () =>
      Promise.resolve(
        response(new Uint8Array(NSE_MASTER_MAX_BYTES + 1), {
          "content-length": String(NSE_MASTER_MAX_BYTES),
        }),
      ),
  );
  assertEquals(result.kind, "OVERSIZE");
  assertEquals(result.eof, false);
  assertEquals(result.sha256, null);
});
for (const declared of [1, 99]) {
  Deno.test(`MASTER_DOWNLOAD length mismatch ${declared} rejects completion`, async () => {
    const mem = memoryStore();
    const result = await captureNseMasterDownload(
      config,
      scope,
      mem.store,
      () =>
        Promise.resolve(
          response(encoder.encode("a|b\n"), {
            "content-length": String(declared),
          }),
        ),
    );
    assertEquals(result.kind, "TRUNCATED");
    assertEquals(result.sha256, null);
  });
}
Deno.test("MASTER_DOWNLOAD bounded identity EOF without Content-Length completes", async () => {
  const mem = memoryStore();
  const raw = encoder.encode("a|b\n");
  const result = await captureNseMasterDownload(
    config,
    scope,
    mem.store,
    () => Promise.resolve(new Response(raw)),
  );
  assertEquals(result.kind, "COMPLETE");
  assertEquals(result.declaredBytes, null);
  assertEquals(result.eof, true);
  assertEquals(result.sha256, await nseMasterSha256(raw));
  assertEquals(mem.chunks.length, 1);
});
for (
  const headers of [
    { "content-length": "junk" },
    { "content-length": "4", "content-encoding": "gzip" },
    { "content-length": "1e3" },
    { "content-length": "-1" },
  ]
) {
  Deno.test(`MASTER_DOWNLOAD unverifiable framing ${JSON.stringify(headers)} fails closed`, async () => {
    const mem = memoryStore();
    const result = await captureNseMasterDownload(
      config,
      scope,
      mem.store,
      () =>
        Promise.resolve(
          new Response("a|b\n", { headers: headers as Record<string, string> }),
        ),
    );
    assertEquals(result.kind, "UNVERIFIABLE");
    assertEquals(mem.chunks.length, 0);
  });
}
Deno.test("MASTER_DOWNLOAD broken stream preserves acknowledged prefix and records no full digest", async () => {
  const mem = memoryStore();
  let reads = 0;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (reads++ === 0) {
        controller.enqueue(new Uint8Array(NSE_MASTER_CHUNK_BYTES));
      } else controller.error(new Error(config.apiSecretUser));
    },
  }, { highWaterMark: 0 });
  const result = await captureNseMasterDownload(
    config,
    scope,
    mem.store,
    () =>
      Promise.resolve(
        new Response(stream, {
          headers: { "content-length": String(NSE_MASTER_CHUNK_BYTES * 2) },
        }),
      ),
  );
  assertEquals(result.kind, "TRANSPORT_FAILED");
  assertEquals(result.sha256, null);
  assertEquals(mem.chunks.length, 1);
  assert(!JSON.stringify(result).includes(config.apiSecretUser));
});
Deno.test("MASTER_DOWNLOAD HTTP/JSON failures retain exact evidence without declaring business success", async () => {
  const mem = memoryStore();
  const raw = encoder.encode('{"response_status":"F"}');
  const result = await captureNseMasterDownload(
    config,
    scope,
    mem.store,
    () =>
      Promise.resolve(
        response(raw, {
          "content-type": "application/json",
          "Set-Cookie": "SECRET",
        }, 503),
      ),
  );
  assertEquals(result.kind, "COMPLETE");
  assertEquals(result.httpStatus, 503);
  assertEquals(result.mediaType, "JSON");
  assertEquals(mem.chunks[0], raw);
  assert(!JSON.stringify(result).includes("SECRET"));
});
Deno.test("MASTER_DOWNLOAD scope/credential binding denial happens before HTTP", async () => {
  const mem = memoryStore();
  mem.store.begin = () => Promise.reject(new Error("scope_invalid"));
  let sends = 0;
  await assertRejects(
    () =>
      captureNseMasterDownload(config, scope, mem.store, () => {
        sends++;
        throw new Error();
      }),
    NseMasterError,
  );
  assertEquals(sends, 0);
  await assertRejects(
    () =>
      captureNseMasterDownload(
        { ...config, baseUrl: "https://user:secret@nse.example.test" },
        scope,
        mem.store,
      ),
    NseMasterError,
  );
});
Deno.test("MASTER_DOWNLOAD lost persistence acknowledgements retry only persistence, never HTTP", async () => {
  const mem = memoryStore();
  let begins = 0;
  let finishes = 0;
  let sends = 0;
  const tokens: string[] = [];
  const begin = mem.store.begin;
  const finish = mem.store.finish;
  mem.store.begin = async (s, binding) => {
    tokens.push(binding.captureToken);
    if (begins++ === 0) throw new Error("lost_ack");
    return await begin(s, binding);
  };
  mem.store.finish = async (s, c) => {
    if (finishes++ === 0) throw new Error("lost_ack");
    return await finish(s, c);
  };
  await captureNseMasterDownload(config, scope, mem.store, () => {
    sends++;
    return Promise.resolve(response(encoder.encode("a|b\n")));
  });
  assertEquals(sends, 1);
  assertEquals(begins, 2);
  assertEquals(finishes, 2);
  assertEquals(tokens[0], tokens[1]);
});
Deno.test("MASTER_DOWNLOAD permanent chunk persistence failure cannot produce a sealed result", async () => {
  const mem = memoryStore();
  let attempts = 0;
  mem.store.append = () => {
    attempts++;
    return Promise.reject(new Error(config.apiSecretUser));
  };
  await assertRejects(
    () =>
      captureNseMasterDownload(
        config,
        scope,
        mem.store,
        () => Promise.resolve(response(encoder.encode("a|b\n"))),
      ),
    NseMasterError,
    "nse_reference_persistence_failed",
  );
  assertEquals(attempts, 2);
  assertEquals(mem.results.length, 0);
});
Deno.test("MASTER_DOWNLOAD persistence adapter forwards only explicit non-secret scope and evidence", async () => {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const store = createNseMasterEvidenceStore({
    rpc(name, args) {
      calls.push({ name, args });
      return Promise.resolve({
        data: name === "begin_nse_master_download"
          ? { download_id: scope.callId, request_body: nseMasterRequest("SCH") }
          : {},
        error: null,
      });
    },
  });
  await captureNseMasterDownload(
    config,
    scope,
    store,
    () =>
      Promise.resolve(
        response(encoder.encode("a|b\n"), {
          Authorization: "SECRET",
          "Set-Cookie": "SECRET",
        }),
      ),
  );
  const serialized = JSON.stringify(calls);
  for (
    const secret of [
      config.apiSecretUser,
      config.apiKeyMember,
      config.loginUserId,
      "Authorization",
      "Set-Cookie",
      "SECRET",
    ]
  ) assert(!serialized.includes(secret));
  assertEquals(calls.map((c) => c.name), [
    "begin_nse_master_download",
    "append_nse_master_chunk",
    "finish_nse_master_download",
  ]);
  assertEquals(calls[1].args.p_base64, btoa("a|b\n"));
});
Deno.test("MASTER_DOWNLOAD separate capture does not weaken bounded report client", async () => {
  const client = new NseClient(
    config,
    () => Promise.resolve(response(new Uint8Array(1024 * 1024 + 1))),
  );
  await assertRejects(
    () =>
      client.request({
        method: "POST",
        path: "/reports",
        maxResponseBytes: 1024 * 1024,
      }),
    Error,
  );
});

Deno.test("QA/PROD streaming download cannot write UAT evidence or invoke the network", async () => {
  for (const environment of ["QA", "PROD"] as const) {
    const mem = memoryStore();
    let begins = 0;
    let sends = 0;
    mem.store.begin = () => {
      begins++;
      throw new Error("must not persist");
    };
    await assertRejects(() =>
      captureNseMasterDownload(
        {
          ...config,
          environment,
          baseUrl: "https://www.nseinvest.com",
          allowedReadApis: ["MASTER_DOWNLOAD"],
        },
        scope,
        mem.store,
        () => {
          sends++;
          throw new Error("must not send");
        },
      ), NseMasterError);
    assertEquals(begins, 0);
    assertEquals(sends, 0);
  }
});
