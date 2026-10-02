import {
  assert,
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { NseMasterError, nseMasterSha256 } from "./nse_master_download.ts";
import { createNseSystematicMasterService } from "./nse_systematic_master_service.ts";
import { SIP_CELLS, SIP_HEADER } from "./nse_systematic_masters_fixtures.ts";
const id = (n: number) =>
  `b0630000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const scope = {
  workspaceId: id(1),
  connectionId: id(2),
  snapshotId: id(3),
  fileType: "SIP" as const,
};
async function fixture(
  change?: (name: string, data: Record<string, unknown>) => void,
  fail?: string,
) {
  const bytes = new TextEncoder().encode(
    SIP_HEADER + "\r\n" + SIP_CELLS.join("|") + "\r\n",
  );
  const hash = await nseMasterSha256(bytes);
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  // Split inside the multibyte rupee symbol; decoding must happen only after assembly.
  const split = bytes.findIndex((b) => b === 0xe2) + 1;
  const chunks = [bytes.slice(0, split), bytes.slice(split)];
  const receipt = {
    snapshot_id: scope.snapshotId,
    workspace_id: scope.workspaceId,
    connection_id: scope.connectionId,
    file_type: "SIP",
    version: 1,
    download_id: id(4),
    parser_version: "nse-systematic-web-v1",
    layout_id: "NSE_WEB_SIP_V1",
    source_sha256: hash,
    source_bytes: bytes.length,
    row_count: 1,
    rejected_rows: 0,
    authority: "REFERENCE_ONLY",
  };
  const service = createNseSystematicMasterService({
    async rpc(name, args) {
      calls.push({ name, args });
      let data: Record<string, unknown>;
      if (name === "get_nse_reference_snapshot") {
        data = {
          ...receipt,
          stage: "STAGED_UNVALIDATED",
          response_bytes: bytes.length,
          response_sha256: hash,
          chunk_count: 2,
        };
      } else if (name === "read_nse_master_chunk") {
        const b = chunks[Number(args.p_ordinal)];
        data = {
          base64: btoa(String.fromCharCode(...b)),
          byte_count: b.length,
          sha256: await nseMasterSha256(b),
        };
      } else data = { ...receipt, is_current: true };
      change?.(name, data);
      return {
        data,
        error: fail === name
          ? { message: "private provider diagnostic" }
          : null,
      };
    },
  });
  return { service, calls };
}
Deno.test("service consumes immutable B06.1 evidence then validates and CAS-publishes", async () => {
  const { service, calls } = await fixture();
  const r = await service.publish(scope, null);
  assertEquals(r.parsed.rows[0].schemeName, "Synthetic Growth ₹");
  assertEquals(r.isCurrent, true);
  assertEquals(calls.map((c) => c.name), [
    "get_nse_reference_snapshot",
    "read_nse_master_chunk",
    "read_nse_master_chunk",
    "validate_nse_systematic_snapshot",
    "publish_nse_systematic_snapshot",
  ]);
  assertEquals(calls.at(-1)?.args, {
    p_workspace_id: scope.workspaceId,
    p_snapshot_id: scope.snapshotId,
    p_expected_current_snapshot_id: null,
  });
  assert(Object.isFrozen(r));
});
for (
  const [field, value] of Object.entries({
    workspace_id: id(9),
    connection_id: id(9),
    snapshot_id: id(9),
    file_type: "STP",
    stage: "PUBLISHED",
    response_bytes: 17000000,
    chunk_count: 65,
    version: 0,
    response_sha256: "0".repeat(64),
    download_id: "invalid",
  })
) {
  Deno.test(`service rejects manifest ${field} mismatch`, async () => {
    const { service, calls } = await fixture((name, d) => {
      if (name === "get_nse_reference_snapshot") d[field] = value;
    });
    await assertRejects(
      () => service.publish(scope, null),
      NseMasterError,
      "manifest_mismatch",
    );
    assert(
      !calls.some((c) =>
        c.name.includes("validate_nse") || c.name.includes("publish_nse")
      ),
    );
  });
}
for (
  const [field, value] of Object.entries({
    sha256: "0".repeat(64),
    byte_count: 0,
    base64: "!!!!",
  })
) {
  Deno.test(`service rejects corrupted chunk ${field}`, async () => {
    const { service } = await fixture((name, d) => {
      if (name === "read_nse_master_chunk") d[field] = value;
    });
    await assertRejects(
      () => service.validate(scope),
      NseMasterError,
      "manifest_mismatch",
    );
  });
}
Deno.test("service rejects a forged validation receipt before publication", async () => {
  const { service, calls } = await fixture((name, d) => {
    if (name === "validate_nse_systematic_snapshot") d.row_count = 2;
  });
  await assertRejects(
    () => service.publish(scope, null),
    NseMasterError,
    "manifest_mismatch",
  );
  assert(!calls.some((c) => c.name === "publish_nse_systematic_snapshot"));
});
Deno.test("historical publication replay is explicitly not current", async () => {
  const { service } = await fixture((name, d) => {
    if (name === "publish_nse_systematic_snapshot") d.is_current = false;
  });
  assertEquals((await service.publish(scope, id(5))).isCurrent, false);
});
Deno.test("persistence failure is sanitized and never auto-retried", async () => {
  const { service, calls } = await fixture(
    undefined,
    "publish_nse_systematic_snapshot",
  );
  await assertRejects(
    () => service.publish(scope, null),
    NseMasterError,
    "nse_systematic_persistence_failed",
  );
  assertEquals(
    calls.filter((c) => c.name === "publish_nse_systematic_snapshot").length,
    1,
  );
});
