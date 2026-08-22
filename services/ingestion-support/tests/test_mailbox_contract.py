from __future__ import annotations

import asyncio
import json
import logging

import httpx
import pytest
from fastapi.testclient import TestClient

from app.errors import ServiceError
from app.mailbox import (
    AccessTokenCache,
    FetchRequest,
    GmailProvider,
    PollRequest,
    RefreshRequest,
)
from app.main import create_app
from conftest import FakeMailboxProvider, FakeMalwareScanner, mailbox_headers, poll_body


def gmail_message(message_id: str, sender: str = "statements@example.test") -> dict[str, object]:
    return {
        "id": message_id,
        "internalDate": "1787392800000",
        "payload": {
            "headers": [{"name": "From", "value": f"Statements <{sender}>"}],
            "parts": [
                {
                    "filename": f"synthetic-{message_id}.pdf",
                    "mimeType": "application/pdf",
                    "body": {"attachmentId": f"attachment-{message_id}"},
                }
            ],
        },
    }


def test_refresh_poll_and_fetch_match_edge_contract(client, settings, fake_mailbox) -> None:
    headers = mailbox_headers(settings)
    refresh = client.post(
        "/oauth/refresh",
        headers=headers,
        json={
            "workspace_id": "workspace-fixture-1",
            "mailbox_connection_id": "mailbox-fixture-1",
            "connector_ref": "gmail:me",
            "registrar": "CAMS",
            "refresh_token": "refresh-fixture",
        },
    )
    assert refresh.status_code == 200
    assert refresh.json() == {
        "access_token": "refreshed-access-token",
        "refresh_token": "rotated-refresh-token",
        "expires_at": "2026-08-22T12:00:00Z",
    }

    poll = client.post(
        "/poll",
        headers={**headers, "X-Mailbox-OAuth-Token": "worker-access-token"},
        json=poll_body(),
    )
    assert poll.status_code == 200
    assert poll.json() == {
        "messages": [
            {
                "message_id": "gmail-message-1",
                "sender_address": "statements@example.test",
                "received_at": "2026-08-22T10:00:00Z",
                "attachments": [
                    {
                        "attachment_id": "gmail-attachment-1",
                        "filename": "synthetic-cams.pdf",
                        "declared_mime": "application/pdf",
                        "received_at": "2026-08-22T10:00:00Z",
                    }
                ],
            }
        ]
    }

    fetched = client.post(
        "/attachments/fetch",
        headers=headers,
        json={
            **poll_body(),
            "message_id": "gmail-message-1",
            "attachment_id": "gmail-attachment-1",
        },
    )
    assert fetched.status_code == 200
    assert fetched.content == b"synthetic attachment"
    assert fetched.headers["content-type"] == "application/octet-stream"
    assert fake_mailbox.access_tokens == ["worker-access-token", "worker-access-token"]


def test_fetch_requires_matching_short_lived_oauth_context(client, settings) -> None:
    response = client.post(
        "/attachments/fetch",
        headers=mailbox_headers(settings),
        json={
            **poll_body(mailbox_connection_id="uncached-mailbox"),
            "message_id": "gmail-message-1",
            "attachment_id": "gmail-attachment-1",
        },
    )
    assert response.status_code == 409
    assert response.json() == {"error": {"code": "mailbox_oauth_context_required"}}


def test_mailbox_rejects_missing_oauth_malformed_and_oversized_json(client, settings) -> None:
    headers = mailbox_headers(settings)
    missing_oauth = client.post("/poll", headers=headers, json=poll_body())
    assert missing_oauth.status_code == 401

    malformed = client.post("/poll", headers=headers, content=b"{")
    assert malformed.status_code == 401  # OAuth is checked before parsing.

    oversized = client.post(
        "/poll",
        headers={**headers, "X-Mailbox-OAuth-Token": "worker-access-token"},
        content=json.dumps({"padding": "x" * 70_000}),
    )
    assert oversized.status_code == 413


def test_provider_failure_and_timeout_fail_closed(client, settings, fake_mailbox) -> None:
    fake_mailbox.failure = ServiceError(503, "provider_unavailable")
    response = client.post(
        "/poll",
        headers={**mailbox_headers(settings), "X-Mailbox-OAuth-Token": "token"},
        json=poll_body(),
    )
    assert response.status_code == 503
    assert response.json() == {"error": {"code": "provider_unavailable"}}


@pytest.mark.asyncio
async def test_gmail_provider_rejects_redirects_and_oversized_responses(settings) -> None:
    request = RefreshRequest(
        workspace_id="workspace-fixture-1",
        mailbox_connection_id="mailbox-fixture-1",
        connector_ref="gmail:me",
        registrar="CAMS",
        refresh_token="refresh-fixture",
    )

    redirect_provider = GmailProvider(
        settings,
        httpx.MockTransport(lambda _request: httpx.Response(302, headers={"Location": "https://evil.test"})),
    )
    with pytest.raises(ServiceError, match="provider_redirect_rejected"):
        await redirect_provider.refresh(request)
    await redirect_provider.close()

    limited_settings = settings.model_copy(update={"max_provider_response_bytes": 1024})
    oversized_provider = GmailProvider(
        limited_settings,
        httpx.MockTransport(
            lambda _request: httpx.Response(
                200,
                content=json.dumps({"padding": "x" * 2000}),
                headers={"Content-Type": "application/json"},
            )
        ),
    )
    with pytest.raises(ServiceError, match="provider_response_too_large"):
        await oversized_provider.refresh(request)
    await oversized_provider.close()


@pytest.mark.asyncio
async def test_gmail_provider_enforces_slow_response_timeout(settings) -> None:
    async def slow_handler(_reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        await asyncio.sleep(0.2)
        writer.close()

    server = await asyncio.start_server(slow_handler, "127.0.0.1", 0)
    port = server.sockets[0].getsockname()[1]
    limited_settings = settings.model_copy(
        update={
            "gmail_oauth_token_url": f"http://127.0.0.1:{port}/token",
            "provider_timeout_seconds": 0.05,
        }
    )
    provider = GmailProvider(limited_settings)
    request = RefreshRequest(
        workspace_id="workspace-fixture-1",
        mailbox_connection_id="mailbox-fixture-1",
        connector_ref="gmail:me",
        registrar="CAMS",
        refresh_token="refresh-fixture",
    )
    async with server:
        with pytest.raises(ServiceError, match="provider_unavailable"):
            await provider.refresh(request)
        await provider.close()
        await asyncio.sleep(0.2)


@pytest.mark.asyncio
async def test_gmail_provider_refresh_poll_and_fetch_adapter(settings) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        path = request.url.path
        if request.url.host == "oauth2.googleapis.com":
            return httpx.Response(200, json={"access_token": "gmail-access", "expires_in": 3600})
        if path.endswith("/messages"):
            assert request.url.params["q"] == "has:attachment {filename:pdf filename:dbf}"
            return httpx.Response(200, json={"messages": [{"id": "gmailMessage1"}]})
        if path.endswith("/messages/gmailMessage1"):
            payload = gmail_message("gmailMessage1")
            payload["payload"]["parts"][0]["body"]["attachmentId"] = "gmailAttachment1"
            return httpx.Response(200, json=payload)
        if path.endswith("/attachments/gmailAttachment1"):
            return httpx.Response(200, json={"data": "Ynl0ZXM", "size": 5})
        return httpx.Response(404)

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    refreshed = await provider.refresh(
        RefreshRequest(
            workspace_id="workspace-fixture-1",
            mailbox_connection_id="mailbox-fixture-1",
            connector_ref="gmail:me",
            registrar="CAMS",
            refresh_token="refresh-fixture",
        )
    )
    assert refreshed.access_token == "gmail-access"

    poll_request = PollRequest(
        connector_ref="gmail:me",
        mailbox_connection_id="mailbox-fixture-1",
        registrar="CAMS",
    )
    messages = await provider.poll(poll_request, refreshed.access_token)
    assert messages[0].sender_address == "statements@example.test"
    assert messages[0].attachments[0].attachment_id == "gmailAttachment1"
    content = await provider.fetch_attachment(
        FetchRequest(
            **poll_request.model_dump(),
            message_id="gmailMessage1",
            attachment_id="gmailAttachment1",
        ),
        refreshed.access_token,
        1024,
    )
    assert content == b"bytes"
    await provider.close()


@pytest.mark.asyncio
async def test_gmail_poll_page_fairly_includes_target_after_full_first_page(settings) -> None:
    limited = settings.model_copy(
        update={
            "max_mailbox_messages": 2,
            "max_mailbox_pages_per_poll": 2,
            "max_mailbox_candidates_per_poll": 4,
        }
    )
    listing_tokens: list[str | None] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            page_token = request.url.params.get("pageToken")
            listing_tokens.append(page_token)
            assert request.url.params["q"] == "has:attachment {filename:pdf filename:dbf}"
            if page_token is None:
                return httpx.Response(
                    200,
                    json={
                        "messages": [{"id": "newer1"}, {"id": "newer2"}],
                        "nextPageToken": "page-2",
                    },
                )
            assert page_token == "page-2"
            return httpx.Response(
                200,
                json={"messages": [{"id": "camsTarget"}, {"id": "older2"}]},
            )
        message_id = request.url.path.rsplit("/", 1)[-1]
        return httpx.Response(200, json=gmail_message(message_id))

    provider = GmailProvider(limited, httpx.MockTransport(handler))
    messages = await provider.poll(
        PollRequest(
            connector_ref="gmail:me",
            mailbox_connection_id="mailbox-fixture-1",
            registrar="CAMS",
        ),
        "pagination-oauth-token",
    )
    await provider.close()

    assert listing_tokens == [None, "page-2"]
    assert [message.message_id for message in messages] == ["newer1", "camsTarget"]


@pytest.mark.asyncio
async def test_gmail_poll_stops_at_maximum_page_bound(settings) -> None:
    limited = settings.model_copy(
        update={
            "max_mailbox_messages": 4,
            "max_mailbox_pages_per_poll": 2,
            "max_mailbox_candidates_per_poll": 20,
        }
    )
    list_calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal list_calls
        if request.url.path.endswith("/messages"):
            list_calls += 1
            return httpx.Response(
                200,
                json={
                    "messages": [{"id": f"page{list_calls}Message"}],
                    "nextPageToken": f"page-{list_calls + 1}",
                },
            )
        return httpx.Response(200, json=gmail_message(request.url.path.rsplit("/", 1)[-1]))

    provider = GmailProvider(limited, httpx.MockTransport(handler))
    messages = await provider.poll(
        PollRequest(
            connector_ref="gmail:me",
            mailbox_connection_id="mailbox-fixture-1",
            registrar="CAMS",
        ),
        "bounded-oauth-token",
    )
    await provider.close()

    assert list_calls == 2
    assert [message.message_id for message in messages] == ["page1Message", "page2Message"]


@pytest.mark.asyncio
async def test_gmail_poll_stops_at_candidate_bound(settings) -> None:
    limited = settings.model_copy(
        update={
            "max_mailbox_messages": 2,
            "max_mailbox_pages_per_poll": 4,
            "max_mailbox_candidates_per_poll": 3,
        }
    )
    list_max_results: list[int] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            list_max_results.append(int(request.url.params["maxResults"]))
            if len(list_max_results) == 1:
                return httpx.Response(
                    200,
                    json={
                        "messages": [{"id": "candidate1"}, {"id": "candidate2"}],
                        "nextPageToken": "candidate-page-2",
                    },
                )
            return httpx.Response(
                200,
                json={
                    "messages": [{"id": "candidate3"}],
                    "nextPageToken": "candidate-page-3",
                },
            )
        return httpx.Response(200, json=gmail_message(request.url.path.rsplit("/", 1)[-1]))

    provider = GmailProvider(limited, httpx.MockTransport(handler))
    messages = await provider.poll(
        PollRequest(
            connector_ref="gmail:me",
            mailbox_connection_id="mailbox-fixture-1",
            registrar="CAMS",
        ),
        "candidate-oauth-token",
    )
    await provider.close()

    assert list_max_results == [2, 1]
    assert [message.message_id for message in messages] == ["candidate1", "candidate3"]


@pytest.mark.asyncio
@pytest.mark.parametrize("bad_token", [123, "", "bad page token"])
async def test_gmail_poll_rejects_malformed_next_page_token(settings, bad_token) -> None:
    provider = GmailProvider(
        settings,
        httpx.MockTransport(
            lambda _request: httpx.Response(
                200,
                json={"messages": [], "nextPageToken": bad_token},
            )
        ),
    )
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        await provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "malformed-page-token-oauth",
        )
    await provider.close()


@pytest.mark.asyncio
async def test_gmail_poll_rejects_repeated_page_token_without_looping(settings) -> None:
    list_calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal list_calls
        list_calls += 1
        return httpx.Response(200, json={"messages": [], "nextPageToken": "repeated"})

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        await provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "repeated-page-token-oauth",
        )
    await provider.close()
    assert list_calls == 2


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("later_failure", "expected_code"),
    [("timeout", "provider_unavailable"), ("error", "provider_request_failed")],
)
async def test_gmail_poll_later_page_failure_is_closed_and_tokens_are_not_logged(
    settings, caplog, later_failure: str, expected_code: str
) -> None:
    caplog.set_level(logging.INFO, logger="moneybowl.ingestion_support")
    oauth_token = "later-page-oauth-token-that-must-not-be-logged"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            if request.url.params.get("pageToken") is None:
                return httpx.Response(
                    200,
                    json={
                        "messages": [{"id": "firstPageMessage"}],
                        "nextPageToken": "later-page",
                    },
                )
            if later_failure == "timeout":
                raise httpx.ReadTimeout("synthetic timeout", request=request)
            return httpx.Response(503)
        return httpx.Response(200, json=gmail_message("firstPageMessage"))

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    with pytest.raises(ServiceError, match=expected_code):
        await provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            oauth_token,
        )
    await provider.close()
    assert oauth_token not in caplog.text


def test_attachment_fetch_response_is_bounded(client, settings, fake_mailbox) -> None:
    fake_mailbox.attachment_content = b"x" * (settings.max_attachment_bytes + 1)
    headers = mailbox_headers(settings)
    poll = client.post(
        "/poll",
        headers={**headers, "X-Mailbox-OAuth-Token": "worker-access-token"},
        json=poll_body(),
    )
    assert poll.status_code == 200
    fetched = client.post(
        "/attachments/fetch",
        headers=headers,
        json={
            **poll_body(),
            "message_id": "gmail-message-1",
            "attachment_id": "gmail-attachment-1",
        },
    )
    assert fetched.status_code == 502
    assert fetched.json() == {"error": {"code": "provider_response_invalid"}}


def test_mailbox_provider_tokens_are_not_logged(client, settings, caplog) -> None:
    caplog.set_level(logging.INFO, logger="moneybowl.ingestion_support")
    secret_oauth = "oauth-value-that-must-never-be-logged"
    client.post(
        "/poll",
        headers={**mailbox_headers(settings), "X-Mailbox-OAuth-Token": secret_oauth},
        json=poll_body(),
    )
    assert secret_oauth not in caplog.text
    assert settings.mailbox_connector_service_token not in caplog.text


def test_process_restart_between_poll_and_fetch_requires_new_oauth_context(settings) -> None:
    first_app = create_app(settings, FakeMailboxProvider(), FakeMalwareScanner())
    with TestClient(first_app) as first_client:
        response = first_client.post(
            "/poll",
            headers={
                **mailbox_headers(settings),
                "X-Mailbox-OAuth-Token": "restart-fixture-oauth-token",
            },
            json=poll_body(),
        )
        assert response.status_code == 200

    restarted_app = create_app(settings, FakeMailboxProvider(), FakeMalwareScanner())
    with TestClient(restarted_app) as restarted_client:
        response = restarted_client.post(
            "/attachments/fetch",
            headers=mailbox_headers(settings),
            json={
                **poll_body(),
                "message_id": "gmail-message-1",
                "attachment_id": "gmail-attachment-1",
            },
        )
    assert response.status_code == 409
    assert response.json() == {"error": {"code": "mailbox_oauth_context_required"}}


@pytest.mark.asyncio
async def test_oauth_cache_expiry_and_lru_eviction_fail_closed(monkeypatch) -> None:
    now = 100.0
    monkeypatch.setattr("app.mailbox.time.monotonic", lambda: now)
    cache = AccessTokenCache(ttl_seconds=5, max_entries=2)
    first = ("gmail:me", "mailbox-1", "CAMS")
    second = ("gmail:me", "mailbox-2", "CAMS")
    third = ("gmail:me", "mailbox-3", "CAMS")

    await cache.put(first, "oauth-first")
    await cache.put(second, "oauth-second")
    assert await cache.get(first) == "oauth-first"
    await cache.put(third, "oauth-third")
    with pytest.raises(ServiceError, match="mailbox_oauth_context_required"):
        await cache.get(second)

    now = 106.0
    for key in (first, third):
        with pytest.raises(ServiceError, match="mailbox_oauth_context_required"):
            await cache.get(key)


@pytest.mark.asyncio
async def test_oauth_cache_isolates_concurrent_mailboxes_and_registrars() -> None:
    cache = AccessTokenCache(ttl_seconds=300, max_entries=8)
    cams_mailbox = ("gmail:me", "mailbox-shared", "CAMS")
    kfintech_mailbox = ("gmail:me", "mailbox-shared", "KFINTECH")
    other_mailbox = ("gmail:me", "mailbox-other", "CAMS")

    await asyncio.gather(
        cache.put(cams_mailbox, "cams-oauth"),
        cache.put(kfintech_mailbox, "kfintech-oauth"),
        cache.put(other_mailbox, "other-oauth"),
    )
    tokens = await asyncio.gather(
        cache.get(cams_mailbox),
        cache.get(kfintech_mailbox),
        cache.get(other_mailbox),
    )
    assert tokens == ["cams-oauth", "kfintech-oauth", "other-oauth"]
