from __future__ import annotations

import json
from pathlib import Path

import httpx
import pytest

from dispatcher import (
    Candidate,
    DispatcherConfigError,
    DispatcherProtocolError,
    OutboxDispatcher,
    Settings,
    load_routes,
)


SERVICE_KEY = "s" * 40
REG_TOKEN = "r" * 40
VERIFY_TOKEN = "v" * 40
EVENT_ID = "10000000-0000-4000-8000-000000000001"


def _routes_file(tmp_path: Path) -> Path:
    path = tmp_path / "routes.json"
    path.write_text(
        json.dumps(
            {
                "integration.nse.ucc_registration_requested": {
                    "worker_slug": "nse-ucc-registration-worker",
                    "token_env": "NSE_UCC_WORKER_TOKEN",
                },
                "integration.nse.ucc_verification_requested": {
                    "worker_slug": "nse-ucc-reconciliation-worker",
                    "token_env": "NSE_UCC_RECONCILIATION_WORKER_TOKEN",
                },
            }
        ),
        encoding="utf-8",
    )
    return path


def _env(tmp_path: Path) -> dict[str, str]:
    return {
        "SUPABASE_URL": "https://example.supabase.co",
        "SUPABASE_SERVICE_ROLE_KEY": SERVICE_KEY,
        "NSE_UCC_WORKER_TOKEN": REG_TOKEN,
        "NSE_UCC_RECONCILIATION_WORKER_TOKEN": VERIFY_TOKEN,
        "OUTBOX_ROUTES_FILE": str(_routes_file(tmp_path)),
        "OUTBOX_HEARTBEAT_FILE": str(tmp_path / "heartbeat"),
    }


def _settings(tmp_path: Path) -> Settings:
    return Settings.from_env(_env(tmp_path))


def test_settings_require_https_except_explicit_loopback(tmp_path: Path) -> None:
    env = _env(tmp_path)
    Settings.from_env(env)

    env["SUPABASE_URL"] = "http://127.0.0.1:54321"
    assert Settings.from_env(env).supabase_url == "http://127.0.0.1:54321"

    env["SUPABASE_URL"] = "http://example.supabase.co"
    with pytest.raises(DispatcherConfigError, match="SUPABASE_URL_requires_https"):
        Settings.from_env(env)

    env["SUPABASE_URL"] = "https://token@example.supabase.co"
    with pytest.raises(DispatcherConfigError, match="SUPABASE_URL_invalid"):
        Settings.from_env(env)


def test_routes_are_config_driven_and_tokens_stay_in_environment(tmp_path: Path) -> None:
    env = _env(tmp_path)
    routes = load_routes(Path(env["OUTBOX_ROUTES_FILE"]), env)

    assert set(routes) == {
        "integration.nse.ucc_registration_requested",
        "integration.nse.ucc_verification_requested",
    }
    assert routes["integration.nse.ucc_registration_requested"].token == REG_TOKEN
    assert routes["integration.nse.ucc_verification_requested"].token == VERIFY_TOKEN

    raw_routes = Path(env["OUTBOX_ROUTES_FILE"]).read_text(encoding="utf-8")
    assert REG_TOKEN not in raw_routes
    assert VERIFY_TOKEN not in raw_routes


def test_feed_uses_service_role_but_returns_metadata_only(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    routes = load_routes(settings.routes_file, _env(tmp_path))
    seen: dict[str, object] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["authorization"] = request.headers.get("authorization")
        seen["apikey"] = request.headers.get("apikey")
        seen["body"] = json.loads(request.content)
        return httpx.Response(
            200,
            json=[
                {
                    "event_outbox_id": EVENT_ID,
                    "event_type": "integration.nse.ucc_registration_requested",
                    "event_status": "pending",
                    "retry_count": 0,
                    "claim_expires_at": None,
                    "created_at": "2026-09-05T09:30:00Z",
                }
            ],
        )

    client = httpx.Client(transport=httpx.MockTransport(handler))
    dispatcher = OutboxDispatcher(settings, routes, client)

    candidates = dispatcher.fetch_candidates()

    assert candidates == [
        Candidate(
            event_outbox_id=EVENT_ID,
            event_type="integration.nse.ucc_registration_requested",
            event_status="pending",
            retry_count=0,
        )
    ]
    assert seen["url"] == (
        "https://example.supabase.co/rest/v1/rpc/list_dispatchable_outbox_events"
    )
    assert seen["authorization"] == f"Bearer {SERVICE_KEY}"
    assert seen["apikey"] == SERVICE_KEY
    assert seen["body"] == {
        "p_event_types": [
            "integration.nse.ucc_registration_requested",
            "integration.nse.ucc_verification_requested",
        ],
        "p_limit": 10,
        "p_retry_delay_seconds": 30,
    }
    assert REG_TOKEN not in json.dumps(seen)
    assert VERIFY_TOKEN not in json.dumps(seen)


def test_worker_dispatch_uses_route_token_and_event_id_only(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    env = _env(tmp_path)
    routes = load_routes(settings.routes_file, env)
    seen: dict[str, object] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["authorization"] = request.headers.get("authorization")
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json={"data": {"outcome": "synthetic"}})

    dispatcher = OutboxDispatcher(
        settings,
        routes,
        httpx.Client(transport=httpx.MockTransport(handler)),
    )
    outcome = dispatcher.dispatch(
        Candidate(
            event_outbox_id=EVENT_ID,
            event_type="integration.nse.ucc_registration_requested",
            event_status="pending",
            retry_count=0,
        )
    )

    assert outcome == "worker_accepted"
    assert seen["url"] == (
        "https://example.supabase.co/functions/v1/nse-ucc-registration-worker"
    )
    assert seen["authorization"] == f"Bearer {REG_TOKEN}"
    assert seen["body"] == {"event_outbox_id": EVENT_ID}
    assert SERVICE_KEY not in json.dumps(seen)


def test_verification_event_routes_to_reconciliation_worker(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    env = _env(tmp_path)
    routes = load_routes(settings.routes_file, env)

    def handler(request: httpx.Request) -> httpx.Response:
        assert str(request.url).endswith(
            "/functions/v1/nse-ucc-reconciliation-worker"
        )
        assert request.headers["authorization"] == f"Bearer {VERIFY_TOKEN}"
        return httpx.Response(202, json={"data": {"outcome": "synthetic"}})

    dispatcher = OutboxDispatcher(
        settings,
        routes,
        httpx.Client(transport=httpx.MockTransport(handler)),
    )

    assert dispatcher.dispatch(
        Candidate(
            event_outbox_id=EVENT_ID,
            event_type="integration.nse.ucc_verification_requested",
            event_status="failed",
            retry_count=1,
        )
    ) == "worker_accepted"


def test_worker_404_is_benign_race_and_does_not_mutate_outbox(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    env = _env(tmp_path)
    routes = load_routes(settings.routes_file, env)

    dispatcher = OutboxDispatcher(
        settings,
        routes,
        httpx.Client(
            transport=httpx.MockTransport(
                lambda _request: httpx.Response(
                    404,
                    json={"error": {"code": "requested_event_not_found"}},
                )
            )
        ),
    )

    assert dispatcher.dispatch(
        Candidate(
            event_outbox_id=EVENT_ID,
            event_type="integration.nse.ucc_registration_requested",
            event_status="pending",
            retry_count=0,
        )
    ) == "stale_or_raced"


def test_feed_rejects_unknown_route_even_if_server_returns_it(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    env = _env(tmp_path)
    routes = load_routes(settings.routes_file, env)

    dispatcher = OutboxDispatcher(
        settings,
        routes,
        httpx.Client(
            transport=httpx.MockTransport(
                lambda _request: httpx.Response(
                    200,
                    json=[
                        {
                            "event_outbox_id": EVENT_ID,
                            "event_type": "integration.unknown.requested",
                            "event_status": "pending",
                            "retry_count": 0,
                        }
                    ],
                )
            )
        ),
    )

    with pytest.raises(
        DispatcherProtocolError,
        match="dispatch_candidate_route_invalid",
    ):
        dispatcher.fetch_candidates()


def test_run_once_updates_heartbeat_after_successful_feed(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    env = _env(tmp_path)
    routes = load_routes(settings.routes_file, env)

    dispatcher = OutboxDispatcher(
        settings,
        routes,
        httpx.Client(
            transport=httpx.MockTransport(
                lambda _request: httpx.Response(200, json=[])
            )
        ),
    )

    assert dispatcher.run_once() == 0
    assert settings.heartbeat_file.exists()
