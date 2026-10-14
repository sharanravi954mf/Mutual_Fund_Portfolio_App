# M4 DEV commissioning readiness

The [2026-10-14 backend delivery V2 source candidate](MONEYBOWL_M4_BACKEND_DELIVERY_V2.md)
adds isolated artifact publication and a root API executor with one consolidated
review/install/activate/verify checklist. It supersedes the proposed host-build and
UID 993 private-state handoff for subsequent automation. Historical facts below
remain unchanged; V2 is not installed or live accepted.

Local implementation for independent review, 2026-10-14. No protected installation,
publication, initial PREPARE, API activation, owner/timer enablement or image operation
was performed. The existing [initial transition](MONEYBOWL_M4_INITIAL_API_TRANSITION.md)
and [environment promotion](MONEYBOWL_M4_ENVIRONMENT_PROMOTION.md) contracts remain mandatory.

## Baseline and root cause

Fetched `origin/develop` and separately queried the remote branch ref; both remain
`aea54c71b41a9b8a15f6854ea5e2279979c71329`. Canonical `develop` was clean. Work is
isolated on `codex/m4-dev-commissioning-readiness` in a separate worktree.

The supplied configuration diagnosis establishes an unchanged original interpolation
file, six absent M3B settings, a disabled regular-owner configuration, missing registry
and initial-transition sections, unapproved infrastructure placeholders, and missing
source/recovery bindings. These protected facts cannot be rechecked by the unprivileged
implementation session. The supplied private observation's SHA-256 was independently
verified as `9d4c726403e242742c8cac6f7c5368e5f11b5c821c86a89cb93ea49c5ea8eb2a`.
It remains an observation, never an independently approved infrastructure baseline.

`DockerOwner` already passes the configured `--env-file` to Compose. `Command` deliberately
does not inherit the operator's M3B shell variables. A complete new protected input
fixes that dependency without changing environment isolation or any live Compose layer.

Read-only inspection through the connected host's existing operator Docker access
confirmed the six service IDs, image IDs, runtime fingerprints and configuration hash
labels against that observation; five networks/volumes and the structural model also
match. API, ClamAV, webhook and receiver are healthy; Caddy and the adapter are running
without Engine healthchecks. The public API `/ready` returns the expected ready result.
Caddy retains its read-only `/srv/moneybowl-m4-receipts` bind. The retired dispatcher is
exited, PID zero, restart `no`; the concrete/template reconcilers are masked and inactive,
and the timer is disabled and inactive. No dispatcher operation was invoked.

The current six M3B relationships were independently reobserved:

| Setting | Binding to preserve |
| --- | --- |
| `M3B_WAKE_GID` | `985`, group `moneybowl-director-wake`, receiver supplemental group |
| `M3B_RECEIVER_IMAGE` | `moneybowl/m3b-receiver@sha256:400d88fd63e353b331519b66a494b3d5c22528b923948518822e96880965cff8` |
| `M3B_RECEIVER_SECRET_FILE` | `/etc/moneybowl-director/m3b-webhook-secret`, root:10001 `0440`, read-only at `/run/secrets/m3b_webhook_secret` |
| `M3B_RECEIVER_STATE_DIR` | `/var/lib/moneybowl-director-m3b/receiver`, 10001:10001 `0700`, writable at `/state` |
| `M3B_WAKE_SPOOL_DIR` | `/var/lib/moneybowl-director-m3b/wake-spool/pending`, root:985 `02770`, writable at `/spool` |
| `M3B_INGRESS_ADAPTER_IMAGE` | `moneybowl/m3b-ingress-adapter:fc58b2c964b8173483af8cf47c40251b4f686bc4`, local ID `sha256:932d0492f45f58fb4cb82707ce4b19d1a528eaa18c3dab932e11c61320d4b0c8` |

The adapter tag is retained. Its immutability/provenance requirement needs explicit
independent review; neither M3B image currently has image labels. No digest replacement,
image recreation or invented provenance is permitted. The historical API also has no
revision label. The existing approved candidate's local immutable binding and mandatory
source labels passed inspection, without a pull or remote credential access.

Real M3B metadata exposed a further controller compatibility blocker: Go templates
using `.Config.Labels` fail when Engine image metadata omits that map key. Both image
inspectors now use optional map indexing for Labels/Cmd (and User in the initial
inspector), consistent with the existing Entrypoint handling. Missing labels normalize
to an empty object. Candidate source labels and runtime assertions remain required;
label-free candidates fail provenance verification. No security exemption is added.

## Bounded utility and inputs

[commissioning_readiness.py](../../tools/deployment/commissioning_readiness.py) provides
INSPECT → STAGE → REVIEW → PUBLISH. It reuses the actual controller's validators and
Docker projections. It never calls `prepare`, `activate`, `verify`, build/push/pull,
Compose up/down, systemctl start/restart/enable, SQL or financial APIs.

The private request is `moneybowl-m4-commissioning-request-v1` with these fields:

| Field | Required contents |
| --- | --- |
| `kind` | `moneybowl-m4-commissioning-request-v1` |
| `config` | Complete initial-owner schema from [ingestion-owner.example.json](../../tools/deployment/ingestion-owner.example.json), with `commissioned=false`, `enabled=false`, `acceptance_required=true`; remove `initial_provenance` |
| `original_input` | Exact existing env path, independently reviewed `approval`, SHA-256 and device/inode/UID/GID/mode identity, root-private policy |
| `m3b` | Exactly the six settings above; missing, additional or different candidates fail closed |
| `preserved` | Exact protected binding per role in the utility's `HISTORY`; identities/digests and independent original-retention review references |

The config uses the new env path `/etc/moneybowl-deployment/runtime-inputs/ingestion-compose-m4.env`.
Publication targets the distinct `/etc/moneybowl-deployment/initial-mailback-dev.json`.
Bind all five ordered layers, two public artifacts, six services, structural model,
daemon, networks/volumes, exact stopped dispatcher and unit inventory. The relocated
M3B layer matches archived Git object `3eefd7cffec7fcd273250e014f03175e1d5c1c3b` at
`services/ingestion-support/compose.m3b.yaml`; this is infrastructure history, not API
build ancestry. Use the fixed candidate/source/component bindings already required
by the initial controller. The normal owner's configuration remains disabled.

Select existing root source/state/report/auth paths only after root inspection. The
private draft proposes the existing `/var/lib/moneybowl-m4-initial-dev` subpaths; none
is assumed ready. In addition to the controller's pins, set `git` and `git_sha256`.
The utility rejects application-owned source trees, symlinks, writable mirror files
and stale local `refs/heads/develop`. Git inspection uses a restricted environment,
disabled hooks/fsmonitor/credential helpers and read-only `ls-remote`; it never fetches,
clones or updates a mirror. Missing trusted mirror objects require separate provisioning.

GHCR requires the actual private package/repository approval, scoped verifier auth,
`https://ghcr.io/token`, service `ghcr.io`, and independently reviewed blob redirect
hosts. No credential is provisioned or emitted. Local image metadata does not replace
the controller's remote private OCI verification. Recovery must bind the exact archive,
record, unknown historical provenance (`git_commit=null`), retention and restoration
readiness. Existing Caddy journal/reconciliation and all three root recovery copies
are immutable preservation prerequisites. The original legacy recovery directory
is owned by UID 993 and is never read, modified or treated as root approval authority
by this utility; the previously reviewed root copies remain the controller's inputs.

The request's new-env binding may initially have null identity/digest/approval; STAGE
fills only observed identity/digest, leaving approval null. Other unresolved fields
remain null in the delivered private draft. Root inspection and independent review
must resolve them before the request is usable; never insert a fabricated approval.

## Transaction and authorization

Use a reviewed new sealed controller installation outside application Git. Preserve
`/opt/moneybowl-deployment/aea54c71b41a9b8a15f6854ea5e2279979c71329` unchanged.
The CLI checks installed code and real/effective root before any operation. The root
operator must separately provision a root-owned `0700` staging parent on the same
filesystem as both target parents, outside source/state/report/auth/approval/history
and deployment configuration directories. Each transaction gets a new directory.

1. **INSPECT** reads approved original-file bindings, checks the disabled owner and
   preserves all historical identities/digests. It reobserves current M3B images,
   mounts, group assignments, external policy/identity metadata and the Caddy receipt
   mount. It reports proposed digests and exact added variable names. It writes nothing
   and cannot compute credential-resolved hashes without staging the new input.
2. **STAGE** creates only inactive artifacts in the new transaction directory. The
   original env bytes are retained as an exact prefix; six literal variables are
   appended. Existing declarations (including duplicate/export/bare forms) fail.
   Files are exclusively created root:root `0400`, with no symlinks/hardlinks, trusted
   ancestry, ACL rejection, descriptor/inode/content rechecks and file/directory fsync.
   `00-intent.json` precedes writes; `10-staged.json` seals the staged identity/digest
   and inactive draft. A failure adds `99-unknown.json` if possible. An incomplete
   directory, UNKNOWN outcome or existing transaction cannot be retried or repaired.
3. **REVIEW** requires a separately authored root-controlled baseline outside staging,
   with its exact raw SHA-256. It permits approval references and `enabled=true` only;
   every other staged binding must match. It checks exact original-byte preservation,
   recovery/history, and absence of retained initial-transition state/ledger artifacts.
   It executes read-only preflight against the staged env using the actual
   `InitialDockerOwner` restricted `Command` environment. All six effective hashes must
   equal independently approved hashes and actual container labels. Container/runtime
   identities, source bytes/history/head, health, resources, external-secret policies
   and mounts, registry/candidate, recovery and retirement checks remain mandatory.
   It returns exact create-only targets, digests, identity, preflight fingerprint and
   preservation conditions. Review writes nothing and does not authorize publication.
4. **PUBLISH** remains unavailable without a separate root-controlled expiring approval
   in the controller's `approval_root`. Under the existing deployment lock it repeats
   REVIEW, checks its exact approved fingerprint, then durably records publication
   intent. A same-filesystem link/unlink transfer retains the approved environment
   inode; config creation is exclusive and fsynced. It rechecks inputs/history and
   live preflight, then records `PUBLISHED_NOT_PREPARED`. It never overwrites or rolls
   back originals, existing configurations, approval records or historical journals.

The independently authored baseline schema is:

```json
{
  "kind": "moneybowl-m4-commissioning-baseline-v1",
  "stage_sha256": "EXACT_REVIEWED_STAGE_CANONICAL_DIGEST",
  "owner_review": "INDEPENDENT_BASELINE_REVIEW_REFERENCE",
  "config": {},
  "ingress_tag_review": {
    "reference": "moneybowl/m3b-ingress-adapter:fc58b2c964b8173483af8cf47c40251b4f686bc4",
    "image_id": "sha256:932d0492f45f58fb4cb82707ce4b19d1a528eaa18c3dab932e11c61320d4b0c8",
    "owner_review": "INDEPENDENT_EXISTING_TAG_AND_PROVENANCE_DISPOSITION",
    "preserve_without_pull": true
  },
  "recovery_review": {
    "offhost_retention_review": "INDEPENDENT_RETENTION_REFERENCE",
    "restoration_readiness_review": "INDEPENDENT_RESTORE_READINESS_REFERENCE",
    "rollback_requires_separate_authorization": true
  }
}
```

`config` is the entire staged config, with genuine independent approval references,
`enabled=true`, `acceptance_required=true`, `commissioned=false`. The new env binding
uses the staged device/inode/UID/GID/mode and digest at its final pathname. The two
external secrets require existing exact root-controlled policy records, not newly
generated records. The utility has no approval-generation command.

Publication approval contains exactly `kind=moneybowl-m4-commissioning-publication-v1`,
`environment=dev`, `project_ref=rskryngwzyuzmiwtriyy`, `review_sha256` (canonical digest
of REVIEW output), `baseline_sha256` (raw file digest), `stage_sha256`, `owner_review`,
a 64-hex `nonce`, numeric `expires_at` no more than one hour ahead, ordered `targets`
equal to the two paths above, and `api_activation_authorized=false`. Root filesystem
authority establishes authorization; an observed digest or human string alone cannot.
One publication intent consumes the transaction; approvals cannot cause a replay.

For isolated Python, the authorized root launcher imports only the sealed directory:

```sh
/usr/bin/python3 -I -B -c 'import sys; sys.path.insert(0, "/opt/moneybowl-deployment/REVIEWED_COMMIT/tools/deployment"); from commissioning_readiness import main; raise SystemExit(main())' inspect --request /protected/request.json
```

The same entrypoint supports `stage --request ... --stage ...`, `review --stage ...
--baseline ... --baseline-sha256 ...`, and, only after independent authorization,
`publish` with the REVIEW arguments plus `--approval ...`. These are interfaces for
the tested utility, not authorization to execute a protected operation in this task.

## Recovery boundaries and validation

A partial stage remains inactive. A publication crash may retain only the new env,
both final artifacts, or two links to its inode; the durable intent/incomplete directory
is authoritative. Every retry fails closed. Inspect these files and their exact
identities/digests through the separate root recovery channel. Do not delete a journal,
unlink a partially published file or overwrite a binding to make a check pass. This
implementation does not provide automatic repair. Preserve original protected env,
disabled owner and all historical recovery/Caddy records throughout reconciliation.

After separately authorized successful publication, a new independent operator
decision may invoke the existing initial PREPARE, subject to its remaining security
prerequisites. ACTIVATE still requires its own expiring, plan-bound root approval.
Automatic UID 993 deployment remains blocked on the separately commissioned constrained
Docker broker. No Docker-group/sudo grant, scheduler change or claimed full M4 success
is part of this work.

Regression coverage is in [test_commissioning_readiness.py](../../tools/deployment/test_commissioning_readiness.py).
Validation uses complete deployment/commissioning/commit-validator suites, Python
syntax compilation, documentation links, commit format and `git diff --check`.
All tests use disposable synthetic files and injected Engine/OCI transports; none
reads live credentials or mutates real containers. Root validation of protected input
bytes/identities/policies and all six effective hashes remains unexecuted here.

Latest complete local results (2026-10-14):

| Command | Result |
| --- | --- |
| `python3 -m unittest discover -s tools/deployment` | 402 tests, PASS, zero failures/errors |
| `python3 -m unittest discover -s tools/commissioning` | 34 tests, PASS, zero failures/errors |
| `python3 -m unittest discover -s .github/scripts -p test_validate_commits.py` | 5 tests, PASS, zero failures/errors |
| Python AST/syntax compilation of all six changed Python files | PASS |
| `.github/scripts/validate_docs.py`, Conventional Commit title, `git diff --check` | PASS |

Read-only live projections additionally passed the M3B relationships helper and both
updated image inspectors. INSPECT/STAGE/REVIEW/PUBLISH CLI root operations and initial
PREPARE were not executed on the host. The private draft/proposal artifacts contain
metadata and unresolved approval fields, with no protected env or credential bytes.
