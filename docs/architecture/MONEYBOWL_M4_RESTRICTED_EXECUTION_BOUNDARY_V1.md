# MONEYBOWL M4 DEV restricted execution boundary V1

The [2026-10-14 backend delivery V2 source candidate](MONEYBOWL_M4_BACKEND_DELIVERY_V2.md)
adds isolated artifact publication and a root API executor with one consolidated
review/install/activate/verify checklist. It supersedes the proposed host-build and
UID 993 private-state handoff for subsequent automation. Historical facts below
remain unchanged; V2 is not installed or live accepted.

**SOURCE CANDIDATE; NOT COMMISSIONED — 2026-10-14.** No DEV deployment is inferred.
This task authorizes source preparation, synthetic offline tests and a local feature
commit only. It does not authorize protected publication, installation, credentials,
PREPARE, ACTIVATE, VERIFY, service enablement or a live API transition.

## Baseline and architecture evidence

The initially clean worktree is
`/home/ubuntu/moneybowl-worktrees/m4-dev-execution-boundary-v1`, branch
`feature/m4-dev-execution-boundary-v1`. HEAD and `origin/develop` were both
`4833842510940586621e0d28dc7448aa2c4079ff`. Canonical develop and its checkout
remain untouched. No remote Git operation is part of this task.

Source review covered the ingestion, initial-transition, integrity, commissioning,
registry, evidence, observer, host, contract, protected-I/O and owner-common modules;
the related tests, systemd samples and relevant M4 architecture sections. The source
establishes these boundaries:

| Component | Current source contract | Remaining boundary |
| --- | --- | --- |
| Ingestion owner | Root-only real DockerOwner; UID 993 rejected before registry reads or plugin discovery. Ordinary reconciliation formerly built/pushed through host Engine, then used a generated API-only override. | No commissioned UID 993 execution adapter. This candidate additionally refuses the ordinary live host-Engine build path. |
| Initial API controller | Separate root PREPARE, ACTIVATE and VERIFY invocations; exact candidate, five layers/six services, input and recovery bindings, independent activation approval, shared lock and retained immutable acceptance artifacts. | Publication/preparation/activation/verification remain separately authorized operations. |
| Initial integrity gate | Rechecks journal, plan, verification, provenance and permanent private service receipt; no failure or missing artifact is acceptance. | Future broker must retain this gate under root authority on every request. |
| Flutter owner | Existing webhook/spool consumer and independent frontend timer; exact-source assets and HTTPS verification. | Preserve this owner; no duplicate consumer or scheduler. |
| Evidence owner | Independent migration history, function export closure, dispatcher readiness/control and fresh service receipt checks; frontend assets and health checked before release evidence. | Project-scoped read capabilities, readiness-only credentials, CLI compatibility, access and receipt hosting need private commissioning. |
| GitHub Actions | Required CI tests source. Environment Release passively observes owners at exact merged SHA. | CI success or directory existence cannot establish a deployment or release PASS. |

Host facts below are **product-owner supplied evidence as of 2026-10-14**, not live
observations made by this candidate. PR #214's sealed root controller is installed at
`/opt/moneybowl-deployment/4833842510940586621e0d28dc7448aa2c4079ff`; it was not changed.
PREPARE has never run. Legacy API provenance remains UNKNOWN and its archive is
preserved. The candidate image was pinned previously; this task does not rebuild,
push, pull or replace it. The six-setting protected preview is explicitly UNAPPROVED
and is not controller STAGE. Final env/config publication is pending. Root approval
and transaction parents are empty; official INSPECT/STAGE/REVIEW/PUBLISH have not run.

The existing unapproved readiness request was neither read nor replaced. UID 993,
primary GID 983 and supplemental GID 981 remain without Docker/sudo/root-input
authority. The evidence service is installed but inactive because its protected
config condition is unmet. `/srv/moneybowl-m4-receipts/{service,backend,release}` are
empty. Required CI passed and Environment Release failed with
`owner_evidence_not_commissioned`. The financial dispatcher container stays stopped.
Older architecture records describe earlier states; these supplied facts do not
retroactively rewrite their evidence.

## Implemented slice and exact limits

[restricted_execution.py](../../tools/deployment/restricted_execution.py) contains
bounded admission primitives and an **offline transaction model**. There is no secure
live privileged broker, daemon, socket listener, owner client, Docker adapter,
registry transport, isolated builder or privileged installation in this candidate.
`live_reconcile` always rejects with `restricted_execution_boundary_uncommissioned`;
the module CLI always exits 1 with deployment unauthorized and release unverified.
There is no `commissioned=true` path. Setting that field invalidates the policy.

The implemented, testable guarantees are:

- A single operation, `reconcile-api-v1`, and exactly five request fields:
  `schema_version`, `operation`, `git_commit`, `request_id`, `approval_id`. Requests
  are at most 1 KiB, duplicate fields/non-objects/malformed JSON fail, and IDs are
  nonzero lowercase 64-hex. Full nonzero Git SHA is required. Arbitrary commands,
  paths, images, environment, projects, targets, mounts and build contexts fail.
- The receive primitive uses Linux `SO_PEERCRED` on Unix `SOCK_SEQPACKET`, requiring
  positive kernel PID and UID/GID 993/983 before receiving. It uses a two-second
  receive timeout and rejects truncation and all ancillary data, closing received
  file descriptors. JSON identity fields never authorize a request. No socket is
  opened. Credentials attest a socket peer identity, not its executable, systemd
  unit or namespace; root installation must separately prove those boundaries.
- Strict `offline-only` policy seals DEV, develop, the canonical repository and
  project, exact SHA, immutable GHCR digest and image ID. It requires digests for
  controller, owner config, service source, initial acceptance, build isolation,
  OCI proof, baseline, API runtime and Compose hash, unrelated/retired/resource
  invariants and file seals. Zero, absent or malformed pins fail.
- The future root-authority reader accepts only the fixed policy pathname
  `/etc/moneybowl-deployment/restricted-api-v1.json` and the exact policy-selected
  hex approval filename beneath `restricted-api-approvals-v1`. It requires real
  and effective root, root-controlled ancestry, no ACLs or links, root:root 0400,
  descriptor/path identity rechecks and a 64 KiB limit. It reads no runtime secrets.
  Raw approval bytes must match the independently pinned policy hash. This reader
  has only been exercised with synthetic files and metadata; no such root policy
  or approval was provisioned here.
- Pure admission binds operation, request nonce, approval ID, all pins and an
  expiring approval (at most five minutes). A human review string is a reference;
  it does not establish root authority. `OfflineJournal` explicitly accepts
  synthetic peers, approvals and snapshots. Its success means `CHECKED_OFFLINE`,
  never deployment authorization or evidence-owner success.
- The offline journal models one nonblocking lock, immutable fsynced intent before
  the second comparison, immutable completion with intent digest, one-use request
  and approval IDs, and a five-second monotonic elapsed check. Failed comparisons,
  expired approval, crash, corrupt/missing completion or unknown files block the
  entire journal, including a different nonce. It has no retry, cleanup or recovery
  mutator. The elapsed check detects overrun; it does not kill blocking work. A
  future executor still needs an independently enforced process duration bound.

These are comparisons and protocol controls, **not runtime attestations**. A string
named `build_isolation_sha256` cannot prove isolation. A digest can be invented in a
synthetic fixture. The offline journal uses disposable owner-private directories,
not the real initial state or public receipt roots. It must not be wired into the
installed owner as a successful deployment path. Full deletion of an offline
journal is not protected by an external rollback anchor; a live journal needs
root-only retention and independently anchored generations. No such guarantee is
claimed here.

[ingestion_owner.py](../../tools/deployment/ingestion_owner.py) additionally records
whether a transport was injected for offline tests, rejects injection of the real
`Command` transport, and refuses `DockerOwner.build` on its real default transport
before capacity checks or Engine commands with
`untrusted_build_isolation_uncommissioned`. There is intentionally no enabling
configuration. Arbitrary Python callables remain test seams, not authorization;
no production entrypoint accepts an injected callable. Existing synthetic build
compatibility tests continue to exercise the historical command contract. This
candidate does not commission that contract. The root initial transition does not
call this build method and its gates/immutable evidence remain unchanged.

## Security dependency and bounded next implementation

The remaining inability to run UID 993 unattended is explicit. The unsafe shortcut
would invoke untrusted Dockerfile `RUN` instructions through the root host Engine.
Allowlisting a build directory, using a clean Git archive, or adding `--no-build`
only to activation does not establish a build sandbox. **Untrusted-build isolation
and independent artifact provenance are mandatory prerequisites**, enforced here
by denying the live build path and leaving all live broker execution unavailable.

The next source contract should separate an isolated, unprivileged ARM64 builder
from a root-owned runtime executor. The builder must have no host Docker socket,
host credentials, host writable mounts, privileged entitlement or financial APIs;
it needs bounded CPU/memory/disk/time, controlled dependency access, disposable
storage and independently verified exact source/OCI output. Its narrowly scoped
publisher may write only the approved DEV package. The runtime verifier gets only
package pull authority. Build/publish capability never goes to UID 993 or the
runtime broker. Rootless-on-the-same-host alone is not accepted as proof; review
user/kernel/namespace escape and credential boundaries, preferably a separate
disposable worker or stronger isolation domain.

After that independent review, implement a root-owned semantic executor, with no
generic argv or Compose passthrough. It must:

1. Load sealed code, policy and exact Git/OCI tickets independently of caller input;
   independently resolve approved develop head and ancestry in a root-controlled
   mirror. A trusted admission issuer may eventually seal independently verified
   candidates for unattended progress. That issuer and its proof verification are
   **not implemented**; this offline V1 requires an exact independently sealed ticket
   and does not authorize arbitrary future SHAs.
2. Generate the API-only runtime specification from reviewed code and root inputs,
   never use source-supplied Compose/Dockerfile/hooks as privileged instructions.
   Keep project, API target, single-worker command, user, security flags, mounts,
   resources, daemon/tool/plugin and env path fixed. Owner requests select none of
   them. Pin root-owned runtime files and descriptors, reject symlinks/ACL/inode or
   mount substitution, and prevent changes between measurement and use. Existing
   live Compose layers under application-owned paths cannot become trusted merely
   because their current hashes match; sealing/ownership and race protection must
   be independently resolved without changing running mounts silently.
3. Recheck permanent initial acceptance using
   [initial_transition_integrity.py](../../tools/deployment/initial_transition_integrity.py),
   all five layers/six services, input/file identities, Docker runtime and daemon,
   image ID/digest/OCI content and source labels, support hashes/local image refs,
   resources, public non-financial readiness and dispatcher retirement. Pin mutable
   M3B tag disposition and never pull/redeploy support services. Any unrelated
   backend, dispatcher, source or runtime change requires a fresh review.
4. Coordinate with the existing root initial/ingestion `.owner.lock`; persist
   root-only intent/approval consumption before a single fixed API-only mutation.
   Independently enforce process time/concurrency bounds; no Engine retry,
   rollback, prune, orphan removal, dependencies or dispatcher operations.
5. Remeasure afterward; archive immutable private transaction evidence before a
   fresh sanitized service receipt. Keep evolving public service reports distinct
   from the permanent initial receipt. Crash/timeout/partial publication must
   quarantine all further requests until independent root reconciliation; never
   clear intent, invent success or reconstruct missing acceptance from requested
   SHA. Prove persistent anti-replay across policy rotation and journal restoration.
6. Prove host Unix peer/user namespace/service identity, root-owned socket directory
   and endpoint, no FD passing, packet/connection limits, minimal owner socket
   capability and no other root operations. Add a client to the existing owner only
   after the reviewed executor exists. Grant UID 993 no root config/state/secret,
   Docker socket, group/ACL access, sudo, arbitrary argv or privileged builder.

## One integrated DEV milestone: two review tracks

Both tracks must complete with independent evidence before describing M4 as an
integrated deployment milestone. The checkboxes are outstanding, not approvals.

### ROOT READINESS REVIEW

- [ ] Independently review sealed source mirror HEAD against current approved
  develop, initial source ancestry, relocated M3B original Git object and service
  digest. Inspect ownership, ancestor permissions, ACLs, links, Git config/hooks/
  helpers and pinned executables; missing trusted objects require provisioning.
- [ ] Bind the original private input and all preserved disabled-owner/Caddy/
  recovery records by exact device/inode/UID/GID/mode, content digest and policy.
  Check both external-secret policy records and actual mount identities without
  exposing values. Preserve UNKNOWN legacy provenance; retain the supplied preview
  and unapproved request unchanged. Empty parent directories are no authority.
- [ ] Obtain actual independent baseline approvals for five layers, six effective
  hashes, runtime/image/container/resource relationships, protected input migration
  and preserved history. Resolve outstanding null approvals/digests independently.
  Official INSPECT/STAGE/REVIEW and separately authorized PUBLISH remain pending;
  use [commissioning readiness](MONEYBOWL_M4_COMMISSIONING_READINESS.md).
- [ ] Verify private GHCR package identity, separately scoped publisher/pull
  credentials, token endpoint/service/redirect policy and actual remote OCI
  ARM64/Linux manifest/config/layer availability. Local RepoDigest or image ID is
  insufficient. OCI labels, user and command must match the reviewed candidate.
- [ ] Record independent disposition of the mutable M3B ingress image tag against
  the approved local image ID/provenance. Preserve without pull under the existing
  baseline, or separately review future immutable migration; do not silently retag,
  redeploy or rewrite the six-setting commissioning request.
- [ ] Prove off-host archive retention, exact archive and recovery-record digest,
  restoration readiness and retention authority. Preserve root recovery copies,
  recovery override and Caddy history. Restore/rollback is separately authorized.

### CODE AUTOMATION

- [ ] Independently review this exact source commit; implement/prove isolated
  builder, ticket issuer, root executor and client as above. Review socket and
  namespace identities, root file sealing, duration limits and persistent journal
  recovery. This source candidate does not complete broker isolation.
- [ ] Root install a separately reviewed new sealed version only after explicit
  authorization; retain the installed `4833842...` controller unchanged. Publish
  approved private inputs through official transaction gates. Separately authorize
  PREPARE, review its immutable plan, authorize ACTIVATE with its own expiring
  plan-bound approval, then authorize VERIFY and audit permanent acceptance.
- [ ] Commission existing ingestion/evidence owners only after API acceptance and
  the execution boundary are proven. Retain root-only initial evidence/config,
  the same deployment lock and financial retirement. No owner `commissioned` flag
  substitutes for any prerequisite, and no timers are enabled by this candidate.
- [ ] Provision evidence-only private inputs independently, prove fresh service/
  backend/release receipts and complete frontend asset health at the same SHA.
- [ ] Verify existing webhook signature/spool/consumer and Flutter timer health,
  ingestion reconciliation and evidence renewal with existing owners. Test missing/
  stale/superseded/failed receipts through passive CI observation, with no second
  webhook, scheduler or privileged CI deploy runner. Observe a real exact merged
  develop SHA only after separate approval; QA/PROD remain outside this task.

## Evidence-owner commissioning handoff

The existing owners and HTTPS receipt graph already supply the integrated release
contract. No new financial dispatcher or Supabase writer is needed. The evidence
owner needs all of the following separately authorized DEV conditions:

| Missing/unproven condition | Owner handoff and acceptance evidence |
| --- | --- |
| Protected evidence config/condition | Root installs reviewed DEV config with its independent source mirror, private state, report/release roots, service receipt origin and frontend origin. Installed unit/drop-ins and credential names must be audited against actual source; examples are not installed-state proof. |
| Management read capability | Evidence owner independently receives project-scoped database/function reads. Prove the exact read-only migration/control/Cron queries and schema visibility. If unavailable, independently review a minimal measurement projection; never add broad owner/admin/service-role fallback. |
| Readiness-only authentication | Independently provision `measurement-token` and `readiness-only-key` to the installed unit. Prove the deployed DEV dispatcher has the reviewed readiness handler and matching dedicated OUTBOX_READINESS_KEY. Never supply notification/worker/service-role credentials or trigger financial events. |
| CLI/source export compatibility | Pin and prove the actual Supabase CLI binary and exported module closure against exact Git bytes. Missing migration statements or unsupported export transformations fail; requested source is not deployed proof. |
| Fresh service proof | After permanent initial acceptance and broker commissioning, the existing ingestion owner produces actual exact-image/runtime, source-digest, health and retirement evidence. The offline CHECKED result cannot populate this report. |
| Receipt hosting | Independently prove Caddy's existing read-only receipt mount and HTTPS service/backend/release routes. Unknown SHA returns 404; no HTML fallback, redirects, credentials or stale cached success. Sanitized publication grants no input/root/Engine access. |
| Frontend and public observer variables | Existing Flutter owner proves actual index/main asset bytes, deployment identity and health. Repository owner separately supplies public M4_DEV_FRONTEND_ORIGIN and M4_DEV_EVIDENCE_URL; no GitHub token/secret or deploy runner is added. |

A specific future sequence is: finish root readiness; complete reviewed isolation
and root executor; separately publish inputs and accept the initial API; commission
the existing ingestion owner; privately provision and validate the independent
evidence owner and read-only receipt hosting; check the existing Flutter owner and
webhook; then allow the existing passive workflow to observe all components at one
actual merged DEV SHA. Every live step requires its own applicable authorization.
`produce` requires fresh service evidence (five-minute maximum age); `owner_cycle`
publishes release status only after all backend components are measured. The
observer also requires current branch identity and served frontend assets/health.
Required CI remains code validation. Environment Release stays failed/unverified
until these independent measurements exist; later private release evidence does
not retroactively change a failed GitHub run.

## Validation and next safe step

[test_restricted_execution.py](../../tools/deployment/test_restricted_execution.py)
adds offline admission, peer, approval, drift, replay, lock, crash, journal and
root-file regressions. Existing suites continue to cover actual synthetic mounts,
Compose relationships/hashes/images/tags, dispatcher retirement, initial integrity,
evidence-owner reads and passive observer failure behavior. Every fixture uses
disposable files and injected measurements; no live Docker, service, registry,
Supabase API, secret or root installation is consulted.

Run full deployment and commissioning suites, commit-validator tests, documentation
audit, Python AST parsing and `git diff --check`. Test results validate source
behavior only. A local Conventional Commit is the review artifact; no push, PR,
merge, tag, canonical develop update or infrastructure change is authorized here.

Completed local validation on 2026-10-14:

| Check | Result |
| --- | --- |
| `python3 -m unittest discover -s tools/deployment` | 472 passed, including 70 new boundary cases |
| `python3 -m unittest discover -s tools/commissioning` | 34 passed |
| `python3 -m unittest discover -s .github/scripts -p test_validate_commits.py` | 5 passed |
| `python3 .github/scripts/validate_docs.py` | Passed |
| All deployment Python modules: AST parsing | Passed |
| `git diff --check` | Passed |

The exact next safe step is independent architecture/security review of this local
candidate and a concrete isolated-builder/provenance/root-executor design. Root
readiness review can proceed separately under its own read authority. Do not enable
the UID 993 owner or initiate API PREPARE/cutover from this source result.
