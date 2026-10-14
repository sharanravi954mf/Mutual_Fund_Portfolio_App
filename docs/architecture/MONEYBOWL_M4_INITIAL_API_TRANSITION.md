# M4 one-time Mailback API transition

The [2026-10-14 commissioning readiness implementation](MONEYBOWL_M4_COMMISSIONING_READINESS.md)
adds a separate protected-input staging/review/publication transaction. Its local
readiness does not authorize protected publication or invoke this controller's PREPARE.

Controller merged in PR #211; compatibility correction: 2026-10-13.
**Code readiness does not establish live commissioning.** A prior sealed controller
installation is recorded in the owner checkpoint; this correction has not been installed
or prepared against DEV, authorized or activated.
It replaces only the Mailback/document ingestion FastAPI service. Financial dispatch
already runs in Supabase DEV `rskryngwzyuzmiwtriyy`; Oracle's financial dispatcher
stays stopped and retired. This procedure never invokes financial operations.

## Verified starting evidence

The clean authorized feature worktree started at
`8afa04f9db4a3429fdfeef503d4ebaf6abf18aa5`; read-only GitHub `develop` matched.
These are historical implementation observations, not the current branch head. Independent read-only
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

1. PR #209's absent-entrypoint fix, PR #211's initial controller and PR #212's
   erased-type import verification fix are already merged at the correction's fetched
   baseline. Independently review this compatibility correction before installation;
   do not remerge superseded PR #210. The initial inspector separately measures
   architecture, OS and user and safely reads an optional entrypoint.
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

## Protected-input compatibility correction — 2026-10-13

The isolated correction starts from fetched `origin/develop`
`4d85b50dddb651dbbdc0a160922649c2e3ed043d`. Diagnosis used only `lstat`, ACL-presence
and account/group metadata; no live credential bytes or hashes were read. The earlier
`/home/ubuntu/moneybowl-m4-commissioning-20261012-2105/OWNER_CHECKPOINT.txt`
is a proposal, not authorization. The following metadata was independently confirmed:

| Input | Observed identity / problem |
| --- | --- |
| `/etc/moneybowl-director/m3b-webhook-secret` | UID 0, GID 10001, `0440`, device 2049, inode 54335, one link; root-owned non-writable ancestry; no ACL. Existing M3B needs its group read permission. |
| `/home/ubuntu/.config/moneybowl/github-webhook-secret` | UID/GID 1001, `0600`, device 2049, inode 1310744; application-owned ancestry including `.config` `0771`. A private leaf does not prevent replacement by an ancestor owner. |
| `/home/ubuntu/moneybowl/services/ingestion-support/.env` | UID/GID 0, `0600`, device 2049, inode 292557; application-owned repository/service directories `0775`. Root leaf ownership does not seal that pathname. |
| Docker socket / UID 993 | Socket UID 0, GID 989, `0660`, no ACL; UID 993 has groups 983 and 981. It cannot use the socket. `/var/run` is the standard `/run` symlink, unrelated to secret exemptions. |

These observations do not approve input contents or an infrastructure baseline. Reobserve
identities and obtain independent approval during the future host checkpoint; stale inode
numbers above are not a configuration to install.

### Contract implemented in the correction

`protected_io.protected()` and `root_controlled()` are unchanged. The initial controller
uses the separate [initial input validator](../../tools/deployment/initial_private_inputs.py).
Every `initial_transition.protected_inputs` item now requires approved `identity` containing
exact integer `device`, `inode`, `uid`, `gid`, and `mode`, plus its original `sha256` and
independent `approval` reference. Missing identities and duplicate paths fail closed;
they are never populated from observations by PREPARE. Root-private inputs still require
root-owned trusted ancestry and `0400`/`0600`, one regular-file link and no symlinks.
Compose interpolation must use a root-private input. ACL access/default entries are
rejected on inputs and ancestors, rather than silently authorizing extra readers.
Root-private inputs are for host use only and cannot be exposed through any container
bind mount, even read-only. Bind sources are resolved strictly: a file alias or a
containing directory (including directory aliases) counts as exposure. For external
secrets the only permitted exposure is the exact approved file path, read-only, at
the approved destination in the approved reader; mounting a parent directory is forbidden
even for that reader. Missing or cyclic bind sources fail closed. Baseline approval
cannot waive these rules. ACTIVATE and VERIFY recheck them for retained plans as well.

Only two external policies exist. They require UID 0, exact `0440`, trusted root-owned
ancestry, no ACLs/hardlinks, and exactly one read-only bind to the specified non-root reader:

| Policy | Exact host path | Group / runtime user | Service / destination |
| --- | --- | --- | --- |
| `m3b-webhook-v1` | `/etc/moneybowl-director/m3b-webhook-secret` | 10001 / `10001:10001` | `m3b-receiver` / `/run/secrets/m3b_webhook_secret` |
| `github-webhook-v1` | `/etc/moneybowl-deployment/runtime-secrets/github-webhook-secret` | 1001 / `1001:1001` | `github-webhook` / `/run/secrets/github_webhook_secret` |

The second path is a **future protected migration destination**, not a waiver for the
current home path. A policy also needs an independently reviewed root-controlled JSON
record (`0400`/`0600`, protected root ancestry). Its file path and SHA-256 are bound by
`policy_record` in the root-controlled initial configuration. The exact record schema is:

```json
{
  "kind": "moneybowl-external-secret-policy-v1",
  "environment": "dev",
  "project_ref": "rskryngwzyuzmiwtriyy",
  "policy": "m3b-webhook-v1",
  "path": "/etc/moneybowl-director/m3b-webhook-secret",
  "uid": 0,
  "gid": 10001,
  "mode": 288,
  "service": "m3b-receiver",
  "destination": "/run/secrets/m3b_webhook_secret",
  "runtime_user": "10001:10001",
  "read_only": true,
  "identity": {"device": null, "inode": null, "uid": 0, "gid": 10001, "mode": 288},
  "sha256": "REPLACE_WITH_INDEPENDENTLY_APPROVED_SECRET_SHA256",
  "owner_review": "REPLACE_WITH_INDEPENDENT_OWNER_REVIEW"
}
```

`288` is decimal `0440`; `256` is decimal `0400`. Nulls/placeholders are deliberately
invalid. For the webhook record substitute exactly the second row's policy/path/group/
reader/service/destination. The record must match the configuration's approved identity
and secret digest. A human review string alone never authorizes anything: root-owned
record/configuration paths establish policy authority. The record cannot authorize
ACTIVATE or replace its expiring, plan-bound, single-use root approval.

The validator hashes an `O_NOFOLLOW` descriptor of the approved inode, checks descriptor
identity before/after reading, and rechecks the pathname, ancestry and content-change
metadata. Byte-identical replacement inodes fail. Plan `private_inputs` stores each
input's digest, identity and external policy digest privately. ACTIVATE and VERIFY
revalidate all bindings. The existing config/plan digest, source component digest,
five-layer runtime checks and crash-consistent completion tuple stay mandatory.
Registry credentials and recovery artifacts retain their original private protections.

### Required separately authorized host checkpoint

No operation below was performed by this correction. The host owner must approve the
specific migration, policy records, webhook-only recreation and resulting baseline:

1. Install the reviewed correction under a new sealed root-owned controller version,
   with all dependencies including `initial_private_inputs.py`. Pin its reviewed Git
   commit and executable digests; preserve the previous installation. Use a separate
   root-owned source mirror and registry credentials. Do not execute privileged code
   from application-owned Git or add a global `safe.directory` exception.
2. Establish approved input bytes through the owner's secure provisioning/review path.
   Do not assume content authority merely because a hash or healthy runtime was observed.
   An authorized migration must open each old source without following links, check
   its approved device/inode/owner/mode and content hash on the descriptor, check for
   concurrent modification, and publish a new file without clobbering an existing path.
   Verify byte equality privately, fsync file and directory, and record new identities.
   Do not emit bytes to terminals, arguments, logs, Git or public evidence. Preserve
   both originals, their current ownership/modes, and existing recovery artifacts.
3. Create root-owned protected `0700` directories under `/etc/moneybowl-deployment`:
   `runtime-inputs`, `runtime-secrets`, and `external-secrets`. All ancestors must be
   root-owned with no group/world write or ACLs. Publish the `.env` bytes unchanged at
   `/etc/moneybowl-deployment/runtime-inputs/ingestion-compose.env`, UID/GID 0, `0400`.
   Bind `compose_env` to that file. This changes the interpolation source only: the
   base/hosted Git files stay identical and **no service is recreated for this copy**.
   Require effective hashes and resolved non-secret service relationships to agree;
   any difference needs review. Do not grant UID 993 access to this root input.
4. Publish the unchanged webhook secret at
   `/etc/moneybowl-deployment/runtime-secrets/github-webhook-secret`, UID 0/GID 1001,
   `0440`. The parent stays root `0700`; the existing read-only container file bind
   supplies access to runtime UID/GID `1001:1001`. Keep the M3B secret at its current
   path with unchanged UID 0/GID 10001/`0440`. Do not rotate either secret. Review
   actual runtime group identities and the exact read-only mount destinations.
5. Stage only this mount-source replacement in the **existing Flutter layer**
   `/home/ubuntu/moneybowl-runtime/flutter-web-dev/compose.web-dev.yaml`:

   ```diff
   -      - /home/ubuntu/.config/moneybowl/github-webhook-secret:/run/secrets/github_webhook_secret:ro
   +      - /etc/moneybowl-deployment/runtime-secrets/github-webhook-secret:/run/secrets/github_webhook_secret:ro
   ```

   Review the complete diff and before-state independently. The recorded webhook
   container was `94ba000cd702842ac77006e8fa8edfeff2b543edd7bfd1c6c38b4cc14e7ce132`;
   its replacement ID is unknown until measured. Its image, runtime user, command,
   networks, ports, state/spool mounts and data must remain unchanged. Only its secret
   source, effective hash and container/runtime identity are expected to change.
   There is no sixth layer. After explicit owner approval, the permitted operation is:

   ```sh
   /usr/bin/docker --host unix:///var/run/docker.sock compose \
     --project-name moneybowl-ingestion-support \
     --project-directory /home/ubuntu/moneybowl/services/ingestion-support \
     --env-file /etc/moneybowl-deployment/runtime-inputs/ingestion-compose.env \
     -f /home/ubuntu/moneybowl/services/ingestion-support/compose.yaml \
     -f /home/ubuntu/moneybowl/services/ingestion-support/compose.hosted.yaml \
     -f /home/ubuntu/moneybowl-runtime/flutter-web-dev/compose.web-dev.yaml \
     -f /home/ubuntu/moneybowl-runtime/m3b/compose.m3b.yaml \
     -f /home/ubuntu/moneybowl-runtime/m3b/compose.m3b-ingress-adapter.yaml \
     up --detach --no-deps --no-build --pull never --scale github-webhook=1 \
     --wait --wait-timeout 120 github-webhook
   ```

   Pre/post acceptance must check webhook health and normal authenticated webhook
   behavior without logging its key or bypassing signature checks. Require unchanged
   API, ClamAV, Caddy, Director/M3B and retired dispatcher identities/resources and
   healthy Flutter HTTPS, deployment manifest, API `/ready` and Director ingress.
   There is a brief webhook interruption risk; preserve spool/state volumes and
   monitor normal reconciliation. Preserve the prior Compose file and original secret.
   Recovery requires separate owner authorization to restore that exact layer/mount
   and run the same webhook-only operation; do not blind retry uncertain recreation.
   No Caddy change is authorized by this correction. If the separate receipt-hosting
   change is approved, complete it before freezing the cutover baseline too.
6. Independently review and publish the two root policy records under `external-secrets`,
   bind their hashes and the new input identities in root-controlled configuration,
   and approve the actual post-change five-layer baseline. Changing a baseline is a
   separate infrastructure approval, never acceptance of observed drift. Rebind layer
   hashes, webhook container/effective/runtime hashes, source artifacts and model hash
   as applicable; retain every unaffected service/network/volume binding. Confirm
   package privacy, remote immutable image proof, recovery archive and disk gates as
   required above. Fetch and approve the actual current `develop` head again.
7. Only then may the root operator run PREPARE. It creates a plan, not approval.
   ACTIVATE still requires a separate expiring approval for that exact plan digest.
   Preserve the shared lock, durable journal, single-use nonce, permanent receipt
   and completion tuple. Do not reset an interrupted transition to get another attempt.

### UID 993 Docker boundary remains uncommissioned

The current adapter directly invokes the root-equivalent Engine socket. The correction
rejects a real non-root command transport with `docker_execution_boundary_uncommissioned`
**before registry credential access or Docker/plugin discovery**, even if a socket group
or ACL grant is present. Both real/effective UID 0 remain required for initial phases.
Injected transports are offline test seams, not a configured host execution boundary.
Do not start the regular service/timer or set it commissioned with the current raw adapter.
Root-operated PREPARE does not depend on giving UID 993 Docker access; this remaining
prerequisite blocks subsequent normal automation, not the root preparation phase.

A safe future boundary requires independent platform/security owner approval and a
separately reviewed constrained broker/adapter. UID 993 must receive only semantic
exact-source build/publish/inspect and plan-bound **API-only** activation operations,
not an arbitrary executable/argv, shell, Docker endpoint or Compose-file passthrough.
The privileged side must own and independently verify code, source mirrors, credentials,
five-layer files/model, allowed paths, daemon identity, proof and runtime baseline; reject
caller-provided mounts, environment, alternate projects/targets and all financial/dependency
operations. Untrusted Dockerfile build execution needs an isolated build boundary as well;
an allowlisted `docker build <caller directory>` helper would still expose authority.
Review IPC authentication, input sealing, replay/concurrency/crash behavior and root-to-993
artifact handoff before installation. Retain root-only initial config/approvals/mirror and
the same state/override path plus permanent completion gate; do not chown all root inputs
to UID 993 or discard the transaction. No such broker is implemented or installed here.
Docker-group membership, socket ACL changes, sudo/setuid command wrappers or running
the ordinary owner as root are not approved solutions to this prerequisite.

## Three separate owner invocations

The following are **future operator commands**, not commands executed in this task.
Use the installed reviewed version and protected real configuration paths, not Git files.
All three invocations must be run by the separately authorized root operator. The
normal service has no sudo, setuid helper or initial-transition service entry point.
Isolated Python excludes the script directory from imports. Add only the explicitly
reviewed sealed module directory, never application Git or the working directory:

```sh
/usr/bin/python3 -I -B -c 'import runpy,sys; sys.path.insert(0,"/opt/moneybowl-deployment/REVIEWED_VERSION/tools/deployment"); runpy.run_module("initial_api_transition",run_name="__main__")' prepare --config /etc/moneybowl-deployment/ingestion.json
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
/usr/bin/python3 -I -B -c 'import runpy,sys; sys.path.insert(0,"/opt/moneybowl-deployment/REVIEWED_VERSION/tools/deployment"); runpy.run_module("initial_api_transition",run_name="__main__")' activate --config /etc/moneybowl-deployment/ingestion.json --approval /private/independent-owner-approvals/approval.json
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
/usr/bin/python3 -I -B -c 'import runpy,sys; sys.path.insert(0,"/opt/moneybowl-deployment/REVIEWED_VERSION/tools/deployment"); runpy.run_module("initial_api_transition",run_name="__main__")' verify --config /etc/moneybowl-deployment/ingestion.json
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
administrator must explicitly hand off its approved state/report directories to
UID 993/GID 983, keeping directories `0700`, immutable initial
artifacts/ledger `0400` and journal/lock `0600`. Keep the installed code, root approval
directory, original authorizations, root CLI configuration and protected runtime inputs
outside executor authority. The execution-boundary prerequisite above remains mandatory;
this state handoff does not give UID 993 raw Docker or root input access.
Retain the consumed-nonce evidence with transaction state; the handoff never authorizes
another initial invocation or resetting the transaction.
Supply the normal service's reviewed private configuration through its existing systemd
credential boundary. Only after the constrained execution boundary is independently
implemented, reviewed and commissioned may `commissioned=true` be set; initial `enabled` may become false while
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

The 2026-10-13 compatibility correction adds 42 synthetic security regressions to the
294-test deployment baseline: **336 deployment tests, 34 commissioning tests and 5
commit-validator tests pass**. Documentation/link and Conventional Commit validation
also pass. Added cases cover both authorized runtime-reader policies; missing/changed
policy authority, wrong group/project/reader, inode/owner substitution, writable or
application-owned ancestry, leaf/parent symlinks, hardlinks, ACL readers, mount scope,
duplicate/missing bindings, private-input drift, concurrent content modification,
replacement before descriptor reading, activation approval substitution and refusal to
commission UID 993 through raw Docker even with socket access. Existing root-only
approval, one-use/expiry, runtime drift and crash-consistency suites remain passing.

Scoped review findings: the three live input compatibility defects require the owner
changes above; raw Docker exposes root-equivalent authority and is deliberately refused
for the ordinary non-root owner. No global path/approval exemption was introduced.
This is local code/test evidence, not independent owner approval, a live secret migration,
tested ingress recovery, PREPARE evidence or successful commissioning.

The follow-up security review reproduced two violations against local commit
`1d92ba66654583e366f13f55ebea77c4a2baf430`: PREPARE accepted a read-only directory bind
containing an external secret and an unrelated reader's direct bind of the root-private
Compose input. Both remained accepted after updating synthetic runtime baselines.
The mount-isolation correction rejects both independent of baseline approval, with
22 added regressions covering file/directory/component aliases, normalized paths,
approved readers trying directory/alias substitutions, unresolved sources, older unsafe
prepared/activated plans and legitimate public mounts, volumes and five-layer operation.
Final validation: **358 deployment tests, 34 commissioning tests and 5 commit-validator
tests pass**, plus documentation/link and Conventional Commit checks. Synthetic
PREPARE/ACTIVATE/VERIFY controls preserve legitimate mounts. No live credentials,
infrastructure, service operation or secret migration was used for this verification.
