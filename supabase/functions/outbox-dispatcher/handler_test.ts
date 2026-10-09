import { resolveConfig } from "./config.ts";
import {
  createHandler,
  type Notification,
  sign,
  signingInput,
} from "./handler.ts";
import { ROUTES } from "./routes.generated.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw Error(message);
}
const id = "11111111-1111-4111-8111-111111111111";
const token = "22222222-2222-4222-8222-222222222222";
const requestId = "33333333-3333-4333-8333-333333333333";
const key = "synthetic-notification-key-".repeat(3);
function settings(
  environment = "DEV",
  mode = "active",
): Record<string, string> {
  return {
    MONEYBOWL_ENV: environment,
    SUPABASE_URL: `https://synthetic-${environment.toLowerCase()}.supabase.co`,
    MONEYBOWL_SUPABASE_URL:
      `https://synthetic-${environment.toLowerCase()}.supabase.co`,
    NSE_URL: environment === "DEV"
      ? "https://nseinvestuat.nseindia.com"
      : "https://www.nseinvest.com",
    NSE_ALLOWED_READ_APIS: "[]",
    OUTBOX_DISPATCH_MODE: mode,
    OUTBOX_NOTIFICATION_KEY: key,
    SUPABASE_SERVICE_ROLE_KEY: `synthetic-${environment}-db-`.repeat(4),
    NSE_WORKER_TOKEN: `synthetic-${environment}-worker-`.repeat(4),
  };
}
function notification(patch: Partial<Notification> = {}): Notification {
  return {
    version: 1,
    request_id: requestId,
    issued_at: 1000,
    environment: "DEV",
    project_url: "https://synthetic-dev.supabase.co",
    kind: "event",
    event_outbox_id: id,
    hop: 0,
    ...patch,
  };
}
async function request(
  n = notification(),
  signatureKey = key,
): Promise<Request> {
  return new Request(
    `https://synthetic-dev.supabase.co/functions/v1/outbox-dispatcher/${n.kind}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Outbox-Signature": await sign(n, signatureKey),
      },
      body: JSON.stringify(n),
    },
  );
}
function harness(options: {
  env?: Record<string, string>;
  admission?: unknown;
  worker?: (init: RequestInit) => Promise<Response>;
  authorize?: boolean;
  dbFailure?: boolean;
} = {}) {
  const calls: { url: string; init: RequestInit }[] = [];
  const logs: unknown[] = [];
  const env = options.env ?? settings();
  const config = resolveConfig((name) => env[name]);
  const handler = createHandler(config, {
    now: () => 1000000,
    log: (entry) => logs.push(entry),
    fetch: (async (url, init) => {
      assert(init);
      calls.push({ url: String(url), init });
      assert(init.redirect === "error", "redirect permitted");
      assert(
        String(url).startsWith(config.origin + "/"),
        "cross-project fetch",
      );
      if (String(url).includes("/rest/")) {
        assert(
          (init.headers as Record<string, string>).apikey ===
            env.SUPABASE_SERVICE_ROLE_KEY,
        );
        if (options.dbFailure) throw Error("DO_NOT_LEAK_SECRET");
        if (String(url).endsWith("/admit_outbox_dispatch")) {
          return Response.json(
            options.admission ?? {
              code: "admitted",
              batch_token: token,
              candidates: [{
                event_outbox_id: id,
                event_type: Object.keys(ROUTES)[0],
              }],
            },
          );
        }
        if (String(url).endsWith("/authorize_outbox_dispatch")) {
          return Response.json(options.authorize ?? true);
        }
        return Response.json(true);
      }
      assert(
        (init.headers as Record<string, string>).Authorization ===
          `Bearer ${env.NSE_WORKER_TOKEN}`,
      );
      assert(
        JSON.stringify(JSON.parse(init.body as string)) ===
          JSON.stringify({ event_outbox_id: id }),
      );
      return options.worker
        ? await options.worker(init)
        : Response.json({ secret: "DO_NOT_LEAK_SECRET" });
    }) as typeof fetch,
  });
  return {
    handler,
    calls,
    logs,
    config,
    workerCalls: () => calls.filter((c) => c.url.includes("/functions/")),
  };
}
Deno.test("valid authenticated notification: metadata only, no event mutation", async () => {
  const h = harness();
  const response = await h.handler(await request());
  assert(response.status === 200);
  assert(h.workerCalls().length === 1);
  assert(h.calls.length === 4);
  assert(!JSON.stringify(h.logs).includes("DO_NOT_LEAK_SECRET"));
  assert(!JSON.stringify(h.config).includes(key));
});
for (const [event, worker] of Object.entries(ROUTES)) {
  Deno.test(`canonical route ${event}`, async () => {
    const h = harness({
      admission: {
        code: "admitted",
        batch_token: token,
        candidates: [{ event_outbox_id: id, event_type: event }],
      },
    });
    assert((await h.handler(await request())).status === 200);
    assert(h.workerCalls()[0].url.endsWith(`/functions/v1/${worker}`));
  });
}
for (const code of ["busy", "replay", "disabled"]) {
  Deno.test(`admission ${code} cannot execute workers`, async () => {
    const h = harness({ admission: { code } });
    assert((await h.handler(await request())).status === 202);
    assert(h.workerCalls().length === 0);
  });
}
for (
  const description of [
    "not found",
    "terminal",
    "already claimed",
    "retry ineligible",
    "out of order",
    "ambiguous write",
  ]
) {
  Deno.test(`DB excludes ${description}`, async () => {
    const h = harness({
      admission: { code: "admitted", batch_token: token, candidates: [] },
    });
    assert((await h.handler(await request())).status === 200);
    assert(h.workerCalls().length === 0);
    const finish = JSON.parse(h.calls.at(-1)!.init.body as string);
    assert(finish.p_next_hop === null);
  });
}
for (
  const patch of [
    { event_outbox_id: "bad" },
    { environment: "QA" },
    { project_url: "https://evil.invalid" },
    { issued_at: 699 },
    { issued_at: 1301 },
    { hop: 16 },
    { hop: 1 },
    { request_id: "bad\nlog-injection" },
    { version: 2 },
    { event_outbox_id: null },
  ]
) {
  Deno.test(`invalid notification ${JSON.stringify(patch)}`, async () => {
    const h = harness();
    assert(
      (await h.handler(
        await request(notification(patch as Partial<Notification>)),
      )).status === 400,
    );
    assert(h.calls.length === 0);
  });
}
Deno.test("missing authentication", async () => {
  const h = harness();
  assert(
    (await h.handler(
      new Request("https://a/outbox-dispatcher/event", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      }),
    )).status === 401,
  );
  assert(h.calls.length === 0);
});
Deno.test("invalid HMAC", async () => {
  const h = harness();
  assert(
    (await h.handler(await request(notification(), "different-key"))).status ===
      401,
  );
  assert(h.calls.length === 0);
});
Deno.test("method/content type/path and oversized or malformed bodies", async () => {
  const h = harness();
  assert(
    (await h.handler(new Request("https://a/outbox-dispatcher/event")))
      .status === 405,
  );
  const req = await request();
  assert(
    (await h.handler(
      new Request(req, { headers: { "content-type": "text/plain" } }),
    )).status === 415,
  );
  for (
    const body of [
      "{",
      "x".repeat(2049),
      JSON.stringify({ ...notification(), worker_url: "https://evil.invalid" }),
    ]
  ) {
    assert(
      (await h.handler(
        new Request("https://a/outbox-dispatcher/event", {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "x-outbox-signature": "a".repeat(64),
          },
          body,
        }),
      )).status === 400,
    );
  }
  assert(
    (await h.handler(
      new Request("https://a/outbox-dispatcher/unknown", { method: "POST" }),
    )).status === 404,
  );
  assert(h.calls.length === 0);
});
Deno.test("caller cannot move event signature to recovery", async () => {
  const n = notification();
  const req = await request(n);
  assert(
    (await harness().handler(
      new Request("https://a/outbox-dispatcher/recovery", req),
    )).status === 400,
  );
});
for (
  const candidates of [
    [{ event_outbox_id: id, event_type: "unknown" }],
    [{ event_outbox_id: id, event_type: "https://evil.invalid" }],
    [{ event_outbox_id: token, event_type: Object.keys(ROUTES)[0] }],
    Array.from(
      { length: 5 },
      () => ({ event_outbox_id: id, event_type: Object.keys(ROUTES)[0] }),
    ),
  ]
) {
  Deno.test(`untrusted feed rejected ${JSON.stringify(candidates)}`, async () => {
    const h = harness({
      admission: { code: "admitted", batch_token: token, candidates },
    });
    assert((await h.handler(await request())).status === 503);
    assert(h.workerCalls().length === 0);
  });
}
Deno.test("switch changed before send fails closed", async () => {
  const h = harness({ authorize: false });
  assert((await h.handler(await request())).status === 200);
  assert(h.workerCalls().length === 0);
});
for (const status of [200, 401, 404, 429, 500, 302]) {
  Deno.test(`worker HTTP ${status} never completes or retries event`, async () => {
    const h = harness({
      worker: () => Promise.resolve(new Response("secret", { status })),
    });
    assert((await h.handler(await request())).status === 200);
    assert(h.workerCalls().length === 1);
    assert(!JSON.stringify(h.logs).includes("secret"));
  });
}
for (
  const name of ["timeout", "transient network failure", "redirect rejection"]
) {
  Deno.test(`${name} retains lease, no immediate continuation or retry`, async () => {
    const h = harness({
      worker: () => Promise.reject(Error("DO_NOT_LEAK_SECRET")),
    });
    assert((await h.handler(await request())).status === 200);
    assert(h.workerCalls().length === 1);
    assert(!h.calls.some((c) => c.url.endsWith("/finish_outbox_dispatch")));
    assert(!JSON.stringify(h.logs).includes("DO_NOT_LEAK_SECRET"));
  });
}
Deno.test("database outage returns only static diagnostics", async () => {
  const h = harness({ dbFailure: true });
  const r = await h.handler(await request());
  assert(r.status === 503 && !(await r.text()).includes("DO_NOT_LEAK_SECRET"));
  assert(h.workerCalls().length === 0);
});
for (const environment of ["DEV", "QA", "PROD"]) {
  Deno.test(`same handler observes ${environment} with independent credentials`, async () => {
    const h = harness({ env: settings(environment, "observe") });
    assert(
      (await h.handler(
        await request(
          notification({ environment, project_url: h.config.origin }),
        ),
      )).status === 200,
    );
    assert(h.workerCalls().length === 0);
  });
  Deno.test(`${environment} disabled by default`, async () => {
    const env = settings(environment, "disabled");
    delete env.OUTBOX_DISPATCH_MODE;
    const h = harness({ env });
    assert(
      (await h.handler(
        await request(
          notification({ environment, project_url: h.config.origin }),
        ),
      )).status === 503,
    );
    assert(h.calls.length === 0);
  });
}
for (
  const patch of [
    { MONEYBOWL_ENV: "" },
    { MONEYBOWL_ENV: "STAGING" },
    { MONEYBOWL_ENV: "QA" },
    { MONEYBOWL_ENV: "PROD" },
    { NSE_URL: "https://www.nseinvest.com" },
    { MONEYBOWL_SUPABASE_URL: "https://wrong.supabase.co" },
    { SUPABASE_URL: "http://127.0.0.1" },
    { OUTBOX_DISPATCH_MODE: "true" },
    { OUTBOX_NOTIFICATION_KEY: "" },
    { NSE_WORKER_TOKEN: key },
    { SUPABASE_URL: "https://synthetic-dev.supabase.co:443" },
    { SUPABASE_URL: "https://synthetic-dev.supabase.co/?" },
  ]
) {
  Deno.test(`invalid source config sanitized ${Object.keys(patch)[0]}`, () => {
    const env: Record<string, string | undefined> = { ...settings(), ...patch };
    try {
      resolveConfig((name) => env[name]);
      throw Error("accepted");
    } catch (e) {
      assert(
        e instanceof Error && e.message === "outbox_configuration_invalid",
      );
    }
  });
}
Deno.test("recovery continuation bounded to 16 invocations", async () => {
  for (const hop of [0, 14, 15]) {
    const h = harness();
    assert(
      (await h.handler(
        await request(
          notification({ kind: "recovery", event_outbox_id: null, hop }),
        ),
      )).status === 200,
    );
    const finish = JSON.parse(h.calls.at(-1)!.init.body as string);
    assert(finish.p_next_hop === (hop < 15 ? hop + 1 : null));
  }
});
Deno.test("HMAC interoperable known canonical input", async () => {
  assert(
    signingInput(notification()) ===
      "1|33333333-3333-4333-8333-333333333333|1000|DEV|https://synthetic-dev.supabase.co|event|11111111-1111-4111-8111-111111111111|0",
  );
  assert(
    (await sign(notification(), key)) ===
      "057915b55737e31043c351d3bf6b27a0e9a67562959adaa1c35433b64959bf3d",
  );
});

Deno.test("four-way fanout is bounded and awaited before continuation", async () => {
  const config = resolveConfig((name) => settings()[name]);
  const ids = Array.from(
    { length: 4 },
    (_, i) => `10000000-0000-4000-8000-00000000000${i}`,
  );
  let active = 0;
  let maximum = 0;
  let completed = 0;
  let finish = false;
  const releases: (() => void)[] = [];
  const handler = createHandler(config, {
    now: () => 1000000,
    fetch: (async (url) => {
      if (String(url).endsWith("admit_outbox_dispatch")) {
        return Response.json({
          code: "admitted",
          batch_token: token,
          candidates: ids.map((event_outbox_id) => ({
            event_outbox_id,
            event_type: Object.keys(ROUTES)[0],
          })),
        });
      }
      if (String(url).endsWith("authorize_outbox_dispatch")) {
        return Response.json(true);
      }
      if (String(url).endsWith("finish_outbox_dispatch")) {
        assert(completed === 4 && active === 0);
        finish = true;
        return Response.json(true);
      }
      active++;
      maximum = Math.max(maximum, active);
      await new Promise<void>((resolve) => {
        releases.push(resolve);
        if (releases.length === 4) releases.forEach((release) => release());
      });
      active--;
      completed++;
      return new Response(null, { status: 200 });
    }) as typeof fetch,
  });
  assert(
    (await handler(
      await request(notification({ kind: "recovery", event_outbox_id: null })),
    )).status === 200,
  );
  assert(maximum === 4 && completed === 4 && finish);
});

Deno.test("actual worker timeout aborts and leaves admission for recovery", async () => {
  let aborted = false;
  const h = harness({
    worker: (init) =>
      new Promise<Response>((_, reject) => {
        assert(init.signal);
        init.signal.addEventListener("abort", () => {
          aborted = true;
          reject(Error("synthetic timeout"));
        }, { once: true });
      }),
  });
  const r = await h.handler(await request());
  assert(r.status === 200 && aborted);
  assert(!h.calls.some((c) => c.url.endsWith("finish_outbox_dispatch")));
});

Deno.test("slow request stream is cancelled at the body deadline", async () => {
  let cancelled = false;
  const h = harness();
  const body = new ReadableStream<Uint8Array>({
    cancel() {
      cancelled = true;
    },
  });
  const r = await h.handler(
    new Request("https://a/outbox-dispatcher/event", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Outbox-Signature": "a".repeat(64),
      },
      body,
    }),
  );
  assert(r.status === 400 && cancelled && h.calls.length === 0);
});

for (const environment of ["DEV", "QA", "PROD"]) {
  for (
    const mode of [
      "disabled",
      "observe",
      ...(environment === "DEV" ? ["active"] : []),
    ]
  ) {
    Deno.test(`commission readiness ${environment}/${mode} never accesses DB or workers`, async () => {
      const h = harness({ env: settings(environment, mode) });
      const n = notification({
        kind: "readiness",
        event_outbox_id: null,
        environment,
        project_url:
          `https://synthetic-${environment.toLowerCase()}.supabase.co`,
      });
      const first = await h.handler(await request(n));
      assert(first.status === 200);
      const body = await first.json();
      assert(body.code === "outbox_ready" && body.mode === mode);
      assert(JSON.stringify(body.routes) === JSON.stringify(ROUTES));
      assert(!JSON.stringify(body).includes(key));
      assert((await h.handler(await request(n))).status === 200);
      assert(h.calls.length === 0 && h.logs.length === 0);
    });
  }
}
Deno.test("commission readiness rejects invalid, missing and stale authentication", async () => {
  const h = harness();
  const n = notification({ kind: "readiness", event_outbox_id: null });
  assert((await h.handler(await request(n, "wrong-key"))).status === 401);
  const missing = await request(n);
  missing.headers.delete("X-Outbox-Signature");
  assert((await h.handler(missing)).status === 401);
  assert(
    (await h.handler(await request({ ...n, issued_at: 1 }))).status === 400,
  );
  assert(h.calls.length === 0 && h.logs.length === 0);
});
Deno.test("commission readiness signature cannot authorize recovery", async () => {
  const h = harness();
  const n = notification({ kind: "readiness", event_outbox_id: null });
  const signed = await request(n);
  const changedPath = new Request(
    "https://synthetic-dev.supabase.co/functions/v1/outbox-dispatcher/recovery",
    {
      method: "POST",
      headers: signed.headers,
      body: JSON.stringify(n),
    },
  );
  assert((await h.handler(changedPath)).status === 400);
  assert(h.calls.length === 0 && h.logs.length === 0);
});
