from __future__ import annotations

import json
import logging
from urllib.parse import parse_qs, urlparse

import httpx
from fastapi.testclient import TestClient

from app.mailbox import GmailProvider, GMAIL_READONLY_SCOPE
from app.main import create_app
from conftest import FakeMalwareScanner, mailbox_headers


STATE = "A" * 43


def _client(settings, handler):
    provider = GmailProvider(settings, httpx.MockTransport(handler))
    return TestClient(create_app(settings, provider, FakeMalwareScanner()))


def test_oauth_authorization_url_is_exact_minimal_offline_flow(settings) -> None:
    provider = GmailProvider(settings)
    app = create_app(settings, provider, FakeMalwareScanner())
    with TestClient(app) as client:
        response = client.post(
            "/oauth/authorization-url",
            headers=mailbox_headers(settings),
            json={"state": STATE, "redirect_uri": settings.gmail_oauth_redirect_uri},
        )
    assert response.status_code == 200
    parsed = urlparse(response.json()["authorization_url"])
    query = parse_qs(parsed.query)
    assert f"{parsed.scheme}://{parsed.netloc}{parsed.path}" == settings.gmail_oauth_authorization_url
    assert query == {
        "client_id": [settings.gmail_oauth_client_id],
        "redirect_uri": [settings.gmail_oauth_redirect_uri],
        "response_type": ["code"],
        "scope": [GMAIL_READONLY_SCOPE],
        "access_type": ["offline"],
        "prompt": ["consent"],
        "state": [STATE],
    }


def test_oauth_exchange_is_server_side_and_requires_refresh_token(settings) -> None:
    seen: dict[str, list[str]] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url == settings.gmail_oauth_token_url
        seen.update(parse_qs(request.content.decode()))
        return httpx.Response(
            200,
            json={"access_token": "access-secret", "refresh_token": "refresh-secret", "expires_in": 3600},
        )

    with _client(settings, handler) as client:
        response = client.post(
            "/oauth/exchange",
            headers=mailbox_headers(settings),
            json={"code": "one-time-code", "redirect_uri": settings.gmail_oauth_redirect_uri},
        )
    assert response.status_code == 200
    assert seen == {
        "client_id": [settings.gmail_oauth_client_id],
        "client_secret": [settings.gmail_oauth_client_secret],
        "code": ["one-time-code"],
        "grant_type": ["authorization_code"],
        "redirect_uri": [settings.gmail_oauth_redirect_uri],
    }
    assert response.headers["cache-control"] == "no-store"


def test_oauth_exchange_rejects_missing_refresh_token(settings) -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"access_token": "access-secret", "expires_in": 3600})

    with _client(settings, handler) as client:
        response = client.post(
            "/oauth/exchange",
            headers=mailbox_headers(settings),
            json={"code": "one-time-code", "redirect_uri": settings.gmail_oauth_redirect_uri},
        )
    assert response.status_code == 502
    assert response.json() == {"error": {"code": "oauth_refresh_token_required"}}


def test_oauth_redirect_mismatch_and_google_error_are_sanitized(settings) -> None:
    def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": "invalid_grant", "error_description": "secret detail"})

    with _client(settings, handler) as client:
        mismatch = client.post(
            "/oauth/exchange",
            headers=mailbox_headers(settings),
            json={"code": "code", "redirect_uri": "https://attacker.example/callback"},
        )
        failed = client.post(
            "/oauth/exchange",
            headers=mailbox_headers(settings),
            json={"code": "code", "redirect_uri": settings.gmail_oauth_redirect_uri},
        )
    assert mismatch.status_code == 400
    assert mismatch.json() == {"error": {"code": "oauth_redirect_uri_mismatch"}}
    assert failed.status_code == 502
    assert failed.json() == {"error": {"code": "provider_request_failed"}}
    assert "secret detail" not in failed.text


def test_oauth_revocation_uses_post_body_and_sanitized_logs(settings, caplog) -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(200)

    caplog.set_level(logging.INFO, logger="moneybowl.ingestion_support")
    with _client(settings, handler) as client:
        response = client.post(
            "/oauth/revoke?access_token=must-not-be-logged",
            headers=mailbox_headers(settings),
            json={"token": "refresh-secret"},
        )
    assert response.status_code == 204
    assert requests[0].url.query == b""
    assert parse_qs(requests[0].content.decode()) == {"token": ["refresh-secret"]}
    logs = "\n".join(record.getMessage() for record in caplog.records)
    assert "must-not-be-logged" not in logs
    assert "refresh-secret" not in logs
    assert json.loads(caplog.records[-1].getMessage())["route"] == "/oauth/revoke"
