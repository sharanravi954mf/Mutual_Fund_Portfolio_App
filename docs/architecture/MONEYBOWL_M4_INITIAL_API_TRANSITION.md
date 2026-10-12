# M4 one-time Mailback API transition

Implementation candidate: 2026-10-12. **Live commissioning remains BLOCKED.**
This controller has not been installed, prepared against DEV, authorized or activated.
It replaces only the Mailback/document ingestion FastAPI service. Financial dispatch
already runs in Supabase DEV `rskryngwzyuzmiwtriyy`; Oracle's financial dispatcher
stays stopped and retired. This procedure never invokes financial operations.

## Verified starting evidence

The clean authorized feature worktree started at
`8afa04f9db4a3429fdfeef503d4ebaf6abf18aa5`; read-only GitHub `develop` matched.
Canonical `/home/ubuntu/moneybowl` remains on that commit. Independent read-only
Docker inspection confirmed the existing candidate, without rebuilding it:

| Binding | Exact value |
| --- | --- |
| Source revision | `8afa04f9db4a3429fdfeef503d4ebaf6abf18aa5` |
| Component digest | `5f06254a13cb666449336425b1a66d31fa8db4afbb30d78d0bc7687dd67d5fd5` |
| Local candidate image ID | `sha256:257c0fd51f3d47a8d24031fd90333945c804a159ad6779301226edcd3fc80945` |
| Local tag | `moneybowl/m4-ingestion-review:8afa04f9db4a3429fdfeef503d4ebaf6abf18aa5` |
| Legacy API container | `7267a578f4bae1df47d18c838b6e59a2c2b4b31522fe4e90946f4cc5d8f034c6` |
| Legacy image ID | `sha256:1c38aa4946fdb961ed7b0983edb6925988961891c91a0b9e296d84ac8a59286f` |

Candidate OCI revision/component labels matched; architecture was ARM64, runtime user
`10001:10001`, command exactly the existing single-worker Uvicorn command and entrypoint
absent. The local RepoDigest is **not remote publication evidence**. The supplied
`/home/ubuntu/moneybowl-m4-ingestion-candidate-20261012/report.json` reports no private
registry push or activation. Legacy source revision/component provenance remains
**unknown**. No historical build record is invented, imported or inferred from recovery.

## Commissioning prerequisites

1. Independently review this complete change and merge
   [PR #209](https://github.com/sharanravi954mf/Mutual_Fund_Portfolio_App/pull/209),
   candidate `c311e5d877bfd5beaba8230d50b9672a5404c112`, before commissioning the
   regular ingestion owner. Its absent-entrypoint fix and tests remain on its branch;
   this change does not duplicate or modify that fix. The initial inspector separately
   measures architecture, OS and user and safely reads an optional entrypoint.
2. Install the reviewed controller and dependencies outside mutable application Git,
   under a root-owned protected version directory. The privileged initial CLI refuses
   a writable/unprotected installation. Use isolated Python (`-I -B`) and reviewed
   Python/Docker/Compose/systemctl executables. The initial phases require both real
   and effective UID 0 under the explicit `root-operated-cutover-v1` authority. The
   existing normal service runs as `moneybowl-ingestion-deploy` (UID 993, GID 983)
   and cannot invoke initial phases or the initial Docker adapter. Docker socket access
   remains root-equivalent; the protected host administrator is the approval authority.
   No installation, privilege change, key or credential provisioning happened here.
3. Complete the existing independent infrastructure review: **all five ordered layers**
   (base ingestion, hosted ingestion, Flutter web, Director M3B, M3B ingress adapter),
   per-service hashes/container IDs/image IDs/runtime fingerprints, public mounted
   artifacts, networks, volumes, daemon ID, actual TLS Mailback API origin and stopped
   dispatcher/unit/timer identities. Match source-bound ingestion files. Keep the
   normal owner uncommissioned during the transition. Never approve an observed
   baseline automatically or replace an infrastructure baseline to make checks pass.
4. Provision an independently authorized **private** repository (GHCR is supported).
   Set protected `registry.repository`, `private=true`, independent review identifier,
   explicit HTTPS token endpoint/service and any exact blob-storage redirect hostnames.
   For GHCR use `https://ghcr.io/token`, service `ghcr.io`, and the commissioned
   `ghcr.io/<owner>/<package>` repository. A provider-scoped publisher credential must
   have only approved package push/pull access; authorize publication separately.
   Keep its Docker auth directory `0700`, `config.json` `0600`/`0400`, with exactly one
   `auths` registry entry and no credential helpers or extra settings. No tokens in
   Git/Actions/receipts/arguments. Token requests ask only for the exact repository's
   pull scope. Independent review must establish provider-side credential permissions.
5. In a separately authorized publishing session, push the already verified candidate
   once, preserving image identity. Pin `repository@sha256:<remote digest>` and verify
   remote manifest/index/config content, ARM64 selection, labels, runtime and every
   layer's availability. Anonymous access must be denied. Classic config IDs or
   containerd OCI index IDs must bind the same remote image; repackaging requires
   separate review and is rejected here. No push or pull occurs in this controller.
6. Protect state/report/approval directories and all private configuration inputs:
   absolute paths, correct owner, no symlinks at any path component, no untrusted
   writable parents, private file modes and no hard-linked protected files. Put the
   root-operated approval in the approved separate directory. The initial CLI configuration
   and approval must be root-owned regular files (`0400` or `0600`, one hard link);
   approval directory must be root-owned `0500` or `0700`. Every ancestor must be
   root-owned with no group/world write access, and every path must be absolute and
   contain no symlinks. Executor-owned files, directories or ancestors are rejected,
   regardless of the JSON `owner` text. Set `initial_transition.approval_authority` to
   `root-operated-cutover-v1` in the protected configuration. Hash-bind
   the Compose interpolation input and all private env/credential/config files used
   by the five layers in `initial_transition.protected_inputs`; review their completeness.
   These values appear only as hashes in private evidence. Do not grant source code
   permission to edit installed owner code, approval/configuration or registry auth.
7. Retain the exact legacy image and recovery archive. Independently review recovery
   record, archive hash/size, storage access and off-host retention. Previously recorded
   archive: 54,473,216 bytes, SHA-256
   `009b26a7c81735b271100a1fe3b7051fda93ad4927c07119eaaea229d418ed49`.
   The protected recovery record must bind the exact legacy image and `git_commit=null`.
   Archive checks are not a demonstrated restoration exercise. Commission recovery
   readiness separately; keep the original recovery API-only override intact.
8. Select and review the then-current full `develop` branch head. The candidate source
   must be its ancestor and keep the exact component digest above. Set the protected
   initial configuration with `enabled=true` and `acceptance_required=true`, explicitly
   enrolling the normal owner in the permanent completion gate. Retain
   `acceptance_required=true` after handoff even if `enabled` becomes false. An unused
   disabled section without enrollment or retained transaction artifacts preserves the
   existing independently provenanced commissioning path. Any retained transaction
   artifact requires the completion gate regardless of these configuration flags. The example
   configuration remains disabled with deliberate placeholders and cannot commission DEV.

The remote verifier follows the [OCI registry HTTP contract](https://distribution.github.io/distribution/spec/api/)
and [GHCR authentication/visibility guidance](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).
It validates manifest/config bytes against their requested digests, checks remote layer
availability, requires authenticated access and rejects public repositories. Blob redirects
are permitted only to independently pinned HTTPS hosts and receive no registry credential.

## Three separate owner invocations

The following are **future operator commands**, not commands executed in this task.
Use the installed reviewed version and protected real configuration paths, not Git files.
All three invocations must be run by the separately authorized root operator. The
normal service has no sudo, setuid helper or initial-transition service entry point.

```sh
/usr/bin/python3 -I -B /opt/moneybowl-deployment/REVIEWED_VERSION/tools/deployment/initial_api_transition.py prepare --config /etc/moneybowl-deployment/ingestion.json
```

PREPARE reads source/branch/image/registry/configuration/runtime/resource/retirement,
capacity, private-input and recovery facts. It writes only protected local evidence:
immutable `initial-plan.json`, the exact API-only `<source>.compose.json`, and the private
transaction journal. It never creates authorization. The plan holds complete intended
before/after bindings, remote proof, input hashes and explicitly unknown legacy provenance.
Any interrupted preparation preserves its artifacts and requires review before another plan.

The independently authorized root operator must review the immutable plan and supply
a protected JSON authorization with exactly this meaning:

```json
{
  "kind": "moneybowl-initial-api-activation-v1",
  "plan_digest": "EXACT_REVIEWED_PLAN_DIGEST",
  "environment": "dev",
  "project_ref": "rskryngwzyuzmiwtriyy",
  "target": "api",
  "branch_head": "EXACT_REVIEWED_DEVELOP_HEAD",
  "owner": "INDEPENDENT_OWNER_REVIEW_REFERENCE",
  "nonce": "ONE_USE_64_LOWERCASE_HEX_NONCE",
  "expires_at": 0
}
```

The operator chooses a real expiry no more than one hour ahead. `owner` is a human
review reference, not proof of authority; kernel UID and the protected root filesystem
boundary enforce authority. The nonce and complete plan scope are consumed once.
The controller supplies no approval generator. After review:

```sh
/usr/bin/python3 -I -B /opt/moneybowl-deployment/REVIEWED_VERSION/tools/deployment/initial_api_transition.py activate --config /etc/moneybowl-deployment/ingestion.json --approval /private/independent-owner-approvals/approval.json
```

ACTIVATE takes the **same `.owner.lock` as regular ingestion reconciliation** without
waiting, revalidates the branch, image/remote digest, all before-state facts, effective
Compose hashes, private inputs, disk and recovery, then consumes authorization and
persists activation intent. It makes one attempt at only this command:

```text
docker compose [approved project and five ordered layers] -f [immutable reviewed API override] up --detach --no-deps --no-build --pull never --scale api=1 --wait --wait-timeout 120 api
```

A successful command returns `ACTIVATED_NOT_VERIFIED`. It does not write provenance or
service success evidence. The independently run verification phase is:

```sh
/usr/bin/python3 -I -B /opt/moneybowl-deployment/REVIEWED_VERSION/tools/deployment/initial_api_transition.py verify --config /etc/moneybowl-deployment/ingestion.json
```

VERIFY rereads Git, remote OCI/private access, local image, private/recovery/configuration
inputs and Docker state. It requires one new API container with the exact image, source
labels, non-root user, empty/absent entrypoint, one-worker command, healthy Docker health
and successful public `/ready`. Every support container and runtime/resource relationship
must stay identical, M3B receiver stays healthy and financial retirement stays intact.
Before remeasurement it durably records `VERIFYING`, which prohibits a blind verification
retry even if termination bypasses ordinary exception handling. Only after every check
passes does it publish immutable private `initial-verification.json`, the genuine provenance
ledger and `initial-service-receipt.json`. The final atomic journal update records
`VERIFIED`, completion version 1 and exact plan/verification/provenance/receipt digests.
No initial success is exported to the normal report directory during this transaction.
Ordinary publication failure records `UNKNOWN`; abrupt termination leaves the last durable
state and artifacts for independent recovery review. A terminated transaction counts as
complete only if the final journal and every matching artifact were already committed.

The normal owner independently validates the entire retained tuple before reading the
branch head or doing deployment work. A missing/mismatched receipt, plan, verification,
ledger or journal, including an old `VERIFIED` journal without completion bindings,
blocks it. Retained initial artifacts also trigger the gate if the journal is missing.
The permanent initial receipt stays private and is distinct from the normal owner's
renewed reports and independently commissioned public HTTPS receipt hosting. Neither
this archive nor `VERIFIED` alone establishes a public service receipt or full M4 PASS.

## Recovery and subsequent automation

Observed invalid invariants produce `FAILED`. Command failure/timeout, unavailable
measurements or interrupted activation produce `UNKNOWN` (a persisted activation intent
also means an unresolved attempt). Abrupt termination may retain `ACTIVATION_ATTEMPTED`
or `VERIFYING`; these are unresolved states, never acceptance. The journal records whether activation was attempted,
fixed failure code, plan/approval bindings and recovery requirement. Immutable private
failure diagnostics capture any measurable API/retirement state without exposing it in
public receipts. Both states prohibit
another activation or automatic verification retry. Preserve all plans, approvals consumed,
images, archive, containers, volumes and evidence. Diagnose under separate owner review;
rollback is a separately authorized API-only procedure using the preserved legacy image,
original five-layer inputs and recovery override. There is no automatic rollback, deletion,
restart, dependency recreation, broad Compose operation or cleanup path.

After independent acceptance, separately review the access handoff and commission
**the existing ingestion owner**. Initial state/report directories and private inputs must
be root-controlled during the root-operated phases. For the later normal service, the
administrator must explicitly hand off its approved state/report directories and needed
private runtime inputs to UID 993/GID 983, keeping directories `0700`, immutable initial
artifacts/ledger `0400` and journal/lock `0600`. Keep the installed code, root approval
directory, original authorizations and root CLI configuration outside executor authority.
Retain the consumed-nonce evidence with transaction state; the handoff never authorizes
another initial invocation or resetting the transaction.
Supply the normal service's reviewed private configuration through its existing systemd
credential boundary. Set `commissioned=true`; initial `enabled` may become false while
retaining `acceptance_required=true` and the original source/image binding. This task performs no handoff or service start.
The gate binds the archived plan and permanent receipt, so renewing normal reports or
regenerating the API override cannot erase acceptance. It validates the labelled running image and Git ancestry,
builds subsequent exact Git archives, pushes through the single approved registry, checks
remote publication and deploys/verifies only `api`. Any incomplete or inconsistent initial
transaction blocks that owner even if partial publication left a labelled image or ledger. The original
`initial_revision` historical-record requirement remains intact for any unlabeled image.
No second scheduler, webhook, Supabase deployer or Director orchestration is introduced.
Existing full M4 release evidence, branch rules, backend measurement and frontend/receipt
hosting commissioning remain separate gates. This service transition cannot certify M4.

## Offline validation

Tests use disposable Git repositories, synthetic Engine/registry transports and no hosted
credentials. Deployment baseline: 171 passed before changes. Final commands/counts are
recorded in the [DEV remediation record](MONEYBOWL_M4_DEV_REMEDIATION_001.md).
The synthetic transition suite covers success, unknown provenance, invalid SHA/digest/labels,
registry credential/publication/privacy/content/layer failures, scoped token/redirect handling,
approval validity/reuse/expiry, concurrent owners, branch moves, disk, daemon/container/Compose
and network/volume/mount drift, replicas, entrypoints, command/workers, runtime user/health,
public readiness, support preservation, retirement, partial activation, false success,
protected paths/symlinks and atomic ledger/receipt failure. Correction regressions add
same-user self-authorization, service-UID direct/CLI bypasses, untrusted approval ancestry,
20 before/after `BaseException`/`SystemExit` publication interruptions, every missing or
tampered completion artifact, and two legitimate normal reconciliations preserving the
permanent receipt. No live replacement was tested.
