import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createNseEvidenceCall } from "./nse_evidence_call.ts";

Deno.test("attempt-local evidence retries a callback once with stable callback state", async () => {
  let callbacks = 0;
  const call = createNseEvidenceCall(() => Promise.resolve("submitted"));
  const stable = { callId: "call-1", startedAt: "2026-09-01T00:00:00Z" };
  const persisted = await call.persist(() => {
    callbacks++;
    if (callbacks === 1) return Promise.reject(new Error("ack_lost"));
    return Promise.resolve(stable);
  });
  assertEquals(callbacks, 2);
  assertEquals(persisted, stable);
});

Deno.test("attempt-local evidence stops after two failed callbacks and caches one submission", async () => {
  let callbacks = 0;
  let submissions = 0;
  const call = createNseEvidenceCall(async () => {
    submissions++;
    return "submitted";
  });
  await assertRejects(
    () =>
      call.persist(() => {
        callbacks++;
        return Promise.reject(new Error("stale_ownership"));
      }),
  );
  assertEquals(callbacks, 2);
  assertEquals(await call.submit(), "submitted");
  assertEquals(await call.submit(), "submitted");
  assertEquals(submissions, 1);
});
