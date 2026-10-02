#!/usr/bin/env python3
"""Exact-develop dispatcher reconciliation. No NSE smoke calls; no secret output.

Installed launcher and config are reviewed bootstrap artifacts, never self-updated.
Source, tests, routes and Compose manifest come from an isolated exact-SHA archive.
"""
import argparse
import fcntl
import io
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tarfile
import tempfile
import time

SHA = re.compile(r"[0-9a-f]{40}\Z")
PROJECT = "moneybowl-ingestion-support"
SERVICE = "outbox-dispatcher"
CONTAINER = PROJECT + "-" + SERVICE + "-1"
NETWORK = PROJECT + "_ingestion_internal"
SECRETS = ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "NSE_WORKER_TOKEN")
SETTINGS = (
    "OUTBOX_DISPATCH_DRY_RUN", "OUTBOX_POLL_INTERVAL_SECONDS",
    "OUTBOX_RETRY_DELAY_SECONDS", "OUTBOX_BATCH_SIZE", "OUTBOX_HTTP_TIMEOUT_SECONDS",
    "OUTBOX_FEED_FAILURE_BACKOFF_SECONDS", "OUTBOX_MAX_CONSECUTIVE_FEED_FAILURES",
)
# Baseline route floor. Candidate validator additionally checks its closed route map.
BASE_ROUTES = {
    "ucc_registration": "nse-ucc-registration-worker",
    "ucc_verification": "nse-ucc-reconciliation-worker",
    "order_status": "nse-order-status-worker",
    "prov_orders": "nse-prov-orders-worker",
    "client_readiness": "nse-client-readiness-worker",
    "order_funding": "nse-order-funding-worker",
    "settlement_redemption": "nse-settlement-redemption-worker",
    "sip_xsip_reports": "nse-sip-xsip-reports-worker",
    "stp_swp_reports": "nse-stp-swp-reports-worker",
}
EXPECTED_ROUTES = {"integration.nse." + k + "_requested":
                   {"worker_slug": v, "token_env": "NSE_WORKER_TOKEN"}
                   for k, v in BASE_ROUTES.items()}


class ReconcileError(Exception):
    """Messages are fixed safe codes only; subprocess errors are never relayed."""


def require(condition, code):
    if not condition:
        raise ReconcileError(code)


def unique_object(pairs):
    result = {}
    for k, v in pairs:
        require(k not in result, "duplicate_json_key")
        result[k] = v
    return result


def json_value(raw):
    try:
        return json.loads(raw, object_pairs_hook=unique_object)
    except (ValueError, TypeError):
        raise ReconcileError("invalid_json") from None


def validate_routes(raw, previous=None, expected=None):
    routes = json_value(raw)
    expected = EXPECTED_ROUTES if expected is None else expected
    require(isinstance(expected, dict) and bool(expected), "route_contract_invalid")
    for event, route in expected.items():
        require(isinstance(event, str) and re.fullmatch(r"integration\.nse\.[a-z_]+_requested", event) and
                isinstance(route, dict) and set(route) == {"worker_slug", "token_env"} and
                isinstance(route["worker_slug"], str) and re.fullmatch(r"nse-[a-z-]+-worker", route["worker_slug"]) and
                route["token_env"] == "NSE_WORKER_TOKEN", "route_contract_invalid")
    require(isinstance(routes, dict) and bool(routes), "routes_invalid")
    for event, route in routes.items():
        require(event in expected and route == expected[event], "route_not_allowed")
    require(routes == expected, "required_route_missing")
    if previous is not None:
        require(all(routes.get(k) == v for k, v in previous.items()), "live_route_dropped")
    require(all(routes.get(k) == v for k, v in EXPECTED_ROUTES.items()), "baseline_route_dropped")
    return routes


def env_dict(container):
    return dict(item.split("=", 1) for item in container["Config"]["Env"])


def check_hardening(container):
    c, h = container["Config"], container["HostConfig"]
    require(c["User"] == "10002:10002" and h["ReadonlyRootfs"] is True, "identity_or_readonly_changed")
    require(h["CapDrop"] == ["ALL"] and not h.get("CapAdd") and not h.get("Privileged"), "capabilities_changed")
    require(h["SecurityOpt"] == ["no-new-privileges:true"], "security_options_changed")
    require(h["NanoCpus"] == 100000000 and h["Memory"] == 134217728 and h["PidsLimit"] == 32, "limits_changed")
    require(h["RestartPolicy"]["Name"] == "unless-stopped", "restart_changed")
    require(h["Tmpfs"] == {"/tmp": "size=8m,mode=1777"}, "tmpfs_changed")
    require(not h.get("PortBindings") and not h.get("Binds") and not h.get("Devices"), "unexpected_exposure")
    require(set(container["NetworkSettings"]["Networks"]) == {NETWORK}, "network_changed")
    require(c["Labels"].get("com.docker.compose.project") == PROJECT and
            c["Labels"].get("com.docker.compose.service") == SERVICE, "compose_identity_changed")
    e = env_dict(container)
    require(all(e.get(k) for k in SECRETS), "required_secret_missing")
    require(all(e.get(k) for k in SETTINGS), "setting_missing")
    require(e.get("OUTBOX_ROUTES_FILE") == "/app/routes.json" and
            e.get("OUTBOX_HEARTBEAT_FILE") == "/tmp/dispatcher-heartbeat", "runtime_paths_changed")


def check_compose(config, original_env):
    require(set(config["services"]) == {SERVICE}, "unrelated_service_in_manifest")
    s = config["services"][SERVICE]
    require(set(s) <= {"image", "user", "restart", "read_only", "cap_drop", "security_opt",
            "cpus", "mem_limit", "pids_limit", "tmpfs", "stop_grace_period", "environment",
            "healthcheck", "networks", "command", "entrypoint"}, "unexpected_service_option")
    require(s.get("stop_grace_period") == "10s", "stop_grace_period_changed")
    require(s.get("healthcheck") == {"test": ["CMD", "python", "-c",
            "import os,sys,time; p='/tmp/dispatcher-heartbeat'; sys.exit(0 if os.path.exists(p) and time.time()-os.path.getmtime(p)<120 else 1)"],
            "interval": "15s", "timeout": "3s", "retries": 4, "start_period": "15s"}, "healthcheck_changed")
    require(s.get("user") == "10002:10002" and s.get("read_only") is True and
            s.get("cap_drop") == ["ALL"] and not s.get("cap_add") and not s.get("privileged"), "compose_hardening_invalid")
    require(s.get("security_opt") == ["no-new-privileges:true"] and
            float(s.get("cpus", 0)) == 0.1 and str(s.get("mem_limit")) == "134217728" and
            s.get("pids_limit") == 32 and s.get("restart") == "unless-stopped", "compose_limits_invalid")
    require(s.get("tmpfs") == ["/tmp:size=8m,mode=1777"] and not s.get("volumes") and
            not s.get("ports") and not s.get("devices") and not s.get("network_mode") and
            not s.get("pid") and not s.get("ipc") and not s.get("depends_on") and
            not s.get("build") and not s.get("command") and not s.get("entrypoint") and not s.get("volumes_from"), "compose_exposure_invalid")
    require(set(s.get("networks", {})) == {"ingestion_internal"} and
            config["networks"]["ingestion_internal"].get("external") is True and
            config["networks"]["ingestion_internal"].get("name") == NETWORK, "compose_network_invalid")
    require(s.get("healthcheck", {}).get("test") == ["CMD", "python", "-c",
            "import os,sys,time; p='/tmp/dispatcher-heartbeat'; sys.exit(0 if os.path.exists(p) and time.time()-os.path.getmtime(p)<120 else 1)"], "compose_health_invalid")
    require(all(s["environment"].get(k) == original_env.get(k) for k in (*SECRETS, *SETTINGS)), "runtime_env_mismatch")
    require(set(s["environment"]) == set((*SECRETS, *SETTINGS, "OUTBOX_ROUTES_FILE", "OUTBOX_HEARTBEAT_FILE")), "unexpected_runtime_env")


class Runtime:
    def __init__(self, repo, env_file, state):
        self.repo, self.env_file, self.state = Path(repo), Path(env_file), Path(state)

    def run(self, args, *, env=None, timeout=120, binary=False):
        # Never print commands, stdout, stderr, environment or exception objects.
        try:
            result = subprocess.run(args, capture_output=True, timeout=timeout,
                                    env=env, check=False)
        except (OSError, subprocess.TimeoutExpired):
            raise ReconcileError("command_unavailable_or_timeout") from None
        require(result.returncode == 0, "command_failed")
        return result.stdout if binary else result.stdout.decode("utf-8")

    def git(self, *args, **kwargs):
        # Root deployment service never needs Git credentials of its own.
        prefix = ["runuser", "-u", "ubuntu", "--"] if os.geteuid() == 0 else []
        return self.run([*prefix, "git", "-C", str(self.repo), *args], **kwargs)

    def latest(self):
        self.git("fetch", "origin", "+refs/heads/develop:refs/remotes/origin/develop", "--quiet")
        sha = self.git("rev-parse", "--verify", "refs/remotes/origin/develop^{commit}").strip()
        require(SHA.fullmatch(sha), "invalid_develop_sha")
        return sha

    def inspect(self):
        return json_value(self.run(["docker", "inspect", CONTAINER]))[0]

    def live_routes(self):
        return json_value(self.run(["docker", "exec", CONTAINER, "cat", "/app/routes.json"]))

    def snapshot(self, sha, directory):
        data = self.git("archive", sha, binary=True)
        with tarfile.open(fileobj=io.BytesIO(data)) as archive:
            archive.extractall(directory, filter="data")
        return Path(directory) / "services/outbox-dispatcher"

    def compose(self, source, image, settings, *action):
        # Existing secret file is read by Compose; never source it as shell code.
        # Override non-secret settings with the verified current runtime values.
        env = {k: v for k, v in os.environ.items() if k not in SECRETS and not k.startswith("OUTBOX_")}
        env.update(settings, DISPATCHER_IMAGE=image)
        return self.run(["docker", "compose", "--project-name", PROJECT,
                         "--env-file", str(self.env_file), "-f", str(source / "deploy/compose.yaml"),
                         *action], env=env)

    def activate(self, source, image, settings):
        self.compose(source, image, settings, "up", "--detach", "--no-deps", "--no-build",
                     "--pull", "never", "--force-recreate", SERVICE)

    def verify(self, image_id, sha, routes, original_env, *, rollback=False):
        last = None
        for _ in range(45):
            last = self.inspect()
            if last["State"].get("Health", {}).get("Status") == "healthy":
                break
            time.sleep(2)
        require(last["State"].get("Health", {}).get("Status") == "healthy", "health_failed")
        check_hardening(last)
        require(last["Image"] == image_id, "image_identity_mismatch")
        if not rollback:
            require(last["Config"]["Labels"].get("org.opencontainers.image.revision") == sha, "deployed_sha_mismatch")
        current = env_dict(last)
        require(all(current.get(k) == original_env.get(k) for k in (*SETTINGS, *SECRETS)), "runtime_configuration_changed")
        require(self.live_routes() == routes, "live_routes_mismatch")
        return last

    def receipt(self, sha, image_id, routes):
        temp = self.state / ".deployment.json.tmp"
        temp.write_text(json.dumps({"sha": sha, "image_id": image_id, "routes": sorted(routes),
                                    "health": "healthy", "secret_presence": True}) + "\n")
        temp.replace(self.state / "deployment.json")

    def deploy(self, requested=None):
        require(requested is None or SHA.fullmatch(requested), "invalid_requested_sha")
        sha = self.latest()
        if requested is not None and requested != sha:
            return "STALE_EVENT_SKIPPED", sha
        previous = self.inspect()
        check_hardening(previous)
        require(previous["State"].get("Health", {}).get("Status") == "healthy", "known_good_container_required")
        previous_routes = self.live_routes()
        original_env = env_dict(previous)
        settings = {k: original_env[k] for k in SETTINGS}
        with tempfile.TemporaryDirectory(prefix="build-", dir=self.state) as directory:
            source = self.snapshot(sha, directory)
            # Candidate's own source-controlled closed map can add routes in later batches.
            # Installed launcher still enforces the retained live-route subset.
            expected = json_value((source / "deploy/routes-contract.json").read_text())
            routes = validate_routes((source / "routes.json").read_text(), previous_routes, expected)
            image = "moneybowl-outbox-dispatcher:" + sha
            config = json_value(self.compose(source, image, settings, "config", "--format", "json"))
            check_compose(config, original_env)
            require(config["services"][SERVICE].get("image") == image, "compose_image_not_bound")
            if previous["Config"]["Labels"].get("org.opencontainers.image.revision") == sha:
                self.verify(previous["Image"], sha, routes, original_env)
                self.receipt(sha, previous["Image"], routes)
                return "ALREADY_CURRENT", sha
            # Tests are built without production secrets, then run network-isolated.
            self.run(["docker", "build", "--target", "test", "-t", image + "-test", str(source)], timeout=600)
            self.run(["docker", "run", "--rm", "--network", "none", "--read-only", "--cap-drop", "ALL",
                      "--security-opt", "no-new-privileges", "--tmpfs", "/tmp:rw,size=32m", image + "-test"], timeout=180)
            self.run(["docker", "build", "--target", "runtime", "--label", "org.opencontainers.image.revision=" + sha,
                      "-t", image, str(source)], timeout=600)
            built = json_value(self.run(["docker", "image", "inspect", image]))[0]
            require(built["Config"]["User"] == "10002:10002" and
                    built["Config"]["Labels"].get("org.opencontainers.image.revision") == sha, "built_image_invalid")
            if self.latest() != sha:
                return "DEVELOP_MOVED_SKIPPED", sha
            current = self.inspect()
            require(current["Image"] == previous["Image"] and env_dict(current) == original_env, "live_runtime_changed_during_build")
            # Freeze rollback manifest before activation; no secret bytes are written.
            rollback_source = Path(directory) / "rollback"
            (rollback_source / "deploy").mkdir(parents=True)
            (rollback_source / "deploy/compose.yaml").write_text((source / "deploy/compose.yaml").read_text())
            try:
                # Immutable image ID also prevents a concurrently retagged image from activation.
                self.activate(source, built["Id"], settings)
                self.verify(built["Id"], sha, routes, original_env)
            except Exception:
                try:
                    self.activate(rollback_source, previous["Image"], settings)
                    self.verify(previous["Image"], None, previous_routes, original_env, rollback=True)
                except Exception:
                    raise ReconcileError("rollback_failed_operator_required") from None
                raise ReconcileError("activation_failed_prior_image_restored") from None
            self.receipt(sha, built["Id"], routes)
            return "DEPLOYED", sha


def reconcile_locked(runtime, requested=None):
    runtime.state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (runtime.state / "deploy.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return runtime.deploy(requested)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config")
    parser.add_argument("--requested-sha")
    parser.add_argument("--validate-routes")
    args = parser.parse_args()
    if args.validate_routes:
        validate_routes(Path(args.validate_routes).read_text())
        print("ROUTES_VALID")
        return
    require(args.config is not None, "config_required")
    cfg = json_value(Path(args.config).read_text())
    require(set(cfg) == {"repo", "env_file", "state"}, "config_fields_invalid")
    env_path = Path(cfg["env_file"])
    info = env_path.stat()
    require(not env_path.is_symlink() and info.st_uid == 0 and
            stat.S_ISREG(info.st_mode) and not info.st_mode & 0o027, "root_owned_private_env_required")
    result, sha = reconcile_locked(Runtime(**cfg), args.requested_sha)
    print(result + " sha=" + sha)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except ReconcileError as error:
        print("DISPATCHER_RECONCILE_FAILED=" + str(error))
        raise SystemExit(1)
    except Exception:
        print("DISPATCHER_RECONCILE_FAILED=unexpected_error")
        raise SystemExit(1)
