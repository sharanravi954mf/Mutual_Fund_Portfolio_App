# MoneyBowl shared protected-merge deployment — issue #218

## Current implementation and preserved state

The owner approved one shared release workflow on 2026-11-02. This source-only
implementation supersedes expansion of the historical DEV-specific M4 admission
and resident Evidence Owner path below. Historical records are retained verbatim.
The accepted initial API cutover remains permanent. Recovery source
`36d29db9836672b879b4c5689ddc5926d4bc3366` remains ROOT_INSTALLED_INACTIVE.
The paused credential manifest `844ec11952bc6365c4e67e66b493ca28a545c7c4c59afc26a20aa9b08e8cd0b6`
is not executed or repurposed. Source validation is not live acceptance.

`environment-promotion.yml` retains all required CI and calls `shared-release.yml`
only after a protected-branch push. There is no environment input, PR deployment,
dispatch deployment or automated merge. Admission independently checks the real
owner-merged two-parent commit, reviewed head, promotion ancestry/tree and the
three actual GitHub Actions app-15368 checks: `M4 Required CI`, `validate-commits`,
`validate-docs`. Mapping: develop → dev, qa → qa, main → production. Runtime names
remain DEV/QA/PROD; Flutter names remain dev/qa/prod. QA and Production are not
commissioned; their project bindings are absent and gates remain closed.

The reusable workflow selects the private component-tagged image only after
comparing its original build source and component tree. Otherwise it builds an
ARM64 OCI artifact on an isolated, credential-free GitHub VM. A separate publisher
retains the bounded OCI validator and private-package checks, publishes by digest,
and adds standard provenance to the registry. Tags are lookup hints, never trust.
Original build SHA and deployment merge SHA remain separate. Every environment
also builds Flutter with public-only configuration. The commissioned Flutter
adapter remains its publisher; the new workflow does not become a second writer.
Its built artifact is retained for comparison/handover, not claimed as installed.

Supabase remains owned by its existing GitHub integration. The workflow contains
no migration/function deployment command. Read-only inspection observed a successful Supabase Preview check from the real
`supabase` GitHub app and active repository hooks. This does not prove its
deployment target/configuration. Before commissioning, inspect the real
integration branch/project/configuration and confirm its only writer; source docs
or a function count do not establish that fact. Read-only verification uses actual
migration statements, deployed function exports/JWT configuration, authenticated
outbox controls/readiness, frontend identities/assets and the host API result.
Function export verification reuses the previously reviewed erased-type-import
correction from `7bc5620ed0cece3567e40e0977ea3d08ac1f3d63`.

The host component is a fixed systemd oneshot, without timer, broker or daemon.
An SSH forced command running as UID/GID 993:983 accepts only a bounded signed
JSON request and may start only `moneybowl-api-deploy.service` through the exact
Polkit rule. No Docker group/socket, sudo, arbitrary unit/command/config path or
root shell is granted. The host verifies the request signature, target project, approved infrastructure source pins,
15-minute expiry, image provenance and fixed approved runtime. It uses the original
DEV `.owner.lock`, a separate private shared-release journal, API-only Compose
`up --no-deps --no-build --pull never --wait`, and actual post-activation identity.
Incomplete journals, failed health, drift and uncertain outcomes stop without
retry or rollback. Original M4 journals, consumed intents and archives are untouched.

GitHub protected workflows become release authority; the host does not reconstruct
GitHub governance through a repository PAT. Signature verification uses pinned
workflow/source identity and registry-carried/local bundles with sealed trust roots.
The real CLI requires authentication even for these bundles; the verifier process
alone receives the existing sealed root GHCR pull credential as `GH_TOKEN`. Its
actual scope is read:packages only. No new repository token, scope or signing
authority is introduced; Docker/git/systemctl processes receive no `GH_TOKEN`.
The verification job has separate read-only credentials but shares GitHub's trust
domain. It is not claimed to provide the old resident Evidence Owner independence.

## PR #219 review corrections — 2026-11-03

Production readiness uses the existing authenticated `readiness` kind. The actual
Edge handler accepts PROD and returns before RPC/worker admission even when mode
is disabled; both M2 schemas accept PROD but prohibit active non-DEV dispatch.
The scoped Python reader now supports that contract with a distinct project and
readiness-only key. No financial or NSE operation is invoked. Shared QA/Production
verification accepts the actual inert absence of recovery Cron, or the existing
canonical inactive job. DEV retains its required active recovery contract.

Both observer jobs wait read-only for existing owners, with a fixed 15-minute
budget, at most 91 attempts and ten-second intervals. HTTP, CLI export and ancestry
reads are limited to remaining time; each job has a 22-minute outer deadline for
setup and result publication. The admitted project/branch/SHA and actual checkout
are checked before waiting; the current protected head is checked before every
attempt and after measurements. Supersession stops rather than adopting a new SHA.
Only a known ancestor frontend may be pending, and success requires the exact
requested SHA, assets, function exports and migration statements. Invalid targets,
failed functions, corrupted same-SHA frontend assets and denied credentials fail
closed. Pending owners time out with an explicit reason/attempt count in sanitized
backend/deployment results, propagated into the final release result. Waiting
never invokes a deployment writer, repeats API activation or enables an environment.

## DEV installation and remaining requirements

### DEV commissioning corrections — issue #220, 2026-11-03

PR #219 is merged at `b55fb1a4c6ff3ae7f05341766472095836fe8215`.
Fresh inspection confirms the accepted API and five support identities, retired
dispatcher, permanent acceptance and inactive M4 authority remain intact. GitHub
environment `dev` now restricts deployment to branch `develop`; its project and
public application settings are bound. No release gate is enabled. The actual
Supabase default branch reports `git_branch=develop` for project
`rskryngwzyuzmiwtriyy`. Its integration and the existing Flutter publisher remain
the deployment writers. The root registry credential passed actual pull-only
scope/private-image checks. UID 993's legacy package-write token and shared build
group remain unchanged; the existing Flutter unit still uses that build group.

The corrected host journal compares API component identity before planning an
activation. Flutter-only, Supabase-only and documentation-only releases record
`unchanged`, retain the exact API observation and perform no Docker pull or Compose
update. Results distinguish the selected, authenticated candidate image/build SHA
from the actual running API image, build SHA and activation SHA. The first shared
release can retain the permanently accepted API when its component is unchanged.
Changed API components still require one authenticated activation, health checks
and unchanged support services. Interrupted no-op journals also stop for review.

The reviewed SSH correction uses `shared_login.py` as a root-owned, fixed login
executable, accepting only sshd's `-c moneybowl-shared-deploy` invocation as
UID/GID 993:983 with zero effective capabilities. It rejects requested commands,
interactive login and subsystem requests, then executes only the sealed client
with an empty/minimal environment. It supplies no command interpreter. Installing
it requires an explicit account-shell change after this source is merged; current
account metadata is unchanged. The supplied tmpfiles entry recreates only the fixed
root:983 result parent at boot, without starting a deployment service.

The merged `b55fb1a` source closure (45 public files) is installed root:root 0444
under `/opt/moneybowl-shared-deploy/b55fb1a4c6ff3ae7f05341766472095836fe8215`;
its launcher and fixed one-shot unit are installed inactive. Independent blob/
SHA-256/inode checks and durable create-only installation records passed. The new
DEV release journal is empty. A root-only disabled host policy, inactive DEV unit
drop-in and fixed inbox/result directories were subsequently installed after real
runtime, permanent initial acceptance, retirement, capacity and seal checks passed.
Its 47 runtime environment entries are unchanged. Independent admission rejects the
disabled policy. SSH and Polkit grants remain absent; the correction source in this
PR is not installed. A new root-private DEV SSH key and TUF-verified Sigstore trust
snapshot are staged; DEV environment SSH and readiness-only secrets were bound by
encrypted process pipes without disclosure. No account/group change or legacy
credential rotation occurred. This is partial installation, not enablement.
The existing Supabase measurement credential fails a
real DEV functions read with HTTP 401 and is preserved, without fallback or renewal.

Real read-only preparation also diagnosed two runtime-contract defects before
creating any host-policy intent. The support API has no Supabase URL/client; its
47-entry sealed environment is preserved, and the environment label, signed target
and root project policy provide the binding. Preparation rejects unexpected
Supabase configuration instead of requiring a nonexistent `SUPABASE_URL`. The
Docker Engine omits the optional image `Entrypoint` key, so shared image inspection
reuses V2's `index .Config "Entrypoint"` lookup. Deterministic tests exercise the
real runtime validator for DEV/QA/Production and the missing-entrypoint case.
Real OCI verification confirmed the CLI authentication prerequisite and that the
existing pull-only credential satisfies it. The accepted baseline has no shared
workflow attestation and its component tag is absent (404), so the first DEV
artifact validation must build/publish a genuinely new attested candidate. Existing
private package metadata confirms the exact repository binding. The baseline API
continues under its permanent acceptance; no provenance is invented for it.

Before enabling the host, the existing workflow/publisher can validate real private
OCI publication and provenance on a normal owner-merged DEV push. This requires
repository variable `MONEYBOWL_SHARED_ARTIFACT_PREFLIGHT_ENABLED=owner-approved-v1`
and DEV environment `SHARED_PUBLICATION_ENABLED=owner-approved-v1`. It never enables
`SHARED_DEPLOYMENT_COMMISSIONED`, requests a host authorization, reaches measurement
credentials or publishes Flutter. Admission still checks the exact owner merge and
required CI. QA/Production cannot use this path. It is the same artifact producer,
not another deployment writer or controller. The artifact-only gate is unset until
reviewed source and public configuration are ready, and is removed after successful
validation; normal deployment uses the existing full-release gates.

Remaining installation steps below require real provider/export/provenance checks;
source tests do not commission deployment. New code is never installed from an
unmerged worktree. No changes to paused M4 credentials, QA or Production are made.

1. Review the exact source commit/PR and complete deterministic and GitHub CI checks.
   Reconfirm API/support identities, retirement, initial acceptance and current seals.
2. Review one bounded privileged installation effect list: new versioned root-owned
   code/launchers; disabled host configuration and privately measured runtime;
   executable/code/credential/trust-root/machine seals; new private journal; existing
   lock relationship; inbox/result directories; inactive oneshot; restricted Polkit
   and SSH configuration. Preserve every existing installed M4 artifact and inode.
   No source-only helper is privileged approval. Require explicit owner approval
   for exact installation/configuration/credential and first-enablement effects.
3. Bind all actual facts in `shared-host.example.json`; it is disabled and incomplete.
   Reuse independently verified root pull-only registry authority without copying
   credentials into source. The runtime snapshot includes actual image defaults and
   exact DEV Supabase URL. Keep secrets private and absent from results and journals.
4. UID 993 currently has a nologin shell, legacy package-write auth and build-group
   membership. Install the reviewed restricted login executable only after source
   merge and account-consumer review; investigate all legacy
   credential/group consumers before approving any account change or isolation.
   Do not revoke, rotate or alter those authorities implicitly. Require ForceCommand,
   no PTY/forwarding/user RC/environment, independent host-key pin and no password login.
5. Establish environment `dev` with branch restriction exactly `develop`; set its
   reviewed host/project/public frontend settings, deployment key, scoped Supabase
   measurement token and readiness-only key. Validate real export and OCI attestation
   compatibility. No service-role, notification or financial writer fallback.
6. Keep `MONEYBOWL_SHARED_RELEASE_ENABLED` unset until this DEV path is commissioned.
   Each GitHub environment separately requires `SHARED_DEPLOYMENT_COMMISSIONED` and
   `SHARED_PUBLICATION_ENABLED`, both exactly `owner-approved-v1`. Old M4 publication
   variables are not reused or enabled. Environment secrets never reach PR jobs.

## Three-environment commissioning and acceptance

### DEV enablement and acceptance — issue #224, 2026-11-05

PR #223 merged at `7371db2f5f601bbe598d33ad02b2ea9322dc1513`; run #63
(`42093304880`) passed required CI, isolated ARM64 build and private publication.
Oracle independently verified image
`sha256:8fbe3f84da04428529238fcad3d50c8ae328ed1db31b74bf4dd39a010757808d`,
its private repository binding, ARM64 runtime configuration and registry-carried
signature using the actual installed CLI, sealed trust roots, exact source and
shared signer workflow. The existing pull credential remains read:packages only.

The root host remains installed at reviewed `afa7369`. Only `commissioned` changed
to true; the original disabled policy inode is preserved in the configuration
archive. Root intent/completion `enable-dev-7371db2-20261105.*.json` bind the change
and independent installed-authority/runtime checks. Real SSH and Polkit checks
passed; the latter uses a trusted action-owner caller against a live zero-capability
UID/GID 993:983 subject. Arbitrary commands and unrelated unit actions are rejected.
Groups, secrets, initial acceptance, recovery/M4 records and shared lock are preserved.
The API and five support containers are unchanged, dispatcher retired, oneshot
inactive and release journal empty. Enabling the host is not deployment acceptance.

GHCR's config GET actually returns 307 to its documented
[GitHub content host](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#communication-requirements-for-github-hosted-runners).
The selector correction admits one bounded download only from the fixed package's
digest-addressed blob path to exact HTTPS `pkg-containers.githubusercontent.com`.
Registry/GitHub headers are never forwarded; other redirects and further hops fail.
The downloaded config must still match the manifest's digest. No URL query or token
is logged. Synthetic tests cover the observed response and isolation/failure cases.

The acceptance change adds `Cache-Control: no-store` to `/health`, preserving its
status and exact JSON and introducing no business or financial operation. After
required source checks, DEV environment commissioning plus the shared repository
gate permit automatic releases on owner merges. QA/Production environment gates
and legacy M4 publication stay unset. No workflow rerun, manual API activation or
synthetic record counts as acceptance: the owner must merge the feature PR normally,
then the real shared workflow must authenticate/deploy the changed API once, observe
existing Supabase/Flutter convergence, and produce a complete measured release result.

### DEV execution and publisher correction — issue #222, 2026-11-05

PR #221 merged at `afa7369118a9dc844718f3b2896870ca87c05a5e`.
Run #60 (`41698192927`) passed required CI and isolated ARM64 build, then rejected
GHCR's HTTP 202 relative upload location before sending blob content. GHCR uses
`/v2/<exact package>/blobs/upload/<opaque handle>`; the publisher assumed plural
`uploads`. The correction accepts only those two explicit paths on HTTPS ghcr.io,
with the exact package and a bounded opaque handle. Redirects, foreign hosts,
repository escapes and fragments remain rejected. Existing query state is retained
verbatim when appending the content digest. Standalone and embedded publisher bytes
remain identical; private-package and authenticated-provenance checks are unchanged.

The reviewed merged host source is installed root-owned at `afa7369`, with the prior
`b55fb1a` source and shared policy inode preserved. The restricted login executable,
dedicated key, SSH Match fragment, exact-unit Polkit rule and result-parent tmpfiles
entry are installed. Actual SSH tests reject invalid envelopes and arbitrary
commands before inbox/unit creation. Actual UID/GID 993:983 has zero capabilities,
cannot read private policy/runtime/registry/journal or access Docker, and is
authorized by Polkit only for the fixed unit's start; other tested units/verbs
require administrator authentication. Groups and legacy credentials are unchanged.
The deployment policy remains disabled, its oneshot inactive and release journal
empty. No API activation occurred; all five support identities, dispatcher
retirement, permanent acceptance and inactive M4 state passed independent checks.

The owner-provisioned DEV-only Database Read/Edge Functions Read token passed actual
92-migration statement comparisons, all 20 function export/source/JWT checks and
authenticated readiness, and is encrypted in environment `dev`. Expiration is
owner-confirmed as 2027-02-01; tested APIs do not expose full token scope/expiry.
DEV artifact validation/private publication is configured for owner merges. The
full shared-release and DEV commissioning gates remain unset, as do old M4 gates.
QA/Production remain uncommissioned. Run #60 is not retried. A new owner-merged
publisher correction must prove publication/attestation before full DEV enablement
and the separate harmless automatic-release acceptance PR.

Protect develop/qa/main: required PRs, strict existing three check contexts/app IDs,
administrator enforcement, no force pushes/deletions and normal merge commits.
Zero required human approvals supports the sole owner; do not fabricate reviews.
Enforce feature/* → develop, develop → qa, qa → main in CI and release admission.
No direct DEV-to-Production route. Create qa only through separately approved
repository configuration work. Bind each GitHub environment to its single branch.

QA needs an independent project, URLs, credentials, host/runtime, frontend adapter
configuration and native Supabase integration. Production requires its actual
project/availability, independent host/credentials, recovery and incident procedures,
and separately reviewed permissions. Root configurations bind distinct project IDs
and machine identities. Production financial controls default disabled. The common
unit grants no DEV state write access. DEV alone installs the supplied DEV drop-in
for its existing lock; QA/Production lock directories live under their new private
shared-deploy state root and never reuse the accepted DEV state.
Only ARM64 API hosts are currently supported. Do not silently reuse a DEV destination.

DEV exit: owner merges a harmless feature PR; all required CI passes; automatic
build/private publication and cryptographic verification succeed; the API changes
once to the recorded digest and becomes healthy; real frontend/database/function
measurements pass; five support containers remain unchanged; the retired dispatcher
remains stopped/restart-disabled; durable intent/completion and sanitized Actions
result exist; duplicate reconciliation returns already_deployed without activation.
Only this real release can establish END_TO_END_VERIFIED.

## QA LIVE KYC functional boundary

QA deployment acceptance is separate from NSE KYC acceptance. No deployment invokes
NSE. Current persisted KYC workers and active dispatcher remain DEV/UAT-only.
The exact external write is POST `/nsemfdesk/api/v1/EKYC/EKYCREG` (KYC fresh
registration); `CLIENT_KYC_REPORT` is a separate report read. Registration may create
real provider records/send a handoff link and is not completed KYC by itself.

The next narrowly scoped functional PR must qualify
`moneybowl_onboarding.kyc_cases`, `kyc_operations`, `kyc_evidence_scope`,
`kyc_context_guard`, `request_onboarding_kyc` and worker claim/finalization contracts
from migration `20261007130243_mfd_onboarding_v2a_kyc_orchestration.sql`, plus their
shared integration/outbox evidence bindings, with QA application environment and
LIVE provider environment. Add an exact KYC-operation allowlist through dispatcher,
worker and transport; preserve DEV/UAT behavior and keep unrelated financial routes
disabled. Do not merely remove `assertNseUatWorkflow` or the non-DEV dispatch guard.
Use a new additive migration after catalog/data preflight and isolated DB tests.

Before any LIVE case: record provider/member authorization, exact permitted and
consenting test identity, allowed AMC/operation, QA credentials/project, any real
record/communication effects and required egress allowlisting. Supabase Edge is the
NSE caller; Oracle's address does not prove Edge egress approval. Explicit owner
and provider authority is required for the operation. Verify registration, handoff
and reconciled completion separately; ambiguous external writes stop for review.

---

# MONEYBOWL M4 — unified environment promotion

The [2026-10-14 backend delivery V2 source candidate](MONEYBOWL_M4_BACKEND_DELIVERY_V2.md)
adds isolated artifact publication and a root API executor with one consolidated
review/install/activate/verify checklist. It supersedes the proposed host-build and
UID 993 private-state handoff for subsequent automation. Historical facts below
remain unchanged; V2 is not installed or live accepted.

The 2026-10-12 [implemented one-time API transition runbook](MONEYBOWL_M4_INITIAL_API_TRANSITION.md)
supersedes the earlier manual initial-transition proposal below. Code and synthetic tests
are implemented for review; the legacy source remains unknown, the new ARM64 image is
local-only, and private registry/owner approval/commissioning remain blocked. No live
replacement or owner activation was performed.

Status: DEV compatibility remediation candidate, 2026-10-11; **end-to-end commissioning BLOCKED**.
Latest execution staged the published `bc1870c5ca87962d9768a9000ba02798c7175df4`
controller without activation and verified a legacy API recovery archive. Capacity
now passes. See the [current commissioning record](MONEYBOWL_M4_DEV_REMEDIATION_001.md#github-actions-completion-execution--2026-10-11)
for the remaining private gates; earlier inspection statements below are historical.
The [DEV remediation record](MONEYBOWL_M4_DEV_REMEDIATION_001.md) contains actual
read-only Oracle discovery, the four/five-layer compatibility contract, capacity
remediation and the precise remaining private commissioning gates. It supersedes
earlier assumptions below about two-layer Compose ownership and a missing frontend timer.
No hosted deployment was performed. Base `origin/develop` was fetched and verified
at `8993ce141ceed6a1cae95c2a7edbfbfcf24524f8`. The canonical checkout was left intact.
The user's commissioning context supersedes older M1/M2/M2A local-candidate notes:
DEV native dispatch is active, one recovery Cron runs every 15 minutes, and Oracle's
financial dispatcher is retired. M4 does not independently recertify those live facts.

## Promotion and deployment ownership

```mermaid
flowchart TD
  Feature[Push feature branch] --> CI[M4 required CI]
  PR[Feature PR to develop] --> CI
  CI --> Review[Owner-required review and branch rules]
  Review --> Develop[Merge into develop]
  Develop --> Supabase[Existing private Supabase integration]
  Develop --> Webhook[Existing Oracle webhook and spool consumer]
  Webhook --> Flutter[Private frontend host adapter]
  Reconcile[Private host reconciliation timer] --> Flutter
  Develop --> Observer[Read-only M4 release observer]
  Supabase --> Proof[Independently measured owner evidence]
  Services[Private ingestion reconciliation timer] --> Proof
  EvidenceTimer[Independent evidence timer] --> Proof
  Proof --> PrivateReport[Recurring full release verification]
  Flutter --> Identity[Public deployment identity and asset hashes]
  Proof --> Observer
  Identity --> Observer
  Observer --> Report[PASS or failed or superseded JSON]
  Develop --> QAPR[PR from develop to qa]
  QAPR --> QACI[Offline QA promotion CI]
  QACI --> QAGate[Private QA commissioning required]
  QAGate --> QA[Independent QA integration and hosting owner]
```

| Component | DEV deployment owner | QA owner | M4 behavior |
| --- | --- | --- | --- |
| Migrations, declared Edge Functions, declared Storage | Existing private Supabase GitHub integration on `develop` | Future separately owned Supabase integration on `qa` | Observe only; no CLI deployments or admin credentials in Actions |
| Flutter web | Existing Oracle webhook/spool and `deploy-develop.sh` | Future independent QA hosting runner | Versioned host adapter replaces the called deploy implementation after installation review; no second webhook consumer |
| Ingestion support API | Private existing Compose owner plus versioned reconciliation adapter | Future private QA service owner | Exact-source build, registry digest, API-only activation, measured verification; installation pending |
| ClamAV, Caddy, existing webhook and M3B ingress/receiver | Existing Oracle infrastructure, Flutter and Director/M3B owners | Independent QA infrastructure owners | Explicit layers and per-service/resource identities verified and preserved; only API may be deployed |
| NSE financial dispatch | M2 native dispatcher inside Supabase | Disabled; independent schema/evidence commissioning needed | No lifecycle operations; preserve active DEV; Oracle dispatcher remains retired |
| Director and host infrastructure | Separate owners | Separate owners | Outside application release; never deployed by M4 |

The ingestion application source, Dockerfile, dependencies, Compose files and
Caddyfile are one hashed component. ClamAV/Caddy images and configuration are thus
included in compatibility evidence; an unchanged API alone is insufficient when
that component changes. The retired `services/outbox-dispatcher` is tested for
compatibility but is deliberately never a deployable component. The automatic ingestion owner is implemented locally; there is no
claim that it is installed or deploying today.

## Exact Actions trigger graph

[Environment promotion workflow](../../.github/workflows/environment-promotion.yml)
has no path filters:

- Every push to `feature/**`, `develop`, or `qa` runs `M4 Contracts`, `M4 Flutter`,
  and `M4 Backend and Integration`, then the always-evaluated `M4 Required CI` gate.
- PR opened, synchronized, reopened or marked ready targeting `develop` or `qa`
  runs the same validation. No PR job deploys or contacts hosted project APIs.
- Only a push to `develop` or `qa` enters `M4 Environment Release`, after the CI
  gate resolves, even if CI failed. Checkout is exactly `github.sha`.
- The release job serializes by `m4-release-refs/heads/<branch>` without cancelling
  an in-progress observer and uses `queue: max`. Up to 100 waiting jobs are retained;
  older slow CI runs cannot replace a newer pending observer. Beyond the platform
  limit, cancellation must alert for a latest-revision workflow rerun. Host deployment
  convergence does not depend on Actions queue ordering.
- QA fails with `environment_not_commissioned` before network access. Neither a
  repository variable nor a workflow dispatch can enable QA; a separately reviewed
  policy change and private infrastructure are required. No manual dispatch exists.
- `main`, tags and Production have no new trigger or target. Existing unrelated
  main-branch validation workflows remain unchanged in purpose.

Existing commit/documentation/migration workflows also recognize `qa`; the M4 gate
always validates migration history, including when their path filters skip them.
The existing outbox workflow is retained. New action references are pinned to full
SHAs. Shared CI uses GitHub-hosted runners and `contents: read` only. No new workflow
references a secret, self-hosted runner, private key, Supabase token or QA admin.
Checkout's automatic repository token is read-only and is never a build define.

The contracts gate records the full PR head SHA. `develop` requires a same-repository
`feature/*` source; `qa` requires the same repository's `develop` source with that
head SHA in fetched develop ancestry. The tested QA merge tree must equal the
reviewed develop tree, preventing QA-only source additions. Advancing develop later
does not invalidate an already reviewed ancestor. No applied migration from the PR
base or previous push may change, disappear or be renamed. Only additions are allowed;
the pre-existing frozen migration manifest is also checked.

## Required repository-owner branch rules

Configure before relying on the zero-command release contract:

1. Require reviewed PRs for `develop` and future `qa`; prohibit direct pushes,
   force pushes, deletion and administrator bypass. Dismiss stale approvals, require
   approval of the latest push, and require resolution of review conversations.
2. Require `M4 Required CI`, existing commit/documentation checks, and the actual
   Supabase integration's migration validation check. Verify exact check names in
   the repository UI. Require branches to be up to date. The unconditional M4 gate
   supplies migration safety even for changes outside existing path filters.
3. Protect workflow files, deployment tools, environment policy and migrations with
   designated reviewers/CODEOWNERS under repository-owner policy.
4. For QA, use the merge strategy whose result preserves the reviewed develop tree;
   resolve any QA divergence through develop before promotion. Preserve SHA ancestry
   for rollback rejection. Do not rebase, force-reset or silently recreate an
   environment branch. Merge queue is not configured by this implementation.
5. Restrict Supabase integration bindings: DEV only `develop`; future QA only `qa`.
   Disable automatic preview creation if feature/PR events would provision shared or
   unwanted projects. Verify these private integration settings separately.

Code cannot infer approval from branch names. Without these rules, branch updates
are not proof of review. M4 does not change repository settings.

## Release identity and independent evidence

[Contract](../../tools/deployment/contract.py),
[observer](../../tools/deployment/observe.py), and
[host adapter](../../tools/deployment/host.py) share environment/branch/project
bindings. DEV is pinned to `rskryngwzyuzmiwtriyy`; QA's project is deliberately null.
The CLI `supabase/config.toml` project identifier is never a deployment target.
Production is rejected by all M4 entrypoints.

The observer requires a fresh HTTPS owner receipt (maximum age five minutes) for
exact environment, project, branch and full merged SHA. Receipt URLs are repository
owner-controlled public configuration, served by the independent private verification
owner. Redirects, proxies, unbounded JSON and credentials in URLs are rejected.
HTTP 404, safe transient transport/408/429/5xx reads, explicit pending components,
and a correctly bound frontend at a proven ancestor may be retried. HTTP 401/403,
untrusted TLS, malformed/mismatched evidence and owner failures are permanent.
Only bounded **reads** are retried (at most 121 observations,
ten-second interval, twenty-minute monotonic deadline; workflow capped at 25 minutes).
This covers the existing fifteen-minute fallback timer plus five minutes of
convergence after observation begins. It is not a cold-build duration guarantee.
Elapsed reads count toward the deadline, sleeps use only the remaining budget,
and no PASS is emitted after expiry. In-flight HTTP reads retain their ten-second
socket timeout and Git reads their existing 120-second command timeout; the workflow
is the outer execution bound. Slow builds remain failed until a later independent
verification or an authorized Actions rerun observes valid fresh evidence.
Migrations, financial operations and deployment writes are never retried by the observer.

The independent [evidence owner](../../tools/deployment/evidence_owner.py) and
[Supabase measurement transport](../../tools/deployment/supabase_reader.py) are now
implemented and synthetically tested. They are **not installed, provisioned or live
certified**. The deployment integration remains the sole Supabase writer. The owner:

1. Fetches current `develop` into its own mirror; extracts that exact revision into
   a temporary source tree. A requested SHA or CI result supplies expectations only.
2. Reads actual migration versions and stored statements through the Management API's
   read-only query endpoint. Requires the complete source history, no extra versions,
   and equal tokenized SQL (comments/whitespace/separators ignored; literals and dollar
   bodies preserved). Missing versions are pending; absent statements, changed content
   or unexplained migrations fail. There is no history repair or migration execution.
3. Lists deployed function IDs, versions, status and JWT configuration. Downloads each
   declared function with the pinned Supabase CLI `functions download --use-api` into
   an isolated temporary HOME. Compares actual exported local module bytes and their
   runtime import closure to Git. Explicit declaration-level `import type` and
   `export type` modules may be absent from the runtime export; their erased bytes
   are not claimed as measured. Every returned module still requires exact Git bytes,
   and ordinary, mixed and dynamic runtime dependencies must be exported.
   Extra functions, changed configuration, incomplete runtime exports,
   import maps/computed imports or source mismatches fail. Missing/deploying functions
   remain pending. Re-reads the metadata and migration snapshots before certifying.
4. Reads only the private project/control identity and canonical Cron projection;
   calls dispatcher **readiness** with a separately provisioned readiness-only HMAC key. Requires the exact project,
   DEV active mode, 17 canonical routes and one active 15-minute recovery Cron.
   The expected NSE origin is supported by the measured dispatcher/runtime source
   and authenticated readiness validation; it is not a new provider/financial probe.
5. Requires a fresh, independently controlled service-owner receipt with actual
   image ID, registry digest, source provenance and measured Oracle retirement.
   Missing service evidence cannot manufacture a retirement claim. Rechecks the
   current branch and publishes sanitized `<sha>.json` atomically.

The receipt includes a digest of the actual migration/metadata snapshot, not raw SQL,
function bodies, environment values or credentials. Source digests are emitted only
following the comparisons above. Unavailable evidence yields 404 or explicit pending
components; unauthorized/malformed/unverifiable measurements yield a bound failure.
A mismatch is not retried within the observer as propagation. The next private timer
cycle remeasures actual state, allowing independent owners to finish convergence.
This may produce a failed Actions observation while an older backend is still serving;
only a later successful measurement can replace that conclusion for the new snapshot.

An unchanged Supabase component may retain an older physical deployment when actual
content matches the approved revision. `git_commit` means the release whose content
was measured, **not** an invented provider deployment SHA. Actual migration records
and function metadata remain the provider's authoritative audit records. The owner
hashes their measured snapshot; private audit retention can archive these records
under separately reviewed data policy. The receipt does not assert that a provider
exposes a trustworthy Git SHA when it does not.

Measurement prerequisites are deliberately fail-closed:

- A privately provisioned, project-scoped Management read capability must permit
  `edge_functions_read` and `database_read`, including the exact migration history,
  `moneybowl_dispatch.commission_identity`, `moneybowl_dispatch.control`, and the
  canonical `cron.job` projection in `supabase_reader.py`. The documented read-only
  endpoint is beta and runs as `supabase_read_only_user`. Private-schema permissions,
  RLS and Cron visibility may prevent these measurements on existing DEV. **No grants,
  administrator fallback or bypass are installed here.** If direct read-only access
  cannot be commissioned safely, review a minimal private measurement projection and
  adapter change independently. Do not substitute the write-capable query endpoint.
- Verify the pinned CLI's real exported module layout/content on the private project.
  Synthetic exports do not establish actual bundle round-trip compatibility. Any
  normalization/unsupported import map requires a reviewed verifier extension, never
  accepting only an entrypoint hash. Remote dependencies retain the Supabase platform
  resolver and approved source pinning trust boundary; they are not independently
  downloaded or execution-attested by this adapter.
- Applied migration statements must actually be retained. Missing historical content
  requires independent provider/audit evidence and a separately reviewed adapter;
  never stamp Git's requested content into history and call it measurement.
- `OUTBOX_READINESS_KEY` is a separate, independently generated readiness-only
  credential. M4 never receives `OUTBOX_NOTIFICATION_KEY`, the database service-role
  key or the worker token. The new key is optional at dispatcher startup: leaving it
  absent preserves existing M2/M2A operation; dedicated M4 authentication fails closed.
  When configured it must be 32–4096 printable non-space ASCII characters, distinct
  from all three existing credentials. Invalid or reused configured values fail
  dispatcher configuration, so never provision a blank/example placeholder.
  The property is non-enumerable and never included in diagnostics.

## Readiness-only authentication and private commissioning

Legacy M2/M2A readiness, event and recovery signatures retain `x-outbox-signature`
and the unchanged canonical signing input. M4 exclusively sends
`x-outbox-readiness-signature`, signing `moneybowl-readiness-v1|` followed by the
same canonical readiness envelope. This header is accepted only on the two explicit
readiness route aliases. Mixed headers fail; no fallback to legacy signing occurs.
Even fresh, otherwise valid event/recovery envelopes signed with the compromised
readiness key fail under either header/signing scheme. Successful readiness returns
before any RPC, admission, continuation or worker request.

Before enabling evidence production, separately authorize and review these steps:

1. Publish/deploy the reviewed dispatcher code through its existing Supabase owner.
   Deployment alone does not need the new secret or change DEV mode, Cron, routes,
   Vault notification key, or M2A commissioning state. Do not bootstrap, activate,
   roll back or rotate dispatch as part of this change.
2. Generate a new independent random readiness secret in the private commissioning
   environment (at least 32 random bytes, encoded as hex, is suitable). Provision
   it as the DEV Edge secret `OUTBOX_READINESS_KEY` and as the evidence service's
   `LoadCredential=readiness-only-key:/private/credentials/m4-readiness-only-key`.
   Use the environment owner's reviewed secret-management process. Do not retrieve,
   copy, derive from or redistribute any existing notification/worker/database key.
   No credential goes to Git, Actions, Flutter, receipts or logs. Supabase's
   [Edge secret configuration](https://supabase.com/docs/guides/functions/secrets)
   is the provider interface; no provisioning command is run by M4.
3. Do not carry forward the former `readiness-key` credential file or service mapping.
   This controller reads only `readiness-only-key` and fails if it is absent or
   malformed; it never falls back to a notification credential or environment variable.
   Independently verify the evidence environment has no notification signing secret.
   Any cleanup of an earlier installation requires separate owner authorization.
4. Keep evidence production disabled until its separate Management read capability,
   actual export/history measurements and dedicated readiness response are verified.
   Confirm readiness returns the existing DEV active mode/project/17 routes and the
   independent read-only Cron measurement is unchanged. The negative financial-path
   tests are synthetic: commissioning does not need event/recovery or financial probes.
5. Enable the private owner/timer only through the separately reviewed installation
   procedure below. Archive sanitized measurement evidence, not credentials. QA needs
   its own independently provisioned key and remains disabled in this implementation.

Primary contracts: [read-only Management query](https://supabase.com/docs/reference/api/v1-read-only-query)
and [deployed function inventory](https://supabase.com/docs/reference/api/v1-list-all-functions).

The exact receipt JSON shape is exercised in
[synthetic tests](../../tools/deployment/test_deployment.py). Required fields:
`schema_version=1`, uppercase `environment`, `git_commit`, `git_branch`,
`supabase_project`, numeric UTC epoch `observed_at`, `financial_policy` (`preserve`
for DEV, `disabled` for QA), canonical `nse_origin`, `oracle_dispatcher=retired`,
and `components` with exactly `migrations`, `edge_functions`, `ingestion_support`.
A `dispatcher` measurement must also report authenticated readiness, exactly 17
routes, one Cron with schedule `*/15 * * * *`, and DEV active mode/active Cron or
QA disabled mode/inactive Cron. This matches the supplied DEV commissioning state;
a deliberately paused DEV must stay paused, report unverified, and receive separate
owner review instead of being automatically activated to satisfy a release check.
Each component requires `state=deployed`, `healthy=true`, a `source_digest`, and
respectively `proof=applied_history`, `downloaded_bundle`, or `running_image`.
`manifest(repo, sha)` computes SHA-256 of sorted Git `ls-tree -r` records for the
component paths. These expected digests must only be emitted after actual measurement.
The authenticated HTTPS endpoint is a trust boundary, not a cryptographic proof
against a malicious environment administrator. Do not host editable receipts in
an ordinary frontend release directory or let PR code publish them.

Flutter `deployment.json` binds uppercase environment, project, branch, exact SHA,
whole release content digest, and SHA-256 hashes of `index.html` and `main.dart.js`.
The observer fetches both served assets and compares hashes, checks the release health
file, and rechecks the current branch. Health-file success proves static serving;
it does not prove interactive sign-in or financial health. The host validates the
whole immutable directory digest when reusing a release. Cache behavior must allow
fresh identity/assets (configure no-store for deployment/health files and HTML).

The structured report distinguishes code validated, deployment detected, backend
deployed, frontend deployed, services deployed, post-deployment passed, and entire
environment release verified. Only `state=pass` means environment PASS. `superseded`
exits successfully as an observer completion but always retains
`environment_release=not_verified`; it is not deployment success. Partial deployment
may exist after failure and is reported by stage. No status is synthesized from CI.
The Actions summary and 30-day JSON artifact record that observation; the private
evidence timer publishes an independent timestamped full-release report after later
convergence. Old snapshots are not current health proof; verify freshness and branch
identity before relying on either. The original Actions result is not rewritten; setup or
observer termination produces an explicit failure fallback. Infrastructure cancellation
may prevent artifact upload; a cancelled job is never evidence of deployment.

## Configuration and private installation

| Name/location | Owner | Purpose |
| --- | --- | --- |
| `tools/deployment/environments.json` | Reviewed source | Environment branch/project/financial policy; QA disabled |
| `M4_DEV_FRONTEND_ORIGIN` | Repository public variable | Exact HTTPS DEV frontend origin |
| `M4_DEV_EVIDENCE_URL` | Repository public variable | Independent HTTPS backend receipt base directory; append `/<sha>.json`, no query/credentials |
| `M4_QA_FRONTEND_ORIGIN`, `M4_QA_EVIDENCE_URL` | Future owner public variables | Future public or sanitized QA evidence; not credentials |
| Host config `environment`, `host_authority`, `repository`, `release_root`, `flutter`, `public_defines`, `frontend_origin` | Private environment host | Explicit deployment paths/ownership; never source shell env files |
| `MONEYBOWL_ENV` | Public Flutter JSON | `dev` or `qa`; frontend Production convention remains `prod` but unsupported here |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Public Flutter JSON | Exact project HTTPS URL and project-specific publishable key (legacy anon JWT accepted with matching ref/role) |
| `NSE_CONSOLE_ENABLED`, `MONEYBOWL_DEV_ONBOARDING_PREVIEW` | Public Flutter JSON | String true/false; true permitted only in DEV |

An opaque publishable key cannot be decoded to prove project provenance. The private
owner must validate its public project pairing during installation. No backend/NSE/
worker/HMAC/service-role field is accepted as a build define. Every build starts
with an explicit clean process environment and a temporary HOME; no inherited
backend values, proxy settings or DART_DEFINES enter the compiler. No secret files
were read to prepare these examples. Unknown build keys fail rather than being copied.

One-time DEV installation is a **separate authorized host change**, not executed here:

1. Review the local commit and existing host permissions. Preserve the current release,
   webhook signature validation, spool and consumer identity. Copy the approved
   deployment Python files and policy to an owner-controlled `/opt/moneybowl-deployment`;
   do not execute a mutable source checkout as the deployment controller.
2. Provide Python 3.12+, an owner-controlled full source mirror with read-only GitHub
   access, and pinned Flutter 3.44.6/Dart 3.12.2. Configure a dedicated deployment user,
   release-root ownership and public-only defines. Review the
   [host config example](../../tools/deployment/host.dev.example.json) and
   [public defines example](../../tools/deployment/public.dev.example.json).
   The public key placeholder intentionally fails validation.
3. Stage-test against a temporary root and synthetic frontend. Verify the old current
   symlink is inside `releases`, full source ancestry is available, and the existing
   deployment identity is compatible. No canonical develop checkout update is required.
4. Replace only the existing `deploy-develop.sh` called by `process-spool.sh` with a
   reviewed wrapper executing `python3 /opt/moneybowl-deployment/host.py --config
   /etc/moneybowl-deployment/dev.json`. Preserve one consumer; do not install the old
   dispatcher webhook override, a second listener, or a financial dispatcher.
   Install the wrapper atomically only after draining the old deploy lock so old
   and new implementations cannot overlap. Retain the original for host rollback.
5. Adapt and review the provided [service](../../tools/deployment/moneybowl-release-reconcile.service)
   and [timer](../../tools/deployment/moneybowl-release-reconcile.timer) for that same
   user/controller/root. Set an appropriate service timeout and monitoring. The timer
   drives the same latest-revision adapter and lock, not another webhook consumer.
   It is necessary because the old spool moves failed batches out of its queue and
   does not itself retry; it also covers lost deliveries and busy-branch exhaustion.
6. Stage the [ingestion owner](../../tools/deployment/ingestion_owner.py) separately
   using the [disabled example](../../tools/deployment/ingestion-owner.example.json).
   Approve the ordered four-layer inventory plus the fifth M3B ingress layer found
   on actual DEV, private resolved service hashes, runtime projections, mounted public
   artifacts and named resource identities using the remediation record. The relocated
   M3B file must match its archived Git object; do not recreate the obsolete path.
   Bind the fixed retirement inventory below and its independently verified container ID.
   Unlabelled API adoption now requires a protected authoritative historical build
   record, not bare initial SHA/image fields. Current DEV lacks this provenance and
   needs archive recovery or a separately authorized initial replacement.
   Pin Docker/systemctl and the actual discovered Compose plugin binaries by SHA-256.
   Resolve capacity first: builds/activation reject less than max(12 GiB, 20%) free
   space or max(100,000, 20%) free inodes. Privately provision
   registry auth and exact registry repository. This owner has Docker socket access,
   a root-equivalent capability; isolate it from app users and shared Actions.
7. Review the ingestion [service](../../tools/deployment/moneybowl-ingestion-owner.service)
   and [timer](../../tools/deployment/moneybowl-ingestion-owner.timer). They converge
   the latest branch every 60 seconds after completion, through one private flock.
   Build the exact archived service source with no private context or build args,
   capture Docker's image ID, push to the private registry and bind its immutable
   repository digest in the private ledger. Verify image labels **and** that ledger.
   Generate the existing immutable override; execute only Compose `up` for `api`
   with `--no-deps --no-build --pull never --scale api=1 --wait`. There is no `down`,
   orphan removal, volume deletion, legacy dispatch profile, or dependency restart.
   API readiness is non-financial. Verify running image/configuration, the exact
   single-worker command and absent entrypoint override, one API container,
   unchanged Caddy/ClamAV/webhook/M3B IDs, images, configuration, networking/storage
   relationships and retirement before publishing. A one-use API activation guard
   rechecks compatible host state and the exact approved override before `up`.
   Source changes to Compose/Caddy fail for separate infrastructure review, rather
   than pretending undeployed infrastructure changes succeeded. Preserve all data.
8. Stage the [evidence configuration](../../tools/deployment/evidence-owner.example.json),
   [service](../../tools/deployment/moneybowl-evidence-owner.service) and
   [timer](../../tools/deployment/moneybowl-evidence-owner.timer) in its own private
   measurement environment. Provision the capabilities listed above, read-only Git
   mirror and pinned Supabase CLI 2.115.0 binary. The ingestion and evidence owners
   use separate mirrors/state/locks; neither shares credentials with the frontend.
   Example configurations remain `commissioned: false`; private reviewed configs
   need `true` plus the already reviewed DEV-only policy.
9. Set config files to 0600 and keep installed code, parent directories, credential
   directories, private state/ledger and source mirrors writable only by their owners.
   Symlinked config/working roots and roots inside the application repository fail.
   Serve only sanitized backend/service/final-status directories over independently
   controlled TLS with `Cache-Control: no-store`. Give the web server read access to
   these report directories only; keep provenance, temporary output and credentials
   private. Atomic files use 0644 inside those protected directories. Do not put
   receipts in a frontend-writable release root. Mirror authentication must be
   read-only and host-owned; public source tests use only disposable local Git.
10. Configure service receipt base URL in the private evidence config, frontend
    origin and separate final-status root. Set Actions' public DEV variables only
    after authentic endpoint ownership is independently established. All backend and
    service URLs resolve as `<base>/<full-sha>.json`. Missing files must return real
    404, not an HTML fallback or stale cached success. The evidence timer also runs
    full frontend/asset checks and writes `<release_status_root>/<sha>.json` after
    measurement. Monitor this independent report as well as Actions.
11. Safely stage duplicate calls, failed build, invalid receipts, stale revisions and
    rapid merges. With separate deployment authorization, verify one approved merge
    across the existing Supabase integration, frontend adapter, ingestion owner and
    both reporting paths. Retain exact live receipts and branch/revision identity.
    No timer or service in this procedure was installed or executed against DEV here.

Actual DEV already has an enabled 15-minute `moneybowl-flutter-web-reconcile.timer`.
Adapt that existing owner and spool dispatch together; do not install the example
frontend reconcile timer alongside it. The owner migration and any interval change
need a separate host review, with one lock and one deployment implementation.

Automatic convergence after commissioning is: approved branch update independently
reaches the existing Supabase integration and webhook; the frontend timer covers lost
spool deliveries; the ingestion timer fetches the latest approved branch; the evidence
timer waits by remeasurement and publishes full status after all components match.
No new webhook consumer exists. Shared Actions only observes; it cannot operate any
private owner. A finite Actions timeout remains failed even if a later timer verifies
the release. The later timestamped private result is separate evidence, with
`code_validated=not_observed`; it never rewrites CI or fabricates an approval check.
Repository branch rules remain the authority that makes a branch revision approved.

## DEV Oracle retirement boundary

The private ingestion owner requires this exact versioned inventory; config omissions
or substitutions cannot waive it. The example remains uncommissioned and requires
`retired_container_id` to be independently bound to the actual 64-hex stopped object.
No live object was inspected to prepare that example.

| Artifact | Required measured state |
| --- | --- |
| `moneybowl-ingestion-support-outbox-dispatcher-1` | Same full container ID; `Status=exited`, PID zero, Running/Restarting/Paused/Dead false, Docker restart policy `no`, expected Compose project/service labels |
| `moneybowl-outbox-dispatcher-reconcile.service` | Persistent unit-file state `masked`, load state `masked`, active state `inactive`, substate `dead` |
| `moneybowl-outbox-dispatcher-reconcile@.service` | Persistent unit-file state `masked`; all discovered concrete instances also persistently masked and inactive/dead |
| `moneybowl-outbox-dispatcher-reconcile.timer` | Unit-file state `disabled`, load state `loaded`, active state `inactive`, substate `dead` |

The checks use only Docker inspect/list and systemctl list/show operations. Missing
containers/units, temporary masks (`masked-runtime`), failed/active/unknown states,
duplicate/missing properties, unexpected dispatcher containers or reconciliation
units, and command errors fail closed. The template is checked as a unit file;
loaded instances and instance-specific files are enumerated so a masked template
cannot hide a still-running or unmasked instance. A masked timer is not substituted
for the commissioned disabled/inactive timer contract.

Retirement gates run before building, before activation and before publishing success.
Application activation selects only `api` with `--no-deps`; no retirement remediation,
systemd mutation or dispatcher start command exists in this owner. A failing final
measurement withholds PASS without restarting or rolling back dispatch. These are
snapshots, not protection against a privileged host actor changing state between
checks. Independent host ownership and commissioning remain necessary. QA retirement
ownership is not inferred from DEV: the concrete Docker adapter rejects QA until a
separate reviewed retirement inventory/verification contract is implemented.

## Races, failures, recovery and rollback

The host holds one flock per environment across the build and activation. It fetches
the current branch before building and immediately before activation. Source is an
exact Git archive; builds use isolated directories and lockfile enforcement. A failed
build cannot touch the old current link. New releases are staged on the same filesystem,
renamed into `releases/<sha>`, and never overwritten. Symlink artifacts are rejected.
Activation uses a temporary symlink and atomic rename. Reuse verifies identity and
content and public-configuration digest; duplicates converge without rebuilding.
A configuration change requires a new reviewed revision instead of silently reusing
an old bundle. Legacy same-SHA releases lacking the new manifest fail closed; install
the adapter for a new approved revision, never relabel an existing legacy release. The previous revision must be an
ancestor of the new one, so branch resets cannot silently roll back the application.

A stale explicit SHA returns `superseded`. The normal spool/timer call omits SHA and
tries up to four latest revisions; a branch advancing during a build leaves that
release inactive and moves on. Continued churn fails for a later timer reconciliation.
GitHub and a filesystem switch cannot be one distributed transaction: a commit can
arrive immediately after the final fetch. Later locked reconciliation advances to
that commit; the current link cannot move behind a newer already activated release.
No finite deployment-time check promises the branch will remain unchanged afterward.
Actions independently rechecks the branch before and after observation. Configure
alerts for failed release reports, missing receipts, failed reconciliation units and
an approved branch head remaining undeployed beyond the expected build window.

Component owners are not transactionally coupled. A frontend may advance while a
migration fails; the aggregate report stays failed. Releases must therefore preserve
backward compatibility across rollout skew (additive schema first, compatible workers,
then frontend). There is no automatic rollback, database retry, event reset, lease
cleanup or financial replay. Retry safe observation or the immutable frontend build
through the same reconciler after resolving the cause. Retain failed reports.

A rollback is a new reviewed forward commit reverting application behavior; it still
uses the normal pipeline and new identity. Never move the branch or symlink to an old
SHA, rewrite applied migrations, clear financial evidence/claim tokens, retry MAYBE_SENT,
or restart Oracle dispatch. A schema repair is a new additive migration reviewed
against current data and integration behavior. Emergency host restoration requires
its own owner review and reconciliation policy so the timer cannot fight the operator.

## Future private QA onboarding

Do not create QA resources from this implementation. A separately authorized owner
must provision a distinct private project, hosting runner, integrations, DNS/TLS,
monitoring, least-privilege access and project-specific public frontend settings.
QA administrator, service-role, NSE, HMAC and worker credentials stay inside QA's
private owners; none goes to Oracle DEV or shared Actions. Shared CI can validate
all QA promotion logic without that project. If the private QA receipt cannot be
safely exposed read-only to Actions, the same observer must run on QA's independent
runner and publish sanitized results; shared runners must not gain private access.

Privately establish environment `QA`, correct project identity, intended NSE origin
`https://www.nseinvest.com`, and disabled persisted financial workflows. Do not copy
DEV credentials or activation history. Review schema/evidence readiness separately;
M4 does not authorize financial commissioning. Only after independent review set the
actual QA public project binding and enable its policy, install the private QA adapter
and service owner, configure integration on `qa`, and create branch/rules through the
owner's separate authorization. QA host authority must be `qa-private`. The DEV host
installation keeps a DEV-only pinned policy; do not give it a QA-enabled controller.
No QA administrator credential is needed to run synthetic tests or the shared workflow.

## Status matrix and limitations

| Capability | Implemented | Locally tested | Already live evidence | Pending |
| --- | --- | --- | --- | --- |
| Feature/PR CI and QA compatibility | Yes | Synthetic and repository regressions | PR #207 exists; this remediation not published | Independent review/publication of this correction, fresh CI and branch rules |
| Existing DEV Supabase deployment | Existing integration retained; independent measurement adapter implemented | Mock API/export comparisons and repository regressions | User-supplied working integration; no M4 receipt | Private read permissions, export compatibility, Independent readiness-only key, installation and live certification |
| Existing DEV Flutter/webhook | Existing scripts, spool consumer and 15-minute timer inspected read-only | Adapter filesystem/process tests | Existing current release `8993ce1...` and active timer observed | Reviewed migration of existing wrapper/timer to dedicated owner; no duplicate scheduler |
| Ingestion service promotion | Explicit four/five-layer inventory, API-only guard, capacity checks and immutable image owner | Mock Docker/provenance/race/failure tests; service regressions | Six application containers inspected read-only; new adapter not installed | Capacity, layer approvals, resolved hashes, legacy source proof/initial replacement, registry, private users/config and controlled installation |
| Consolidated status | Bounded observer plus independent recurring backend/full-release evidence owner | Delayed/partial/404/permanent/race tests and synthetic full sequence | None from this implementation | Private measurement capabilities, receipt hosting, timer installation and full live verification |
| QA deployment framework | Shared code, disabled policy | Synthetic isolated QA success/denial | No QA environment | All independent private commissioning |
| Financial state preservation | No mutation interfaces in M4 | Existing M1/M2/M2A safety/SQL tests | User reports DEV active, one Cron, Oracle retired | Live release preservation measurement by private owner |

Local implementation is ready for independent security review, not security-approved.
End-to-end live commissioning remains **BLOCKED** by the explicit private prerequisites
above. No local test is hosted deployment evidence or establishes operational completion.
The Management read permissions, deployed export format, actual Docker/Compose behavior,
real endpoint ownership and Actions execution remain unverified runtime assumptions.

Current references: [Supabase integration ownership and scope](https://supabase.com/docs/guides/deployment/branching/github-integration)
and [GitHub concurrency semantics](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
Supabase changelog was checked; no database/platform upgrade is part of M4. Existing
SQL tests use the repository's pinned disposable Postgres image, not a hosted database.
See [validation record](MONEYBOWL_M4_VALIDATION.md) for commands and observed outcomes.
