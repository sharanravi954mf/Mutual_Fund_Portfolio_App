from __future__ import annotations

import asyncio
import json
import logging

import httpx
import pytest

from app.errors import ServiceError
from app.mailbox import FetchRequest, GmailProvider, PollRequest, RefreshRequest
from conftest import FakeMailboxProvider, mailbox_headers, poll_body


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
            return httpx.Response(200, json={"messages": [{"id": "gmailMessage1"}]})
        if path.endswith("/messages/gmailMessage1"):
            return httpx.Response(
                200,
                json={
                    "id": "gmailMessage1",
                    "internalDate": "1787392800000",
                    "payload": {
                        "headers": [{"name": "From", "value": "Statements <statements@example.test>"}],
                        "parts": [
                            {
                                "filename": "synthetic.pdf",
                                "mimeType": "application/pdf",
                                "body": {"attachmentId": "gmailAttachment1"},
                            }
                        ],
                    },
                },
            )
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
