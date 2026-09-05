from __future__ import annotations

import json
import os
import re
import signal
import sys
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from types import FrameType
from typing import Mapping
from urllib.parse import urlparse

import httpx


_EVENT_TYPE_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_.-]{0,99}$")
_WORKER_SLUG_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,62}$")
_TOKEN_ENV_PATTERN = re.compile(r"^[A-Z][A-Z0-9_]{2,99}$")
_ALLOWED_EVENT_STATUSES = {"pending", "failed", "processing"}
_MAX_FEED_BYTES = 65_536


class DispatcherConfigError(ValueError):
    pass


class DispatcherProtocolError(RuntimeError):
    pass


@dataclass(frozen=True)
class Route:
    event_type: str
    worker_slug: str
    token_env: str
    token: str


@dataclass(frozen=True)
class Candidate:
    event_outbox_id: str
    event_type: str
    event_status: str
    retry_count: int


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    service_role_key: str
    dry_run: bool
    poll_interval_seconds: float
    retry_delay_seconds: int
    batch_size: int
    http_timeout_seconds: float
    failure_backoff_seconds: float
    max_consecutive_feed_failures: int
    routes_file: Path
    heartbeat_file: Path

    @classmethod
    def from_env(cls, environ: Mapping[str, str] | None = None) -> "Settings":
        env = os.environ if environ is None else environ
        return cls(
            supabase_url=_trusted_origin(_required(env, "SUPABASE_URL")),
            service_role_key=_secret(env, "SUPABASE_SERVICE_ROLE_KEY"),
            dry_run=_boolean(env, "OUTBOX_DISPATCH_DRY_RUN", True),
            poll_interval_seconds=_bounded_float(
                env, "OUTBOX_POLL_INTERVAL_SECONDS", 5.0, 1.0, 60.0
            ),
            retry_delay_seconds=_bounded_int(
                env, "OUTBOX_RETRY_DELAY_SECONDS", 30, 0, 3600
            ),
            batch_size=_bounded_int(env, "OUTBOX_BATCH_SIZE", 10, 1, 50),
            http_timeout_seconds=_bounded_float(
                env, "OUTBOX_HTTP_TIMEOUT_SECONDS", 45.0, 5.0, 120.0
            ),
            failure_backoff_seconds=_bounded_float(
                env, "OUTBOX_FEED_FAILURE_BACKOFF_SECONDS", 30.0, 1.0, 300.0
            ),
            max_consecutive_feed_failures=_bounded_int(
                env, "OUTBOX_MAX_CONSECUTIVE_FEED_FAILURES", 12, 1, 100
            ),
            routes_file=Path(env.get("OUTBOX_ROUTES_FILE", "/app/routes.json")),
            heartbeat_file=Path(
                env.get("OUTBOX_HEARTBEAT_FILE", "/tmp/dispatcher-heartbeat")
            ),
        )


def _required(env: Mapping[str, str], name: str) -> str:
    value = env.get(name, "").strip()
    if not value:
        raise DispatcherConfigError(f"{name}_required")
    return value


def _secret(env: Mapping[str, str], name: str) -> str:
    value = _required(env, name)
    if len(value) < 32:
        raise DispatcherConfigError(f"{name}_too_short")
    return value


def _trusted_origin(value: str) -> str:
    parsed = urlparse(value)
    is_local = parsed.hostname in {"localhost", "127.0.0.1", "::1"}
    if (
        not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
        or parsed.path not in {"", "/"}
    ):
        raise DispatcherConfigError("SUPABASE_URL_invalid")
    if parsed.scheme != "https" and not (parsed.scheme == "http" and is_local):
        raise DispatcherConfigError("SUPABASE_URL_requires_https")
    return value.rstrip("/")


def _boolean(
    env: Mapping[str, str],
    name: str,
    default: bool,
) -> bool:
    raw = env.get(name)
    if raw is None or not raw.strip():
        return default
    normalized = raw.strip().lower()
    if normalized == "true":
        return True
    if normalized == "false":
        return False
    raise DispatcherConfigError(f"{name}_invalid")


def _bounded_int(
    env: Mapping[str, str],
    name: str,
    default: int,
    minimum: int,
    maximum: int,
) -> int:
    raw = env.get(name)
    if raw is None or not raw.strip():
        return default
    try:
        value = int(raw)
    except ValueError as exc:
        raise DispatcherConfigError(f"{name}_invalid") from exc
    if value < minimum or value > maximum:
        raise DispatcherConfigError(f"{name}_out_of_range")
    return value


def _bounded_float(
    env: Mapping[str, str],
    name: str,
    default: float,
    minimum: float,
    maximum: float,
) -> float:
    raw = env.get(name)
    if raw is None or not raw.strip():
        return default
    try:
        value = float(raw)
    except ValueError as exc:
        raise DispatcherConfigError(f"{name}_invalid") from exc
    if value < minimum or value > maximum:
        raise DispatcherConfigError(f"{name}_out_of_range")
    return value


def load_routes(
    path: Path,
    environ: Mapping[str, str] | None = None,
) -> dict[str, Route]:
    env = os.environ if environ is None else environ
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DispatcherConfigError("OUTBOX_ROUTES_FILE_invalid") from exc

    if not isinstance(raw, dict) or not raw or len(raw) > 32:
        raise DispatcherConfigError("OUTBOX_ROUTES_FILE_invalid")

    routes: dict[str, Route] = {}
    for event_type, config in raw.items():
        if not isinstance(event_type, str) or _EVENT_TYPE_PATTERN.fullmatch(event_type) is None:
            raise DispatcherConfigError("route_event_type_invalid")
        if not isinstance(config, dict) or set(config) != {"worker_slug", "token_env"}:
            raise DispatcherConfigError("route_definition_invalid")

        worker_slug = config.get("worker_slug")
        token_env = config.get("token_env")
        if (
            not isinstance(worker_slug, str)
            or _WORKER_SLUG_PATTERN.fullmatch(worker_slug) is None
        ):
            raise DispatcherConfigError("route_worker_slug_invalid")
        if (
            not isinstance(token_env, str)
            or _TOKEN_ENV_PATTERN.fullmatch(token_env) is None
        ):
            raise DispatcherConfigError("route_token_env_invalid")

        routes[event_type] = Route(
            event_type=event_type,
            worker_slug=worker_slug,
            token_env=token_env,
            token=_secret(env, token_env),
        )

    return routes


def _log(event: str, **fields: object) -> None:
    safe = {"event": event, **fields}
    print(json.dumps(safe, separators=(",", ":"), sort_keys=True), flush=True)


class OutboxDispatcher:
    def __init__(
        self,
        settings: Settings,
        routes: Mapping[str, Route],
        client: httpx.Client | None = None,
    ) -> None:
        if not routes:
            raise DispatcherConfigError("dispatcher_routes_required")
        self.settings = settings
        self.routes = dict(routes)
        self._owns_client = client is None
        self.client = client or httpx.Client(
            timeout=httpx.Timeout(settings.http_timeout_seconds),
            follow_redirects=False,
            trust_env=False,
            headers={"User-Agent": "MoneyBowl-Outbox-Dispatcher/1.0"},
        )

    def close(self) -> None:
        if self._owns_client:
            self.client.close()

    def _feed_url(self) -> str:
        return (
            f"{self.settings.supabase_url}"
            "/rest/v1/rpc/list_dispatchable_outbox_events"
        )

    def _worker_url(self, route: Route) -> str:
        return (
            f"{self.settings.supabase_url}"
            f"/functions/v1/{route.worker_slug}"
        )

    def fetch_candidates(self) -> list[Candidate]:
        response = self.client.post(
            self._feed_url(),
            headers={
                "apikey": self.settings.service_role_key,
                "Authorization": f"Bearer {self.settings.service_role_key}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            json={
                "p_event_types": list(self.routes),
                "p_limit": self.settings.batch_size,
                "p_retry_delay_seconds": self.settings.retry_delay_seconds,
            },
        )
        if response.status_code < 200 or response.status_code >= 300:
            raise DispatcherProtocolError(
                f"dispatch_feed_http_{response.status_code}"
            )
        if len(response.content) > _MAX_FEED_BYTES:
            raise DispatcherProtocolError("dispatch_feed_response_too_large")

        try:
            payload = response.json()
        except ValueError as exc:
            raise DispatcherProtocolError("dispatch_feed_response_invalid") from exc
        if not isinstance(payload, list) or len(payload) > self.settings.batch_size:
            raise DispatcherProtocolError("dispatch_feed_response_invalid")

        candidates: list[Candidate] = []
        for item in payload:
            candidates.append(self._parse_candidate(item))
        return candidates

    def _parse_candidate(self, item: object) -> Candidate:
        if not isinstance(item, dict):
            raise DispatcherProtocolError("dispatch_candidate_invalid")

        event_id = item.get("event_outbox_id")
        event_type = item.get("event_type")
        event_status = item.get("event_status")
        retry_count = item.get("retry_count")

        try:
            parsed_uuid = uuid.UUID(str(event_id))
        except (ValueError, TypeError, AttributeError) as exc:
            raise DispatcherProtocolError("dispatch_candidate_id_invalid") from exc

        if str(parsed_uuid) != str(event_id).lower():
            raise DispatcherProtocolError("dispatch_candidate_id_invalid")
        if not isinstance(event_type, str) or event_type not in self.routes:
            raise DispatcherProtocolError("dispatch_candidate_route_invalid")
        if event_status not in _ALLOWED_EVENT_STATUSES:
            raise DispatcherProtocolError("dispatch_candidate_status_invalid")
        if (
            isinstance(retry_count, bool)
            or not isinstance(retry_count, int)
            or retry_count < 0
        ):
            raise DispatcherProtocolError("dispatch_candidate_retry_invalid")

        return Candidate(
            event_outbox_id=str(parsed_uuid),
            event_type=event_type,
            event_status=str(event_status),
            retry_count=retry_count,
        )

    def dispatch(self, candidate: Candidate) -> str:
        route = self.routes[candidate.event_type]
        if self.settings.dry_run:
            _log(
                "dispatch_dry_run",
                event_outbox_id=candidate.event_outbox_id,
                event_type=candidate.event_type,
                event_status=candidate.event_status,
                retry_count=candidate.retry_count,
            )
            return "dry_run"

        try:
            response = self.client.post(
                self._worker_url(route),
                headers={
                    "Authorization": f"Bearer {route.token}",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
                json={"event_outbox_id": candidate.event_outbox_id},
            )
        except httpx.HTTPError:
            _log(
                "dispatch_transport_failed",
                event_outbox_id=candidate.event_outbox_id,
                event_type=candidate.event_type,
            )
            return "transport_failed"

        status = response.status_code
        if 200 <= status < 300:
            outcome = "worker_accepted"
        elif status == 404:
            outcome = "stale_or_raced"
        elif status in {401, 403}:
            outcome = "worker_auth_rejected"
        else:
            outcome = "worker_failed"

        _log(
            "dispatch_result",
            event_outbox_id=candidate.event_outbox_id,
            event_type=candidate.event_type,
            event_status=candidate.event_status,
            retry_count=candidate.retry_count,
            worker_status=status,
            outcome=outcome,
        )
        return outcome

    def run_once(self) -> int:
        candidates = self.fetch_candidates()
        self.touch_heartbeat()
        for candidate in candidates:
            self.dispatch(candidate)
        return len(candidates)

    def touch_heartbeat(self) -> None:
        self.settings.heartbeat_file.parent.mkdir(parents=True, exist_ok=True)
        self.settings.heartbeat_file.touch(exist_ok=True)


def run() -> int:
    try:
        settings = Settings.from_env()
        routes = load_routes(settings.routes_file)
    except DispatcherConfigError as exc:
        _log("dispatcher_configuration_failed", code=str(exc))
        return 2

    dispatcher = OutboxDispatcher(settings, routes)
    stop_requested = False

    def stop_handler(_signum: int, _frame: FrameType | None) -> None:
        nonlocal stop_requested
        stop_requested = True

    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)

    _log(
        "dispatcher_started",
        route_count=len(routes),
        poll_interval_seconds=settings.poll_interval_seconds,
        batch_size=settings.batch_size,
        retry_delay_seconds=settings.retry_delay_seconds,
        dry_run=settings.dry_run,
    )

    consecutive_feed_failures = 0
    try:
        while not stop_requested:
            try:
                dispatcher.run_once()
                consecutive_feed_failures = 0
                sleep_seconds = settings.poll_interval_seconds
            except (httpx.HTTPError, DispatcherProtocolError):
                consecutive_feed_failures += 1
                _log(
                    "dispatch_feed_failed",
                    consecutive_failures=consecutive_feed_failures,
                )
                if (
                    consecutive_feed_failures
                    >= settings.max_consecutive_feed_failures
                ):
                    _log("dispatcher_feed_failure_limit_reached")
                    return 1
                sleep_seconds = settings.failure_backoff_seconds

            deadline = time.monotonic() + sleep_seconds
            while not stop_requested and time.monotonic() < deadline:
                time.sleep(min(0.5, max(0.0, deadline - time.monotonic())))
    finally:
        dispatcher.close()

    _log("dispatcher_stopped")
    return 0


if __name__ == "__main__":
    sys.exit(run())
