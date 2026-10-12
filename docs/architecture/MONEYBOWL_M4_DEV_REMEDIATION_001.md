# M4 DEV commissioning remediation 001

The 2026-10-12 [implemented one-time API transition runbook](MONEYBOWL_M4_INITIAL_API_TRANSITION.md)
supersedes the earlier manual initial-transition proposal below. Code and synthetic tests
are implemented for review; the legacy source remains unknown, the new ARM64 image is
local-only, and private registry/owner approval/commissioning remain blocked. No live
replacement or owner activation was performed.

The [latest execution record](#github-actions-completion-execution--2026-10-11)
supersedes historical capacity and installation blockers below. DEV is still not
commissioned; staging is not a successful deployment.

Date: 2026-10-11. Starting candidate:
`744ded1d7650fdcbd5415baa83def3eab07774af`; fetched remote feature matched it.
`origin/develop` and clean canonical checkout:
`8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`.
Work remained in `moneybowl-worktrees/m4-unified-environment-deployment-v1`.

**Local implementation is ready for review; DEV installation and end-to-end
commissioning remain BLOCKED.** No build, deployment, service installation, cleanup,
credential provisioning, publication or financial operation was performed. The private
`moneybowl-m4-commissioning-preflight-20261011/DEV_COMMISSIONING_PREFLIGHT.json`
was read; its staging-only blockers remain operational gates, not permission to install.
See the [canonical promotion runbook](MONEYBOWL_M4_ENVIRONMENT_PROMOTION.md).

## Read-only discovery and ownership

Docker Engine/client 29.7.2, Compose 5.5.0. All six application containers also record
Compose 5.5.0 at creation. The daemon ID is
`694c3116-1db0-44e0-88ce-237cc8414783`, storage `/var/lib/docker`.
The Compose project is `moneybowl-ingestion-support`, project directory
`/home/ubuntu/moneybowl/services/ingestion-support`. These observed identities are
not automatically installed as trusted M4 configuration.

| Ordered layer | Provenance and SHA-256 | Deployment authority |
| --- | --- | --- |
| `services/ingestion-support/compose.yaml` in canonical checkout | Tracked develop source; `9ed8b556d4f73a8e561f0210d1d4f16d6723546af00d629357572094d535f028` | Ingestion/infrastructure owner |
| `services/ingestion-support/compose.hosted.yaml` | Tracked develop source; `66a2240ed9f12da28504acfff21e6453930d92199468bb6293a452cb9a7ef926` | Ingestion/infrastructure owner |
| `/home/ubuntu/moneybowl-runtime/flutter-web-dev/compose.web-dev.yaml` | Existing private runtime artifact; `1438ee2dc18c2264430ae1855d639d7d38b1d1276af186c52d8e6e1563b4c08e`; independent owner approval still needed for M4 | Existing Flutter/webhook owner |
| `/home/ubuntu/moneybowl-runtime/m3b/compose.m3b.yaml` | Byte-identical to `services/ingestion-support/compose.m3b.yaml` at historical `3eefd7cffec7fcd273250e014f03175e1d5c1c3b`; SHA-256 `fb8b6d1d940316c15eafae790d28042b09f1ae464a66cc7615703d64b0fffa20` | Director/M3B owner |
| `/home/ubuntu/moneybowl-runtime/m3b/compose.m3b-ingress-adapter.yaml` | Existing runtime artifact, SHA-256 `c7393239131e93e122647a516e91d69df05de66dea61a040952768c63c4d4a9e`; no authoritative source-commit binding established in this review | Director/M3B ingress owner; separate approval required |

The historical fourth path under the application checkout is absent. Runtime
`m3b/RECREATE.md` documents relocation on 2026-09-16 to keep that checkout clean,
including the matching hash and original project directory. The earlier M3B commit
`6011f5f` is **not** equivalent: its receiver lacks the later `group_add` permission
correction. The exact later Git bytes and relocation record establish relocation
residue, not permission to recreate a missing file or assume every overlay is compatible.

Container labels retain the file list used at their creation; they are not a single
current project-wide file list:

| Service / existing owner | Container ID prefix | Recorded layers | Observed state / image ID prefix |
| --- | --- | --- | --- |
| API / ingestion | `7267a578f4ba` | Four; historical missing M3B path | Running, healthy; `1c38aa4946fd` |
| ClamAV / infrastructure | `ee01e9ecae39` | Base + hosted | Running, healthy; `2bb8cd7dfe3e` |
| GitHub webhook / existing spool owner | `94ba000cd702` | Base + hosted + Flutter | Running, healthy; `b64631e04e49` |
| M3B receiver / Director | `79358abb2eb3` | Four; historical missing M3B path | Running, healthy; `400d88fd63e3` |
| Caddy / shared ingress infrastructure | `773e98bacecd` | Five; relocated M3B + ingress adapter | Running, no Docker healthcheck; `5f5c8640aae0` |
| M3B ingress adapter / Director | `a188792e353b` | Five | Running, no Docker healthcheck; `932d0492f45f` |

All six use restart policy `unless-stopped`. Caddy owns host TCP ports 80/443.
API has no published port and no persistent mount. Caddy connects to both
`moneybowl-ingestion-support_ingestion_internal` and `moneybowl_m3b_private`, mounts
the runtime Flutter Caddyfile and `/srv/moneybowl-web-dev` read-only, and retains
`caddy_data`/`caddy_config` named volumes. ClamAV retains `clamav_db`. Webhook and
M3B receiver bind their existing code, secret **paths**, state and spool directories;
secret file contents were never read. The M3B private network is internal; the ingress
layer declares it external so that its established lifecycle remains separately owned.
An unresolved five-layer render reproduces these structural relationships.

Recorded service hashes were inspected (examples: API `21b08785e3581ae00674d1a5103825165c28785ff968f297acb741e685bcfdad`,
Caddy `674fa95483dcc474a8a495fbc3ca5c258f3324d9a4485baa7cafe391c09ec017`).
**Actual credential-resolved hash equivalence was not certified.** Automatic approval
review rejected a proposed Compose check that supplied the live `.env`, because it
would access credentials. The safe replacement used `--env-file /dev/null`,
`--no-interpolate`, and `--no-env-resolution`, printing only structural fields.
The future private owner must independently authorize and complete resolved `config
--hash` comparisons; no hash copied from a container label alone proves equivalence.
[Compose documents the render and hash operations](https://docs.docker.com/reference/cli/docker/compose/config/).

The existing Flutter deploy script and spool consumer have locks, exact-source builds
and stale-head checks. The spool calls the existing `deploy-develop.sh`; the systemd
path unit watches it. **An existing Flutter reconcile timer is already enabled**, runs
as `ubuntu`, and has a 15-minute interval. M4 must adapt this single owner, not install
its example timer alongside it. Director worker/Slack/base-reconciliation units and
M3B receiver/ingress are separate owners and remain outside API deployment authority.

Oracle financial retirement was independently observed: original container
`da4eb94852192fa7cfa4723535a15cdfcd63f608438571a08b544df54af95e72` is exited,
restart policy `no`; regular and template reconciliation services have persistent
`/etc/systemd/system` links to `/dev/null`, and the timer is disabled/inactive.
No hosted Supabase/financial probe ran; active native DEV dispatch and its Cron remain
supplied commissioning context, preserved by unchanged source and absence of operations.

## Corrected compatibility contract

The previous adapter hard-coded two `-f` files and checked only Caddy/ClamAV. It
therefore evaluated a Caddy configuration missing Flutter mounts, webhook ownership,
M3B networking and the later ingress adapter. That was the exact integration mismatch.

[Compose inventory](../../tools/deployment/compose_inventory.py) and the
[ingestion owner](../../tools/deployment/ingestion_owner.py) now require:

1. Exactly four ordered known layers, or those four plus the explicit M3B ingress
   layer. DEV paths, project/directory, owner role, approval reference, filesystem UID/mode and file digest
   are explicit. A four-layer profile cannot omit a fifth-layer running container.
   Missing, reordered, substituted, linked or unsupported files fail. Base/hosted and
   source Caddyfile bytes must also equal the approved application revision. M3B bytes
   must equal the archived original Git object, which must exist in the private mirror.
2. Separately approved hashes for the non-secret runtime Caddyfile and webhook
   receiver source. Their secret mounts are checked as metadata, never read or hashed
   as files. External overlay/artifact approvals belong to their respective owners;
   neither discovery nor a GitHub CI result creates those approvals.
3. A private reviewed unresolved-model digest, exact service inventory, original
   per-service file labels, and resource identities. Enumerating **all** project
   containers detects unknown services, extra API replicas and one-off containers.
   Every support service retains its full approved ID/image; mutable legacy support
   tags may only resolve to that already approved local image, never be pulled.
4. Fresh resolved Compose hashes must match the running service labels and approved
   baseline. Runtime projections separately bind mounts, ports, restart policies,
   command/entrypoint, security properties and stable network IDs/aliases. Named
   network/volume metadata must match approved digests. Missing resources fail before
   `up`; the adapter never creates a replacement infrastructure baseline.
5. One API worker, healthy API/ClamAV/webhook/M3B receiver, and unchanged running
   ingress containers. The read-only public `/ready` route verifies API reachability
   through Caddy before and after deployment; a missing Caddy healthcheck alone is
   never described as an independent HTTP health measurement.
6. A prepared override exactly equal to the generated immutable API manifest.
   Support-service hashes with and without the override must be equal. A one-use
   activation permission binds the file bytes and before-state; immediately before
   activation, capacity, retirement and host compatibility are rechecked.
   The only activation command is `compose ... up --detach --no-deps --no-build
   --pull never --scale api=1 --wait --wait-timeout 120 api`. No profile activation,
   `down`, dependency restart, orphan removal, resource deletion or broad `up` exists.
7. Existing locks, current-head checks, immutable image/registry provenance and
   failure reporting remain. Exact prior ledgers are required for labelled API
   images; a label cannot replace the ledger. Duplicates remeasure, concurrent calls
   serialize, superseded revisions never become deployed, and failed activation is
   not blindly retried or automatically rolled back. Post-check failure withholds PASS.

The [disabled example](../../tools/deployment/ingestion-owner.example.json) shows
all fields but contains deliberately invalid approval/hash and UID/mode placeholders. It grants no
live authority. Configure resource digests from the exact JSON projections in the
adapter, and runtime digests using `runtime_identity`; independently compare those
measurements to the resolved approved Compose configuration before accepting them.
Never auto-populate and commission a baseline merely because current containers exist.
Docker, systemctl and the **actual discovered Compose plugin path** are byte-pinned.
Install the complete reviewed runtime module set, including `compose_inventory.py`,
in the protected controller directory; replacing only `ingestion_owner.py` is not
sufficient. Layer/artifact `uid` and integer permission `mode` must match the
independently reviewed filesystem metadata; world-writable files are rejected.
Host configuration, mirrors, code, approval records and state must be protected from
application writers. Privileged host owners can still race or bypass Docker controls;
these checks are not a sandbox against a malicious Docker/root administrator.

## Legacy API provenance and initial transition

Actual image:
`sha256:1c38aa4946fdb961ed7b0983edb6925988961891c91a0b9e296d84ac8a59286f`,
created `2026-08-28T11:27:39.027516977Z`. It has no OCI revision/source label. Its local
repository digest identifies bytes, not the originating Git revision or a registry
build attestation. Repository history has an ingestion change earlier that day; timing
is circumstantial and **was not used to infer the source SHA**. The inspected source,
runtime inventory and deployment records provide no authoritative image-to-SHA record.
Some private legacy dispatcher state is inaccessible and was not opened or escalated;
it is not an ingestion build record in any event. Historical API provenance is BLOCKED.

The former bare `initial_revision`/`initial_image_id` fallback is no longer accepted.
A 0600 owner/root-owned historical JSON record must have `kind=historical-build-record`,
its independent authority, exact `image_id`, `git_commit`, and source component digest;
its bytes are bound by `initial_provenance.path/sha256` in protected owner config. The
record must come from an authoritative build/deployment archive. The verifier checks
consistency and ancestry; it cannot create missing historical knowledge or certify a
self-written claim. No such real record was generated in this task.

If the original record cannot be recovered, authorize a distinct **initial replacement**:
first establish capacity, reviewed infrastructure baselines, registry and recovery
plan; build a chosen reviewed approved revision and independently capture image/digest
provenance. The existing infrastructure owner then performs an explicitly authorized
API-only transition, retains the unknown legacy image for emergency recovery, and
records the newly measured revision/ledger/override. Leave the old revision recorded
as unknown. Independently verify all support IDs, mounts, ports, retirement and health
before enabling reconciliation. This is not a normal automatic M4 deployment and
cannot be enabled through an `allow_unknown` flag. No such transition was performed.

## Capacity evidence and ranked remediation

Root `/dev/sda1`, ext4: 47,321,268,224 filesystem bytes (44.07 GiB), approximately
40.86 GiB used, **3,449,139,200 bytes available (3.21 GiB), 93% utilized**. Inodes:
5,980,160 total, approximately 4,886,370 available (19% used). Values are snapshots
and change slightly with ordinary ongoing service/session activity.

| Observed consumer | Usage | Important qualification |
| --- | --- | --- |
| `.codex` | 6.93 GiB | 5.73 GiB executable packages, 0.77 GiB session history, small caches; not all logs |
| `moneybowl-worktrees` | 3.53 GiB | 19 build/cache pairs total 3.12 GiB; 90 registered worktrees across all locations, none reported prunable/locked |
| `moneybowl-director` | 2.42 GiB | 2.12 GiB evidence plus state/worktrees; active Director dependencies |
| `/srv/moneybowl-web-dev` | 2.13 GiB | 52 immutable releases; current symlink targets develop `8993ce1...` |
| Docker images | 12.45 GB reported | 86 images, 19 active; **1.192 GB reclaimable**, not 12.45 GB |
| Docker containers | 12.85 MB reported | 24 containers, 22 running; includes old isolated test DBs with unknown current owners |
| Docker volumes | 484.1 MB reported | 11 volumes, 8 referenced; only 74.85 MB unreferenced, potentially valuable DB evidence |
| Docker build cache | 669.9 MB reported | Mostly shared; only 8.846 MB reported reclaimable |
| `/tmp` | 1.89 GiB | Includes 0.46 GiB prior M4 CI fixtures/cache; some temporary paths are mounted by running validation containers |

No cleanup candidate is approved for deletion by this report. Estimates overlap
where Docker shares layers; do not add nominal image sizes. Read-only process metadata
identified active Codex 0.162.1 and its `current` symlink, and this worktree in use.
It cannot prove that other worktrees or executable versions have no future owner.
No Codex histories, Director evidence, private credential stores or financial records
were opened to assess their contents or retention.

| Rank / candidate | Potential additional free space | Use evidence / consequences | Backup, owner authorization and risk |
| --- | --- | --- | --- |
| 1. Expand OCI boot volume to a reviewed 100 GB-class size | Approximately 46–50 GiB additional capacity; verify provider units | Preserves all working data and audit history; durable solution, increased storage cost | Boot-volume backup plus tested recovery, tenancy/VM/Director owners and privileged Ubuntu operator required; medium change risk |
| 2. Old Codex executable versions only | About 5.0 GiB if current and one previous version are retained | 17 version directories; active/current is 0.162.1. Removing a pinned version can break a launcher | Codex/operator owner must check pins/open processes, retain checksummed reinstall/archive and current/rollback versions; low-to-medium conditional risk |
| 3. Generated `build`/`.dart_tool` in individually idle worktrees | Up to 3.12 GiB | Generated caches are reproducible but removal disrupts active builds and costs rebuild time; worktrees remain registered | Each worktree/Director owner approves exact paths after idle check and preserves untracked evidence; low conditional risk; no worktree removal |
| 4. Old Flutter releases outside an approved retention set | Up to about 2.0 GiB | 52 releases, roughly 42 MiB each; current and approved rollback/client retention must remain | Frontend owner approves retention window, off-host checksummed archive and restore test; medium risk |
| 5. Explicit unused Docker image IDs / cache records | At most current 1.192 GB image estimate plus 8.846 MB independent cache estimate | Most historical dispatcher images share layers; never delete the retired container or its bound image; some build bases aid recovery | Docker/infrastructure owner checks all references and recovery digests/archives; medium risk; selective reviewed object list, no prune |
| 6. Prior isolated `/tmp/moneybowl-m4-ci-207` build/cache artifacts | Up to 0.46 GiB | Prior CI evidence and reproducible dependencies; other `/tmp` paths may be active container mounts | CI owner archives validation logs/necessary fixtures and checks mounts/processes first; low conditional risk |
| Retain Codex sessions and Director evidence/state | **0 approved reclaimable** | Audit/history retention requirements were not found to authorize deletion; Director is active | Data owners must define retention, legal/audit holds, off-host backup and restoration before any future compaction; high risk |
| Retain database/ClamAV/Caddy volumes and test containers | **0 approved reclaimable** | Small potential gain, unknown DB retention; live signatures/TLS/state are active dependencies | Respective owners and independent data recovery plan; high risk |

Selective cleanup may provide temporary relief but cannot be promised without those
approvals and may refill rapidly. Expansion is preferred before unattended builds.
A conservative planning allowance is **2–4 GiB Flutter**, **2–4 GiB Docker** (pulls,
unpacked stages, dependency/build cache, old and new images), plus at least **4 GiB
operating reserve**: plan for 8–12 GiB peak additional space. This is an engineering
budget, not a measured cold-build peak; full builds were deliberately not run.

The new ingestion capacity gate checks the state, temporary-source and Docker-data
filesystems and requires free bytes at least **max(12 GiB, 20%)**, and free inodes at
least **max(100,000, 20%)**, before source extraction/build and activation. Unknown
capacity fails closed. The actual read-only host gate returned
`insufficient_build_capacity`. It performs no cleanup. Plan alerts below max(15 GiB,
25%) free or 25% free inodes; page on gate failure/critical <8 GiB or <10% free. Allow
only one build per owner, cap aggregate build concurrency, and include Director jobs
in capacity planning. Other processes can consume space after any snapshot.

### Separately authorized OCI/Ubuntu expansion procedure

1. Tenancy/VM owner confirms instance, boot-volume OCID, attachment type, quota/cost,
   backup retention, replication settings, recovery access and maintenance window.
   Take a protected boot-volume backup and application-consistent Director/state
   backup under their owners; test restore access before changing partition metadata.
2. Expand the existing boot volume through OCI Console or reviewed
   `oci bv boot-volume update --volume-id <verified-boot-volume-OCID> --size-in-gbs <approved-size>`.
   Follow the instance-specific rescan instructions. No OCI credentials or API were
   accessed here. OCI permits growth, not shrinking; backup is explicitly recommended.
   [OCI volume resizing](https://docs.oracle.com/en-us/iaas/Content/Block/Tasks/resizingavolume.htm),
   [online procedure](https://docs.oracle.com/en-us/iaas/Content/Block/Tasks/update-online-resize-block-boot-volume.htm).
3. An independently authorized privileged Ubuntu operator verifies `lsblk`, mount
   source, partition starts and backups after rescan. This snapshot has root ext4
   on `/dev/sda1`, starting at sector 2099200 after EFI/boot partitions. If unchanged
   and free space is contiguous after root, review `growpart -N /dev/sda 1` first,
   then authorized `growpart /dev/sda 1` and `resize2fs /dev/sda1`. Do not operate on
   EFI/boot partitions or assume device naming stayed stable. These are future
   commands, not executed actions. See Ubuntu's
   [growpart](https://manpages.ubuntu.com/manpages/resolute/man1/growpart.1.html) and
   [resize2fs](https://manpages.ubuntu.com/manpages/bionic/man8/resize2fs.8.html) manuals.
4. Online growth can avoid detachment, but reserve an outage/reboot window if the
   kernel cannot reread the table or the provider requires it. Verify filesystem
   capacity/inodes, service health, mounts, ingress, Director and retirement after
   completion. No M4 timer is enabled as a side effect.
5. Rollback is **restore/switch to a verified backup boot volume**, not shrink the
   enlarged filesystem. It may require downtime and lose writes since the snapshot.
   Director owners must reconcile durable delivery/evidence state before restoring
   automation; do not replay financial work or restart Oracle dispatch. Maintain
   retirement masks/policy and prevent duplicate workers/webhook consumers on recovery.

## Private commissioning checklist and owners

None of the three example service users (`moneybowl-deploy`, `moneybowl-ingestion-deploy`,
`moneybowl-evidence`) or `/opt/moneybowl-deployment`/`/etc/moneybowl-deployment` exists
in this inspection. Example `/private` mirrors do not exist. Private staging is code,
not an installed service or provisioning of capabilities.

| Prerequisite | Responsible owner / safe automation after approval | Current gate |
| --- | --- | --- |
| Capacity and monitoring | OCI/host owner executes reviewed expansion or per-object cleanup and installs alerts | BLOCKED: 3.21 GiB available |
| Ordered layers, mounted public files, private model/service/resource baselines | Ingestion, Flutter and Director/M3B owners jointly approve; read-only measurement can be scripted, acceptance must remain independent | BLOCKED: fifth-layer authority review and credential-resolved hash/relationship certification pending |
| Legacy API adoption | Existing ingestion owner supplies authoritative historical record or approves a separate initial replacement | BLOCKED: source provenance unknown |
| Dedicated Flutter owner | Host owner grants only source/cache/release access; adapts existing spool call and existing 15-minute reconcile unit to one locked versioned controller | BLOCKED: no dedicated user/install; do not enable the example second timer |
| Dedicated ingestion owner | Host owner installs reviewed adapter, private state/config and narrow service scheduling | BLOCKED: Docker socket is root-equivalent, cannot be made safe for shared CI by systemd flags alone |
| Evidence owner | Independent measurement owner; separate user/host and state; no Docker socket or deployment write access | BLOCKED: not provisioned |
| Git mirrors | Each owner gets its own read-only authenticated mirror of the exact repository/branch; ingestion also retains reviewed historical M3B object/ref | BLOCKED: mirrors/auth and immutable archive access not installed |
| Executables | Host owner pins Python 3.12.3, Flutter 3.44.6/Dart 3.12.2, Docker 29.7.2, Compose 5.5.0 plugin and systemctl bytes; evidence owner separately pins reviewed Supabase CLI 2.115.0 | Existing tools are not an approved installation; hash manifest and protected upgrade process pending |
| Readiness-only capability | Supabase/evidence owners provision a new independent `OUTBOX_READINESS_KEY` only after reviewed readiness code is deployed through the existing integration | BLOCKED; no retrieval/reuse of `OUTBOX_NOTIFICATION_KEY`; no code/secret provisioning in this task |
| Scoped Supabase measurement | Project owner provisions read-only migration statements, declared-function exports, identity/control/Cron projections; verify real CLI round trip | BLOCKED; no admin/write fallback and no grants executed |
| Registry/provenance | Private registry owner grants scoped ingestion push/pull; owner records exact built image ID, immutable digest and source ledger | BLOCKED; no registry auth, build or push performed |
| Trusted TLS receipts | Independent host/DNS/TLS owner serves sanitized service/backend/status directories with no-store and genuine 404s; app users cannot write them | BLOCKED; no receipt hosting installed |
| GitHub public observer variables | Repository owner sets `M4_DEV_FRONTEND_ORIGIN` and `M4_DEV_EVIDENCE_URL` after endpoint ownership verification | Not changed or assumed configured; no secrets belong here |
| Unit permissions and timers | Host owner reviews installed-code/config parent ownership, 0600 private config/records, distinct writable state/report roots, `LoadCredential` only on evidence service, `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, explicit `ReadWritePaths` and network/socket restrictions compatible with each role | Examples are not installed/hardened/certified units; evidence/ingestion 60-second convergence timers require approval; reuse existing frontend timer |
| Webhook handoff | Existing webhook/M3B owners retain their endpoints, secrets, spools and consumer locks; only the existing frontend dispatch target is adapted under review | No additional webhook listener/consumer; no changes made |
| End-to-end acceptance | Repository, Supabase and host owners authorize publication/review/merge and one controlled release; independently retain exact deployed content/revision and full PASS evidence | BLOCKED: PR unmerged, no live owner receipt or unattended release demonstrated |

Next operational request should be a **separate owner approval for capacity expansion
and protected baseline measurement**, backed by independent review of this commit.
Then resolve the legacy image transition and owner provisioning. Do not enable any
M4 service/timer until those gates pass. Normal approved merges can then converge
Supabase, Flutter and API owners without recurring manual commands; only independently
verified final receipts establish that outcome. QA remains disabled and separately
owned; Production and financial activation are outside this process.

## Validation and limitations

Existing-file baseline before edits: M4 119 tests, M2A 34, 17 routes and 27 frozen
migrations passed. New tests use temporary synthetic Git/source trees and mocked
Docker/HTTP/systemctl interfaces. They do not build images or change the live stack.
Read-only host evidence establishes file relocation, service/resource metadata,
retirement and capacity; it does not certify private resolved configuration or image
source provenance. See the appended [validation record](MONEYBOWL_M4_VALIDATION.md)
for final commands/counts.

In the tested command path, unrelated container activation is excluded by exact
service selection, `--no-deps`, no profile, no build/pull, existing resource checks and
an override restricted to `api`; tests inspect the full mutation argument vector and
before/after support state. This is a tested adapter property, not a claim that real
host commissioning has run or that a privileged external actor cannot mutate Docker.

## GitHub Actions completion execution — 2026-10-11

**Result: source timing correction and safe staging completed; automatic DEV release
still BLOCKED.** Explicit fetch of both remote refs confirmed published feature
`bc1870c5ca87962d9768a9000ba02798c7175df4` and develop
`8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`. Both checkouts were clean before work.
The default fetch refspec had left the feature tracking ref stale; an explicit fetch
resolved it. PR #207 remains draft with no recorded reviews. Five workflows passed
for the published candidate; `M4 Environment Release` was deliberately skipped.
Neither those checks nor this implementation constitute independent release approval.

The existing observer exhausted 30 ten-second attempts before a missed webhook could
be recovered by the existing fifteen-minute frontend timer. An offline sixteen-minute
convergence case failed on the original code. The correction allows at most 121 reads
under a twenty-minute monotonic deadline, retaining the existing twenty-five-minute
Actions job. Slow reads consume the budget, sleep cannot extend it, and verification
finishing after expiry cannot emit PASS. Permanent errors, exact SHA/project/content,
health, financial and retirement checks remain intact. No scheduler or workflow writer
was added. Six new regressions pass; full results are in the
[validation record](MONEYBOWL_M4_VALIDATION.md).

### Actual host staging and recovery evidence

- Installed 25 exact tracked files from the published candidate at
  `/opt/moneybowl-deployment/bc1870c5ca87962d9768a9000ba02798c7175df4/tools/deployment`.
  Source files are root-owned `0444`, directories `0555`; `INSTALLATION.json` binds
  their SHA-256 values and records `activation=false`. This is a new version alongside
  `535050e0bb6afcd4c019fee6d85015d2172a7672`, whose 25 files remain unchanged.
  Existing `/etc` pins still select the older version. The new local observer correction
  is for review; it was not substituted into this published-source installation.
- Exported the exact legacy API image to the private recovery directory
  `/var/lib/moneybowl-ingestion-deploy/recovery/1c38aa4946fdb961ed7b0983edb6925988961891c91a0b9e296d84ac8a59286f/`.
  `legacy-api-image.tar` is 54,473,216 bytes, SHA-256
  `009b26a7c81735b271100a1fe3b7051fda93ad4927c07119eaaea229d418ed49`.
  Docker 29 identifies this image by its OCI index, not its config blob. Verification
  traversed all 14 referenced OCI blobs, checked descriptor sizes/digests, and checked
  all eight decompressed ARM64/Linux layer hashes against the config's rootfs diff IDs.
  No image was loaded, built, pushed, deleted or replaced.
- `RECOVERY.json` explicitly records `git_commit=null`, unknown source provenance,
  no restoration test and no replacement authorization. `recovery-api.compose.json`
  selects only the exact local legacy image ID and one API replica. It is an emergency
  recovery input, **not** historical provenance or permission for normal M4 adoption.
  Off-host retention and an independently reviewed restoration exercise remain pending.
- Capacity gate passed with 68,732,805,120 available bytes before this staging.
  All seven original container IDs/images and normalized runtime relationships remain
  recorded. API, ClamAV, webhook and M3B receiver were healthy; Caddy and ingress
  adapter running. Oracle dispatcher remains exited with restart `no`, persistent
  service masks and disabled/inactive reconciliation timer.
- Existing Flutter timer and webhook dispatch path remain enabled. No owner units,
  timers, activation stamps, handlers, active configuration or running containers changed.
  Receipt roots are still empty. No credentials were read, generated or rotated.

Private execution evidence is under
`/home/ubuntu/moneybowl-m4-completion-20261011`. Existing unit proposals passed syntax
verification but still refer to the older installation and require a reviewed handoff;
syntax acceptance is not operational commissioning.

### Exact remaining prerequisites

| Owner / component | Observed blocker and required operation |
| --- | --- |
| Repository | `develop` is unprotected; effective branch rules and M4 Actions variables are empty. Establish reviewed-PR/latest-push/check requirements with no bypass, independently review the local correction, then publish and rerun CI. This task did not push or merge. |
| Existing infrastructure owners | Disabled ingestion config still contains `REPLACE_WITH_OWNER_REVIEW_RECORD` on all five layers and an invalid model digest. Complete the existing protected measurement transaction with authoritative `M3B_RECEIVER_IMAGE`, `M3B_RECEIVER_SECRET_FILE` and `M3B_WAKE_GID` interpolation inputs. Independently approve resolved service hashes, mounts, networks, volumes and before-state. Do not derive authorization from observed container labels. No M3B deployment or Director operation is required. |
| Ingestion registry | `image_repository` still names `registry.example.invalid/moneybowl-ingestion-dev`; `/var/lib/moneybowl-ingestion-deploy/docker-auth` is absent. Supply an approved repository and scoped private push/pull authority, with no credential in Actions or Git. |
| Initial API transition | No historical record exists at the configured provenance path. Complete separate review of a selected exact source SHA, new image digest/ledger and recovery procedure before replacing the unknown legacy image. The archive alone cannot authorize or attest the transition. |
| API readiness | `service_origin` is still `https://ingestion.example.invalid`. Bind the actual Caddy-served API origin and demonstrate the existing read-only `/ready` route returns exactly the required JSON. |
| Frontend owner | `/opt/moneybowl-toolchains/flutter-3.44.6/bin/flutter` is absent. Install a verified protected Flutter/Dart toolchain with a working cache model and pins. Review release-root write access for `moneybowl-deploy` and the existing spool/service handoff, keeping the one existing fifteen-minute timer and shared build lock. |
| Ingestion identity | The dedicated identity lacks access through `/home/ubuntu` and lacks the reviewed Docker authority. Provision narrowly scoped access to required Compose inputs and owner state without widening unrelated home/Director access. Docker authority remains root-equivalent; evidence must never receive it. |
| Supabase measurement | `/etc/moneybowl-deployment/credentials/measurement-token` is absent. Provision project-scoped `database_read` and `edge_functions_read`; prove the exact read-only migration/control/Cron queries and pinned CLI exports work. Existing MCP access is not a credential for the installed evidence owner. No admin fallback or schema grants were added. |
| Readiness-only authentication | A local root `0600` readiness-only credential already exists; its value was not read. Existing commissioning records show it has not been provisioned to Edge and deployed code lacks its handler. Deploy reviewed code through the existing Supabase integration, then provision the same separate readiness-only capability privately and verify it. Do not use notification/worker/service-role secrets. |
| Independent receipts | Backend/service/release directories contain zero receipts. Public `/m4/backend/<develop>.json` returns HTTP 200 HTML. The ingress owner must review receipt access/routing with TLS, no-store and genuine 404s, preserving shared Caddy resources; that container change was not attempted. Only then set `M4_DEV_FRONTEND_ORIGIN=https://moneybowl-app-dev.duckdns.org` and `M4_DEV_EVIDENCE_URL=https://moneybowl-app-dev.duckdns.org/m4/backend`. |
| Final owner activation | After all gates, review new version pins, enable only the ingestion/evidence owners and adapt the existing Flutter handler/timer. Observe one genuinely merged develop SHA and fresh independent backend/image/asset receipts in Actions. QA and Production remain disabled/out of scope. |

Fresh Supabase read-only checks found DEV `ACTIVE_HEALTHY`, dispatch mode `active`,
one active fifteen-minute recovery job and 92 migrations with statement arrays.
These counts do not establish source-content equivalence or a valid backend receipt.
Public frontend TLS still serves exactly `8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`,
without M4 asset/configuration evidence. No automatic deployment PASS was observed.

### API-only initial transition for separate review

1. Keep owners disabled while completing approved Compose baselines, actual API
   readiness origin, registry access and recovery retention. Confirm the legacy
   image/archive/container IDs above still match. No synthetic historical record.
2. Select and independently approve a full source SHA already in develop ancestry.
   The source needed for the first merge is not yet known. Through the **single private
   ingestion builder**, build that exact archive, capture its iidfile, push once to
   the approved registry, and verify OCI revision/source-digest labels, image ID,
   immutable registry digest and the one-worker command. Preserve the new ledger and
   exact generated API override. This build has not been executed.
3. Before replacement, compare every support service hash with/without that override,
   verify runtime/resource baselines and retirement, and retain the private resolved
   input provenance. Obtain separate review of these concrete before/after artifacts.
   Missing historical provenance is handled by this one-time infrastructure-owner
   transition, not by enabling or bypassing `initial_revision` in the normal reconciler.
4. The separately authorized infrastructure owner may then select only `api` using
   the existing ordered Compose prefix plus the reviewed override and
   `up --detach --no-deps --no-build --pull never --scale api=1 --wait --wait-timeout 120 api`.
   Do not perform this operation until the input/rollback review above is complete.
   Preserve all old images/resources. Recheck API/public health, new labels/digest,
   support identities and financial retirement before recording acceptance.
5. For a failed transition, withhold PASS and keep reconciliation disabled. Emergency
   recovery requires separate operator review using the preserved local image and
   API-only recovery override against those same approved inputs. An archive integrity
   check is not a successful restoration test. Do not automatically roll back, restart
   support services, dispatch financial work, or move an approved Git ref backwards.
6. Only after the new known image is running and its genuine ledger/override has been
   independently verified can the normal owner's labelled-image path commission it.
   Subsequent merges use the existing exact-source owner and independent observer.

### Off-host ARM64 build decision

[GitHub-hosted ARM64 runners are available](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
They are deferred for the first commissioned release because the current contract
creates provenance from the private owner's exact archive, Docker iidfile, push and
local immutable-digest verification. It has no reviewed workflow-identity/attestation
verifier or remote ledger import path. No approved registry or credential scope is
configured either. Adding a hosted publisher while retaining `DockerOwner.build()`
would create two build owners; trusting an arbitrary digest would weaken provenance.
Retain the existing single private builder. A later reviewed replacement can use a
pinned ARM64 job, immutable digest and verified repository/workflow/SHA attestation,
and must remove private rebuilding as part of that same ownership change. No Actions
Supabase credentials or second Supabase deployment path are needed.

The next safe operation is to supply the authoritative private Compose interpolation
inputs and complete independent baseline measurement, while reviewing this local
correction and provisioning the missing registry/measurement capabilities. A merge
or live image replacement before those gates cannot produce a genuine M4 PASS.

## Initial API transition implementation validation — 2026-10-12

Implementation is local and reviewable; **live commissioning remains BLOCKED**.
The [new runbook](MONEYBOWL_M4_INITIAL_API_TRANSITION.md) specifies the implemented
phases, exact candidate/legacy identities, scoped private registry provisioning,
five-layer baseline approvals, one-use owner authorization and reviewed recovery.
No private registry was provisioned, no image pushed/rebuilt, no live transition run,
no owner service started, and no Supabase/Production/Caddy/Director changes occurred.
Independent candidate inspection and Git component measurement matched the supplied
image/source/digest. Canonical develop remains `8afa04f9db4a3429fdfeef503d4ebaf6abf18aa5`.

| Final validation command | Result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment` | 244 passed, 0 failed; includes 73 new initial-transition/OCI cases; original baseline 171 passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning` | 34 passed, 0 failed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p test_validate_commits.py` | 5 passed, 0 failed |
| `env -u INGESTION_SUPPORT_BASE_URL PYTHONDONTWRITEBYTECODE=1 timeout 120 /tmp/moneybowl-m4-venv/bin/python -m pytest -o addopts='' -m 'not integration' -q` in `services/ingestion-support` | 194 passed, 0 failed, 1 live integration test deselected; authorized local test sockets only |
| `PYTHONDONTWRITEBYTECODE=1 /tmp/b061-test-venv/bin/python -m pytest -o addopts='' -q` in `services/outbox-dispatcher` | 63 passed, 0 failed; offline compatibility tests, no dispatcher process started |
| `PYTHONPYCACHEPREFIX=/tmp/m4-initial-api-compile python3 -m py_compile` on six changed/new Python files | Passed; all bytecode outside canonical repository |
| `PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/validate_migration_history.py` | Passed; 27 frozen migration files unchanged |
| `PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate_outbox_routes.py --check` | Passed; 17 canonical routes unchanged |
| `PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/validate_docs.py` | Passed; documentation links/anchors validated |
| `PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/validate_commits.py 'feat: add one-time verified Mailback API transition'` and `git diff --check` | Passed |

The first restricted ingestion harness stalled on local TestClient sockets and was
terminated; the authorized local-socket rerun completed. Quiet-mode exploratory runs
were repeated with summaries enabled for exact counts. Final suites have zero failures;
540 test cases passed across the five final suites. No live integration smoke was selected.
The optional entrypoint inspector remains a separately documented PR #209 dependency
for the regular owner. The initial controller rejects nonempty entrypoints, wrong commands,
extra workers, root users and unsupported image/platform provenance.

Final implementation review checked exact API-only command scope, the unchanged normal
historical-provenance guard, one-use authorization/expiry/revalidation, shared locking,
protected file/parent/link permissions, remote privacy/digests/config/layer availability,
credential-free blob redirects, immutable failure diagnostics, preserved rollback data,
source/branch/container/resource drift gates and publication ordering. Independent review
subsequently reproduced approval-authority and crash-consistency gaps in that candidate;
the corrections below supersede the original publication-ordering assessment.
No independent security certification or full M4 release PASS is claimed.

## Initial transition security review corrections — 2026-10-12

Corrective work began from exact feature HEAD
`a86515bc03f9b1c80032651582022dca7e0a16be`, with a clean worktree and canonical
develop unchanged at `8afa04f9db4a3429fdfeef503d4ebaf6abf18aa5`.

**Approval authority:** the previous `approve()` checked private filesystem modes and a
nonempty `owner` field but accepted the executing user's own directory/file. That was
self-authorization, not independent authority. All initial phases, the CLI and initial
Docker adapter now require real/effective UID 0 and explicit `root-operated-cutover-v1`.
The CLI configuration, approval file, approval directory and every ancestor are checked
for root ownership, protected modes and absence of symlinks; approval/configuration
files must have one hard link. `owner` remains only a human review reference. The existing
`moneybowl-ingestion-deploy` identity (UID 993/GID 983) cannot cross this initial boundary.
No sudo helper, new service, key or credential was introduced. The host administrator
is explicitly trusted; Docker socket access remains root-equivalent. Expiry, exact
DEV/project/API/plan/branch bindings and one-use no-retry consumption remain enforced.

**Completion integrity:** the previous journal could become `VERIFIED` before receipt
publication; the normal owner trusted that state alone. Verification now durably enters
`VERIFYING` before checks/publication, writes immutable measurement evidence, provenance
and a permanent private `initial-service-receipt.json`, then commits the digest-bound
completion journal last. Every normal reconciliation validates the matching journal,
archived plan, verification, original ledger and private receipt before branch measurement
or deployment work. Old, missing, inconsistent or interrupted completion fails closed.
Normal report renewal and override regeneration do not alter the archived initial receipt.
No initial success is exported to the normal report directory during the transaction.
Preparation also requires protected `acceptance_required=true` enrollment, retained after
handoff so disabling initial activation or deleting every archive cannot remove the gate.
An unused disabled section without enrollment/artifacts preserves the normal owner's
existing independently provenanced path; retained artifacts always force the gate.
The private archive is not independently commissioned public HTTPS hosting or a full
M4 acceptance receipt. Abrupt termination preserves unresolved durable state and immutable
artifacts; it does not trigger retry or rollback. A termination after the final completion
commit is accepted only with the entire validated artifact tuple.

Regressions reproduce arbitrary-owner same-user approval and deny the real service UID,
executor-owned approval/configuration or ancestors, writable ancestors, symlinks and hard
links. Twenty before/after publication interruptions use `BaseException` and `SystemExit`
at the verification-intent, measurement, ledger, private-receipt and completion boundaries.
Missing/tampered tests cover each of the five completion artifacts, including the exact
old `VERIFIED`-without-receipt failure. A legitimate synthetic transition followed by two
normal reconciliations preserves the private receipt. Tests use disposable Git fixtures
and synthetic Docker/registry results, never live Docker or Supabase.

A fresh read-only bypass/regression reviewer found no surviving route for the two supplied
triggers, and reproduced one compatibility regression in the first corrective candidate:
an unused disabled initial section blocked an independently proven normal owner. The
enrollment/artifact distinction above corrects that confirmed regression, with positive
normal-owner and negative missing/orphaned-artifact cases. This review is not a hosted
commissioning or independent QA certificate.

The updated [runbook](MONEYBOWL_M4_INITIAL_API_TRANSITION.md) specifies the root approval
boundary and separately reviewed handoff to the normal UID 993/GID 983 service. The legacy
image's source revision is still unknown; the reviewed candidate remains local-only.
Private registry publication/provenance, five-layer runtime/configuration approvals,
recovery review, PR #209's normal-owner optional-entrypoint fix, independent review and
public measurement/HTTPS evidence hosting remain commissioning prerequisites. No scheduler
or Jenkins integration was added. API-only replacement, unrelated service preservation,
financial retirement and original historical-provenance safeguards remain in force.
M4 is not fully commissioned. No live infrastructure or canonical develop was modified.

| Corrective validation command | Result |
| --- | --- |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment -p test_initial_api_transition.py` | 119 passed, 0 failed; includes 46 added authority/completion regressions |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/deployment` | 290 passed, 0 failed; includes all focused cases |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/commissioning` | 34 passed, 0 failed |
| `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/scripts -p test_validate_commits.py` | 5 passed, 0 failed |
| `PYTHONPYCACHEPREFIX=/tmp/m4-corrections-compile python3 -m py_compile tools/deployment/{protected_io,initial_api_transition,initial_transition_integrity,ingestion_owner,test_initial_api_transition}.py` | Passed; bytecode outside repository |
| `PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/validate_migration_history.py` | Passed; 27 frozen migrations unchanged |
| `PYTHONDONTWRITEBYTECODE=1 python3 scripts/generate_outbox_routes.py --check` | Passed; 17 canonical routes unchanged |
| `PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/validate_docs.py` | Passed |
| `PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/validate_commits.py 'fix: enforce initial cutover authority and completion integrity'` | Passed |

The complete final owning suites total 329 passed, 0 failed; the focused 119 are included
in that total. During test development, authority mocks and the synthetic Compose hash
model needed adjustment; the final commands above passed. API and retired-dispatcher
code were unchanged and their historical implementation counts above are not represented
as new corrective runs. All tests remain offline; real execution identities are modeled,
not acquired. No live initial transition or public commissioning validation was attempted.
