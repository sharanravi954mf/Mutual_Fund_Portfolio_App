import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.177.0/testing/asserts.ts";
import {
  createNseNavService,
  NSE_NAV_LAYOUT_SHA256,
  NSE_NAV_PARSER,
  NSE_NAV_PUBLICATION,
} from "./nse_nav.ts";
import { createNseSetService } from "./nse_set.ts";
import { NseMasterError } from "./nse_master_download.ts";

const snapshotId = "b0640000-0000-4000-8001-000000000001";
const workspaceId = "b0640000-0000-4000-8002-000000000001";
const scope = { snapshotId, workspaceId };
const receipt = () => ({
  snapshot_id: snapshotId,
  workspace_id: workspaceId,
  connection_id: "b0640000-0000-4000-8003-000000000001",
  download_id: "b0640000-0000-4000-8004-000000000001",
  snapshot_version: "9007199254740993",
  parser_version: NSE_NAV_PARSER,
  source_sha256: "a".repeat(64),
  layout_sha256: NSE_NAV_LAYOUT_SHA256,
  status: "VALIDATED_OBSERVATIONS",
  row_count: 2,
  rejection_code: null,
  rejected_line: null,
  api_compatibility: "UNCOMMISSIONED",
  publication_state: NSE_NAV_PUBLICATION,
});
const row = (line = 1) => ({
  line_number: line,
  nav_date: "2026-09-30",
  nse_scheme_code: "NSE-A",
  scheme_name: "Synthetic Growth",
  rta_scheme_code: "RTA-A",
  dividend_reinvestment: "Z",
  isin: "INF000000001",
  nav_value: "123.450000",
  rta_code: "CAMS",
});
const page = () => ({
  snapshot_id: snapshotId,
  parser_version: NSE_NAV_PARSER,
  source_sha256: "a".repeat(64),
  row_count: 2,
  publication_state: NSE_NAV_PUBLICATION,
  observations: [row()],
  next_after_line: 1,
});
const assessment = () => ({
  snapshot_id: snapshotId,
  workspace_id: workspaceId,
  connection_id: receipt().connection_id,
  download_id: receipt().download_id,
  snapshot_version: "1",
  source_sha256: "a".repeat(64),
  assessment_version: "NSE_SET_EVIDENCE_V1",
  status: "BLOCKED_LAYOUT_UNCHARACTERIZED",
  reason_code: "WEB77_API_COMPATIBILITY_AND_HEADER_UNCONFIRMED",
});
function mock(data: unknown) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return Promise.resolve({ data, error: null });
    },
  };
}
Deno.test("NAV service delegates parsing of stored bytes using only workspace and snapshot", async () => {
  const client = mock(receipt());
  const service = createNseNavService(client);
  const result = await service.validate(scope);
  assertEquals<unknown>(result, receipt());
  assertEquals(client.calls, [{
    name: "validate_nse_nav_snapshot",
    args: { p_workspace_id: workspaceId, p_snapshot_id: snapshotId },
  }]);
  assertEquals(result.snapshot_version, "9007199254740993");
  assertEquals(Object.keys(service).sort(), ["readPage", "validate"]);
});
for (
  const [field, value] of Object.entries({
    snapshot_id: workspaceId,
    workspace_id: snapshotId,
    connection_id: "unknown",
    download_id: "unknown",
    snapshot_version: 1,
    parser_version: "GUESS",
    source_sha256: "abc",
    layout_sha256: "b".repeat(64),
    api_compatibility: "CONFIRMED",
    publication_state: "PUBLISHED",
    status: "SUCCESS",
    row_count: 0,
    rejection_code: "provider-secret",
    rejected_line: 1,
  })
) {
  Deno.test(`NAV receipt fails closed on ${field}`, async () => {
    await assertRejects(
      () =>
        createNseNavService(mock({ ...receipt(), [field]: value })).validate(
          scope,
        ),
      NseMasterError,
      "nse_nav_response_invalid",
    );
  });
}
Deno.test("NAV rejection is typed and cannot be read as observations", async () => {
  const client = mock({
    ...receipt(),
    status: "REJECTED",
    row_count: 0,
    rejection_code: "nse_nav_column_count",
    rejected_line: 2,
  });
  const service = createNseNavService(client);
  const rejected = await service.validate(scope);
  assertEquals(rejected.status, "REJECTED");
  await assertRejects(
    () => service.readPage(rejected),
    NseMasterError,
    "nse_nav_response_invalid",
  );
  assertEquals(client.calls.length, 1);
});
Deno.test("NAV page pins source/version and preserves precise NAV decimals", async () => {
  const validated = await createNseNavService(mock(receipt())).validate(scope);
  const client = mock(page());
  const result = await createNseNavService(client).readPage(validated, 0, 1);
  assertEquals(result.observations[0].nav_value, "123.450000");
  assertEquals(client.calls[0], {
    name: "read_nse_nav_observations",
    args: {
      p_workspace_id: workspaceId,
      p_snapshot_id: snapshotId,
      p_after_line: 0,
      p_limit: 1,
    },
  });
  assertEquals(result.publication_state, NSE_NAV_PUBLICATION);
});
for (
  const [field, value] of Object.entries({
    snapshot_id: workspaceId,
    parser_version: "V2",
    source_sha256: "b".repeat(64),
    row_count: 3,
    publication_state: "PUBLISHED",
    next_after_line: null,
    observations: [],
  })
) {
  Deno.test(`NAV page rejects changed or truncated ${field}`, async () => {
    const validated = await createNseNavService(mock(receipt())).validate(
      scope,
    );
    await assertRejects(
      () =>
        createNseNavService(mock({ ...page(), [field]: value })).readPage(
          validated,
          0,
          1,
        ),
      NseMasterError,
      "nse_nav_response_invalid",
    );
  });
}
for (
  const [field, value] of Object.entries({
    line_number: 2,
    nav_date: "2026-02-30",
    nav_value: 123.45,
    dividend_reinvestment: "?",
    nse_scheme_code: "",
    rta_scheme_code: "A".repeat(11),
    isin: "unknown",
    rta_code: "secret\nheader",
    scheme_name: "padded ",
  })
) {
  Deno.test(`NAV typed row rejects invalid ${field}`, async () => {
    const validated = await createNseNavService(mock(receipt())).validate(
      scope,
    );
    await assertRejects(
      () =>
        createNseNavService(
          mock({ ...page(), observations: [{ ...row(), [field]: value }] }),
        ).readPage(validated, 0, 1),
      NseMasterError,
      "nse_nav_response_invalid",
    );
  });
}
Deno.test("NAV final page remains on original snapshot and has no cursor", async () => {
  const validated = await createNseNavService(mock(receipt())).validate(scope);
  const result = await createNseNavService(
    mock({ ...page(), observations: [row(2)], next_after_line: null }),
  ).readPage(validated, 1, 1);
  assertEquals(result.next_after_line, null);
  assertEquals(result.snapshot_id, snapshotId);
});
Deno.test("NAV invalid pagination never invokes persistence", async () => {
  const validated = await createNseNavService(mock(receipt())).validate(scope);
  const client = mock(page());
  for (const [after, limit] of [[-1, 1], [3, 1], [0, 0], [0, 1001], [0.5, 1]]) {
    await assertRejects(
      () => createNseNavService(client).readPage(validated, after, limit),
      NseMasterError,
    );
  }
  assertEquals(client.calls.length, 0);
});
Deno.test("SET is explicitly blocked with no calendar parser or publisher", async () => {
  const client = mock(assessment());
  const service = createNseSetService(client);
  assertEquals(await service.assess(scope), assessment());
  assertEquals(client.calls, [{
    name: "assess_nse_set_snapshot",
    args: { p_workspace_id: workspaceId, p_snapshot_id: snapshotId },
  }]);
  assertEquals(Object.keys(service), ["assess"]);
});
for (
  const [field, value] of Object.entries({
    snapshot_id: workspaceId,
    workspace_id: snapshotId,
    status: "VALIDATED",
    reason_code: "",
    source_sha256: "no",
    assessment_version: "V2",
    snapshot_version: 1,
  })
) {
  Deno.test(`SET fails closed on ${field}`, async () => {
    await assertRejects(
      () =>
        createNseSetService(mock({ ...assessment(), [field]: value })).assess(
          scope,
        ),
      NseMasterError,
      "nse_set_response_invalid",
    );
  });
}
Deno.test("NAV and SET errors never leak database/provider diagnostics", async () => {
  for (const throws of [false, true]) {
    const client = {
      rpc() {
        if (throws) throw new Error("provider-secret");
        return Promise.resolve({
          data: null,
          error: { message: "provider-secret" },
        });
      },
    };
    await assertRejects(
      () => createNseNavService(client).validate(scope),
      NseMasterError,
      "nse_nav_persistence_failed",
    );
    await assertRejects(
      () => createNseSetService(client).assess(scope),
      NseMasterError,
      "nse_set_persistence_failed",
    );
  }
});

Deno.test("NAV service accepts terminal row-limit rejection and refuses oversized receipts", async () => {
  const data = {
    ...receipt(),
    status: "REJECTED",
    row_count: 0,
    rejection_code: "nse_nav_row_limit",
  };
  assertEquals(
    (await createNseNavService(mock(data)).validate(scope)).status,
    "REJECTED",
  );
  await assertRejects(() =>
    createNseNavService(mock({ ...receipt(), row_count: 100001 })).validate(
      scope,
    )
  );
});
