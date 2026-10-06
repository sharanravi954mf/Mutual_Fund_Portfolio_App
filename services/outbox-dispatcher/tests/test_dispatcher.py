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
NSE_TOKEN = "n" * 40
EVENT_ID = "10000000-0000-4000-8000-000000000001"


def _routes_file(tmp_path: Path) -> Path:
    path = tmp_path / "routes.json"
    path.write_text(
        json.dumps(
            {
                "integration.nse.ucc_registration_requested": {
                    "worker_slug": "nse-ucc-registration-worker",
                    "token_env": "NSE_WORKER_TOKEN",
                },
                "integration.nse.ucc_verification_requested": {
                    "worker_slug": "nse-ucc-reconciliation-worker",
                    "token_env": "NSE_WORKER_TOKEN",
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
        "NSE_WORKER_TOKEN": NSE_TOKEN,
        "OUTBOX_ROUTES_FILE": str(_routes_file(tmp_path)),
        "OUTBOX_HEARTBEAT_FILE": str(tmp_path / "heartbeat"),
        "OUTBOX_DISPATCH_DRY_RUN": "false",
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
    assert routes["integration.nse.ucc_registration_requested"].token == NSE_TOKEN
    assert routes["integration.nse.ucc_verification_requested"].token == NSE_TOKEN

    raw_routes = Path(env["OUTBOX_ROUTES_FILE"]).read_text(encoding="utf-8")
    assert NSE_TOKEN not in raw_routes


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
    assert NSE_TOKEN not in json.dumps(seen)


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
    assert seen["authorization"] == f"Bearer {NSE_TOKEN}"
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
        assert request.headers["authorization"] == f"Bearer {NSE_TOKEN}"
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


def test_dry_run_never_invokes_worker(tmp_path: Path) -> None:
    env = _env(tmp_path)
    env["OUTBOX_DISPATCH_DRY_RUN"] = "true"
    settings = Settings.from_env(env)
    routes = load_routes(settings.routes_file, env)
    calls = 0

    def handler(_request: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(500)

    dispatcher = OutboxDispatcher(
        settings,
        routes,
        httpx.Client(transport=httpx.MockTransport(handler)),
    )

    assert dispatcher.dispatch(
        Candidate(
            event_outbox_id=EVENT_ID,
            event_type="integration.nse.ucc_registration_requested",
            event_status="pending",
            retry_count=0,
        )
    ) == "dry_run"
    assert calls == 0


def test_dry_run_defaults_to_true(tmp_path: Path) -> None:
    env = _env(tmp_path)
    del env["OUTBOX_DISPATCH_DRY_RUN"]
    assert Settings.from_env(env).dry_run is True


def test_repository_order_status_route_uses_dedicated_worker() -> None:
    routes = load_routes(
        Path(__file__).parents[1] / "routes.json",
        {"NSE_WORKER_TOKEN": NSE_TOKEN},
    )
    route = routes["integration.nse.order_status_requested"]
    assert route.worker_slug == "nse-order-status-worker"
    assert route.token == NSE_TOKEN


def test_repository_prov_orders_route_uses_shared_nse_token() -> None:
    routes = load_routes(
        Path(__file__).parents[1] / "routes.json",
        {"NSE_WORKER_TOKEN": NSE_TOKEN},
    )
    route = routes["integration.nse.prov_orders_requested"]
    assert route.worker_slug == "nse-prov-orders-worker"
    assert route.token == NSE_TOKEN


def test_repository_readiness_route_uses_shared_nse_token() -> None:
    routes = load_routes(
        Path(__file__).parents[1] / "routes.json",
        {"NSE_WORKER_TOKEN": NSE_TOKEN},
    )
    route = routes["integration.nse.client_readiness_requested"]
    assert route.worker_slug == "nse-client-readiness-worker"
    assert route.token == NSE_TOKEN


def test_repository_order_funding_route_uses_shared_nse_token() -> None:
    routes = load_routes(
        Path(__file__).parents[1] / "routes.json",
        {"NSE_WORKER_TOKEN": NSE_TOKEN},
    )
    route = routes["integration.nse.order_funding_requested"]
    assert route.worker_slug == "nse-order-funding-worker"
    assert route.token == NSE_TOKEN


def test_repository_settlement_redemption_route_uses_shared_nse_token() -> None:
    routes = load_routes(Path(__file__).resolve().parents[1] / "routes.json", {"NSE_WORKER_TOKEN": NSE_TOKEN})
    route = routes["integration.nse.settlement_redemption_requested"]
    assert route.worker_slug == "nse-settlement-redemption-worker"
    assert route.token == NSE_TOKEN


def test_repository_sip_xsip_reports_route_uses_shared_nse_token() -> None:
    routes = load_routes(Path(__file__).resolve().parents[1] / "routes.json", {"NSE_WORKER_TOKEN": NSE_TOKEN})
    route = routes["integration.nse.sip_xsip_reports_requested"]
    assert route.worker_slug == "nse-sip-xsip-reports-worker"
    assert route.token == NSE_TOKEN


def test_master_download_uses_commissioned_route_and_event_id_only(tmp_path: Path) -> None:
    env = _env(tmp_path)
    env["OUTBOX_ROUTES_FILE"] = str(Path(__file__).parents[1] / "routes.json")
    settings = Settings.from_env(env)
    routes = load_routes(settings.routes_file, env)
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={"data": {"publication_gate": "BLOCKED"}})

    dispatcher = OutboxDispatcher(settings, routes, httpx.Client(transport=httpx.MockTransport(handler)))
    result = dispatcher.dispatch(Candidate(EVENT_ID, "integration.nse.master_download_requested", "pending", 0))
    assert result == "worker_accepted"
    assert str(requests[0].url).endswith("/functions/v1/nse-master-download-worker")
    assert json.loads(requests[0].content) == {"event_outbox_id": EVENT_ID}
    assert requests[0].headers["authorization"] == f"Bearer {NSE_TOKEN}"
    assert SERVICE_KEY not in str(requests[0].headers)


def test_mandate_status_route_uses_shared_token_and_event_only(tmp_path: Path) -> None:
    env = _env(tmp_path)
    env["OUTBOX_ROUTES_FILE"] = str(Path(__file__).parents[1] / "routes.json")
    settings = Settings.from_env(env)
    routes = load_routes(settings.routes_file, env)
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200, json={"data": {"outcome": "mandate_status_unique_match_received"}})

    dispatcher = OutboxDispatcher(settings, routes, httpx.Client(transport=httpx.MockTransport(handler)))
    assert dispatcher.dispatch(Candidate(EVENT_ID, "integration.nse.mandate_status_requested", "pending", 0)) == "worker_accepted"
    assert str(requests[0].url).endswith("/functions/v1/nse-mandate-status-worker")
    assert json.loads(requests[0].content) == {"event_outbox_id": EVENT_ID}
    assert requests[0].headers["authorization"] == f"Bearer {NSE_TOKEN}"
    assert not any("bank_add" in event or "bank_del" in event or "mandate_registration" in event for event in routes)


@pytest.mark.parametrize("action", ["mandate_registration", "bank_add", "bank_del"])
def test_blocked_b07_write_feed_never_invokes_worker(tmp_path: Path, action: str) -> None:
    env = _env(tmp_path)
    env["OUTBOX_ROUTES_FILE"] = str(Path(__file__).parents[1] / "routes.json")
    settings = Settings.from_env(env)
    routes = load_routes(settings.routes_file, env)
    requests: list[httpx.Request] = []
    event_type = f"integration.nse.{action}_requested"

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        assert request.url.path == "/rest/v1/rpc/list_dispatchable_outbox_events"
        assert event_type not in json.loads(request.content)["p_event_types"]
        return httpx.Response(200, json=[{
            "event_outbox_id": EVENT_ID,
            "event_type": event_type,
            "event_status": "pending",
            "retry_count": 0,
        }])

    dispatcher = OutboxDispatcher(settings, routes, httpx.Client(transport=httpx.MockTransport(handler)))
    with pytest.raises(DispatcherProtocolError, match="dispatch_candidate_route_invalid"):
        dispatcher.run_once()
    assert len(requests) == 1
