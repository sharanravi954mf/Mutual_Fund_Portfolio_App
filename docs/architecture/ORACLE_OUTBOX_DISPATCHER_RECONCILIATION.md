# Oracle outbox dispatcher reconciliation

The new reconciler makes future develop changes update the dispatcher automatically
through the existing GitHub webhook delivery path, with a periodic fallback.
It builds a specific commit, validates it, and replaces only the dispatcher.
It never manufactures a queued operation or calls NSE as a deployment smoke test.

## Current status

| Boundary | Status for this local candidate |
| --- | --- |
| SOURCE IMPLEMENTED | Yes; reconciler, tests, isolated Compose manifest, units, sudo rule, webhook consumer and bootstrap script |
| BOOTSTRAP REQUIRED | Yes; new service/timer, reviewed launcher/config installation and existing webhook service drop-in |
| HOST AUTOMATION COMMISSIONED | No; nothing installed, enabled, restarted or deployed by this task |
| FUTURE MERGE AUTO-DEPLOY READY | No on the current host; designed to become ready after the commissioning steps below |

No claim of hosted rollout, UAT success or active post-merge automation is made.

## Existing mechanisms inspected read-only

On 2026-10-02:

- `moneybowl-director-dev.duckdns.org/github/webhook` routes through Caddy to the
  existing GitHub receiver, which verifies HMAC, repository and `refs/heads/develop`,
  and writes small verified events containing `head_sha` into
  `/home/ubuntu/moneybowl-runtime/github-webhook-container/spool`.
- `moneybowl-github-webhook-dispatch.path` triggers the existing dispatch service.
  Its current `process-spool.sh` reconciles Flutter once for each event batch.
- `moneybowl-flutter-web-reconcile.service/timer` runs the same Flutter deployer
  every 15 minutes. It archives exact develop, builds and checks it, and checks
  develop again before activation. It does not own dispatcher images.
- Director's `base_reconciler.py` owns clean, bounded fast-forward of the canonical
  repository. The separate `/github/director-ci` M3B path is not a deployment hook.
  Neither is repurposed as a second deployment framework.
- Live Compose project is `moneybowl-ingestion-support`, with source Compose files
  under `/home/ubuntu/moneybowl/services/ingestion-support`. Dispatcher container:
  `moneybowl-ingestion-support-outbox-dispatcher-1`, healthy. Its prior manual
  recreate label referenced a temporary env file, so that label is not reusable.
- Durable `.env` at that source directory is root:root 0600. Only presence of
  `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `NSE_WORKER_TOKEN` was checked; all
  were present. Values were not printed. Reconciliation must still compare these
  values to the live configuration in memory and stop if they differ.
- Compose 5.5.0 and sudo 1.9.15p5 are installed. Live dispatcher: UID/GID10002,
  read-only root, ALL capabilities dropped, no-new-privileges, CPU0.10, 128MiB,
  PID32, `/tmp` tmpfs8MiB, restart unless-stopped and only the private
  `moneybowl-ingestion-support_ingestion_internal` bridge, with no exposed ports.
- Live operational settings: dry-run `false`, poll `60`, retry-delay `30`, batch
  `10`, HTTP timeout `45`, feed-failure backoff `30`, max feed failures `12`.
  The source's historical poll default is 5; blindly using defaults would drift.

No receiver, systemd, Caddy, Docker, M3B, Supabase, frontend gate or secret was
modified during this inspection.

## Architecture and activation safety

The existing verified spool remains the sole webhook entry point. A replacement
consumer invokes a fixed SHA-parameterized dispatcher systemd service, then
attempts the existing Flutter reconciliation independently. No additional webhook
registration, HTTP receiver, webhook secret or container socket mount is added.
The existing spool lock and delivery directories are retained. Stale events are
successful skips; failed delivery batches move to the existing failed directory.
The dispatcher timer independently reconciles current develop every 15 minutes.

Dispatcher launchers and config are installed once under
`/home/ubuntu/moneybowl-runtime/outbox-dispatcher`. The new deployment service runs
as root solely to read the unchanged root-owned env and manage Docker. Its Git
commands run as ubuntu through `runuser`; no new Git credentials are provisioned.
The webhook consumer remains ubuntu. A sudoers **argument regex** permits only
`systemctl start --wait moneybowl-outbox-dispatcher-reconcile@<40 lowercase hex>.service`.
It cannot choose another unit, executable, repository or configuration file.
The periodic service and webhook template use the same root-owned `deploy.lock`.
Container execution remains UID/GID10002; neither tests nor runtime receive root
privileges from the deployment service.

A reconciliation performs these ordered steps:

1. Acquire the deployment lock. Fetch the explicit develop ref and resolve a
   full 40-character commit SHA. If a webhook requested another SHA, skip it.
2. Require a healthy known-good existing dispatcher, inspect only in memory,
   retain its image ID, route set, operational settings and required secret values.
   Verify existing hardening before attempting a change.
3. Archive the exact commit into a private temporary source directory. Never
   checkout, reset or edit the canonical repository.
4. Parse candidate `routes.json` with duplicate-key rejection. Match the closed
   source-controlled `deploy/routes-contract.json`; enforce NSE route/worker names
   and `NSE_WORKER_TOKEN`. Require every currently live route to survive unchanged.
   Future reviewed route additions update source policy; they do not require a
   manual image rebuild or launcher reinstall.
5. Render the dispatcher-only Compose manifest with the existing secret env file.
   Override its non-secret operational settings with the verified live values.
   Capture expanded output in memory; never print it. Check environment equality,
   service isolation, exact image binding, hardening, limits, health command, network
   and absence of ports/volumes/dependencies/command overrides before activation.
6. Build the Docker test stage and run pytest under UID10002 with network none,
   read-only root, dropped capabilities and tmpfs. No production secrets enter
   the test image/container. Build the runtime image tagged
   `moneybowl-outbox-dispatcher:<SHA>` and labeled
   `org.opencontainers.image.revision=<SHA>`; verify image user and revision.
7. Fetch develop again immediately before activation. If it moved, leave the
   current container unchanged. Also reject live configuration changes made by
   another operator during the build. The next webhook/timer handles the new SHA.
8. Activate by **immutable image ID**, using the existing Compose project and
   single-service manifest:

   ```text
   docker compose ... up --detach --no-deps --no-build --pull never --force-recreate outbox-dispatcher
   ```

   There is no `--remove-orphans`, whole-project `down`, dependency recreation or
   action on API, Caddy, ClamAV, webhook, Director or M3B containers.
9. Poll health for up to 90 seconds, then verify actual image ID, SHA label,
   live route bytes parsed as JSON, hardening, network, health, required secret
   presence/equality and unchanged operational settings. Only then write an atomic
   secret-free `state/deployment.json` receipt. Already-current reconciliation
   performs the same readback and refreshes that receipt without recreating.
10. On activation/health/readback failure, recreate only the dispatcher with the
    prior immutable image ID and preserved environment/settings; verify prior
    routes and health. No success receipt is written. If restoration fails,
    emit `rollback_failed_operator_required` and stop, rather than hiding failure.

The live container continues running while images build. Compose replacement
itself is not zero downtime; rollback can require a short second recreate. Images
are not pruned automatically, preserving rollback availability. Subprocess stdout,
stderr and exception details are captured and never relayed, because Compose and
inspect can contain secrets. Only fixed safe codes, SHA and a secret-free receipt
are reported. No env file is sourced as executable shell or rewritten.

Normal already-authorized queued operations may resume when the dispatcher starts.
Deployment tests never enqueue a synthetic event and never call an NSE worker.

## One-time commissioning procedure — not executed here

This must be separately authorized. Use the reviewed merged source after Supabase
migrations/workers are present in DEV. Do not enable a browser gate as a side effect.
The automation intentionally refuses an absent/unhealthy prior dispatcher; initial
infrastructure recovery is an operator task, not an automatic guess.

1. Verify a healthy current dispatcher and read-only operational settings against
   the record above. Confirm that the existing durable env is the authoritative
   one. Do not rotate keys, copy them into a new env, print `docker inspect`, run
   `docker compose config` to a terminal, or change root:root0600 permissions.
   The reconciler compares secret values without exposing them and stops on drift.
2. Prepare a **non-secret** config JSON from `deploy/config.example.json`, containing
   canonical repo, existing `.env` path and private state directory. Verify installed
   sudo supports regex arguments (1.9.10+), and validate the supplied sudoers file.
3. Run the source-controlled bootstrap from the reviewed commit:

   ```bash
   sudo bash services/outbox-dispatcher/deploy/bootstrap.sh /absolute/reviewed/config.json
   ```

   This installs root-owned launchers/config, the service/template/timer and narrow
   sudo rule. It stages the webhook override in the runtime directory, then reloads
   systemd. It does **not** enable/start the timer, activate a container, or wire the
   existing webhook to the new consumer. It does not modify the secret env.
4. Commission one deployment through the installed service:

   ```bash
   sudo systemctl start --wait moneybowl-outbox-dispatcher-reconcile.service
   sudo systemctl status moneybowl-outbox-dispatcher-reconcile.service
   sudo cat /home/ubuntu/moneybowl-runtime/outbox-dispatcher/state/deployment.json
   ```

   Read only the safe receipt/codes. Confirm exact current develop, image identity,
   health, all nine current route mappings and preserved settings/hardening. Do not
   use a provider call as a health test. If the env differs, stop for configuration
   review; the reconciler will not rewrite it to make deployment succeed.
5. After the healthy service result, wire the existing webhook consumer and enable
   periodic reconciliation:

   ```bash
   sudo install -d -m 0755 /etc/systemd/system/moneybowl-github-webhook-dispatch.service.d
   sudo install -o root -g root -m 0644 /home/ubuntu/moneybowl-runtime/outbox-dispatcher/webhook-dispatch.override.conf /etc/systemd/system/moneybowl-github-webhook-dispatch.service.d/outbox.conf
   sudo systemctl daemon-reload
   sudo systemctl enable --now moneybowl-outbox-dispatcher-reconcile.timer
   ```

   Existing webhook path/receiver and Flutter timer remain in place. Do not manually
   start the spool consumer with forged provider events. A subsequent ordinary
   develop delivery and timer readback establish operational readiness.
6. Record the four status fields above with commissioning time, exact deployed SHA,
   safe health/readback result, timer enabled status and verified webhook delivery.
   Only then mark FUTURE MERGE AUTO-DEPLOY READY as yes.

Future develop route/dispatcher updates need no manual Docker rebuild after this
bootstrap. The installed launcher is deliberately not self-modifying; a reviewed
change to its deployment safety algorithm requires a separate launcher update.
It still deploys later application/source/route changes from their exact SHAs.
Operational-setting changes likewise require explicit reviewed commissioning;
this version always preserves the current live values.

## Rollback and recovery

Automatic image rollback is part of activation. If it fails, retain both images
and the safe failure code for operator recovery; never fall back to `latest` or
restart unrelated services. If automation itself must be disabled during separate
commissioning, stop/disable only its timer, remove its webhook drop-in, and reload
systemd; the prior Flutter spool processor then resumes under its unchanged base
unit. Keep the root env and healthy dispatcher untouched. Do not remove container
or image state merely to clear a failed deployment receipt.

## Local verification

The 38 new reconciliation tests simulate stale events, exact-SHA snapshot/build,
branch advancement, route policy/drop checks, preserved settings, secret equality,
pre-activation hardening failures, image/label/route/health drift, lock serialization,
rollback and secret-safe errors. Together with 16 existing dispatcher tests, 54 pass.
The test/runtime Docker stages build locally; the test image runs pytest network-none.
Synthetic Compose rendering exercises the actual installed CLI without a daemon
call and caught/covered string-valued `mem_limit`. Shell and sudoers syntax pass.
No live systemd activation, rollback or webhook commissioning was tested; those
are explicitly the outstanding commissioning boundary.

Systemd unit-template verification also passed. It reported pre-existing executable-mode
warnings for Oracle unified-monitoring units and invalid-URL warnings in the existing
Director Slack unit. No unit was installed or modified to silence those warnings.
