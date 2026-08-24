from __future__ import annotations

import asyncio
import base64
import json

import httpx
import pytest
from conftest import FakeMailboxProvider, FakeMalwareScanner, mailbox_headers, poll_body
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.config import Settings
from app.errors import ServiceError
from app.mailbox import (
    GMAIL_MESSAGE_DETAIL_FIELDS,
    AccessTokenCache,
    FetchRequest,
    GmailProvider,
    InlineAttachmentCache,
    PollRequest,
    RefreshRequest,
)
from app.main import create_app


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


def gmail_inline_message(
    message_id: str,
    content: bytes,
    *,
    encoded: str | None = None,
) -> dict[str, object]:
    inline_data = encoded or base64.urlsafe_b64encode(content).decode().rstrip("=")
    return {
        "id": message_id,
        "internalDate": "1787392800000",
        "payload": {
            "headers": [
                {
                    "name": "From",
                    "value": "Statements <statements@example.test>",
                }
            ],
            "parts": [
                {
                    "filename": "",
                    "mimeType": "text/plain",
                    "body": {"data": "c3ludGhldGljIGJvZHk", "size": 14},
                },
                {
                    "filename": "synthetic-cams.dbf",
                    "mimeType": "application/octet-stream",
                    "body": {"data": inline_data, "size": len(content)},
                },
            ],
        },
    }


def gmail_nested_message(message_id: str) -> dict[str, object]:
    return {
        "id": message_id,
        "internalDate": "1787392800000",
        "payload": {
            "headers": [
                {
                    "name": "From",
                    "value": "Statements <statements@example.test>",
                }
            ],
            "mimeType": "multipart/mixed",
            "parts": [
                {
                    "mimeType": "multipart/alternative",
                    "parts": [
                        {
                            "filename": "",
                            "mimeType": "text/plain",
                            "body": {"data": "c3ludGhldGljIGJvZHk", "size": 14},
                        }
                    ],
                },
                {
                    "mimeType": "multipart/mixed",
                    "parts": [
                        {
                            "filename": "nested-cams.dbf",
                            "mimeType": "application/octet-stream",
                            "body": {
                                "attachmentId": f"nested-attachment-{message_id}",
                                "size": 618,
                            },
                        }
                    ],
                },
            ],
        },
    }


async def controlled_delayed_gmail_poll(
    settings,
    concurrency: int,
    message_ids: list[str],
) -> tuple[int, int, list[str]]:
    """Run a poll in deterministic delay waves without wall-clock assertions."""

    limited = settings.model_copy(
        update={
            "max_mailbox_messages": len(message_ids),
            "max_mailbox_pages_per_poll": 1,
            "max_mailbox_candidates_per_poll": len(message_ids),
            "gmail_detail_fetch_concurrency": concurrency,
        }
    )
    current_gate = asyncio.Event()
    started: asyncio.Queue[str] = asyncio.Queue()
    finished: asyncio.Queue[str] = asyncio.Queue()
    active = 0
    max_active = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal active, max_active
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": item} for item in message_ids]})

        message_id = request.url.path.rsplit("/", 1)[-1]
        assert request.url.params["fields"] == GMAIL_MESSAGE_DETAIL_FIELDS
        gate = current_gate
        active += 1
        max_active = max(max_active, active)
        await started.put(message_id)
        try:
            await gate.wait()
        finally:
            active -= 1
        await finished.put(message_id)
        return httpx.Response(200, json=gmail_message(message_id))

    provider = GmailProvider(limited, httpx.MockTransport(handler))
    poll_task = asyncio.create_task(
        provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "controlled-delay-oauth-token",
        )
    )
    delay_rounds = 0
    remaining = len(message_ids)
    try:
        while remaining:
            wave_size = min(concurrency, remaining)
            for _request in range(wave_size):
                await started.get()

            next_gate = asyncio.Event()
            released_gate = current_gate
            current_gate = next_gate
            released_gate.set()
            for _request in range(wave_size):
                await finished.get()

            delay_rounds += 1
            remaining -= wave_size

        messages = await poll_task
        assert active == 0
        return delay_rounds, max_active, [message.message_id for message in messages]
    finally:
        if not poll_task.done():
            poll_task.cancel()
            await asyncio.gather(poll_task, return_exceptions=True)
        await provider.close()


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
        httpx.MockTransport(
            lambda _request: httpx.Response(302, headers={"Location": "https://evil.test"})
        ),
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
            assert request.url.params["format"] == "full"
            assert request.url.params["fields"] == GMAIL_MESSAGE_DETAIL_FIELDS
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
async def test_gmail_detail_partial_response_omits_large_unneeded_message_data(settings) -> None:
    generic_limit = settings.max_provider_response_bytes
    limited = settings.model_copy(update={"max_gmail_message_detail_response_bytes": generic_limit})
    full_response = {
        **gmail_message("partialMessage"),
        "threadId": "unused-thread-id",
        "labelIds": ["UNUSED"],
        "snippet": "irrelevant-provider-content-" + "x" * generic_limit,
        "historyId": "123456789",
        "sizeEstimate": generic_limit * 2,
        "classificationLabelValues": [{"id": "unused-classification"}],
    }
    assert len(json.dumps(full_response).encode()) > generic_limit
    returned_lengths: list[int] = []

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": "partialMessage"}]})
        assert request.url.params["format"] == "full"
        assert request.url.params["fields"] == GMAIL_MESSAGE_DETAIL_FIELDS
        assert "snippet" not in request.url.params["fields"]
        assert "labelIds" not in request.url.params["fields"]
        partial_response = gmail_message("partialMessage")
        encoded = json.dumps(partial_response).encode()
        returned_lengths.append(len(encoded))
        return httpx.Response(200, content=encoded, headers={"Content-Type": "application/json"})

    provider = GmailProvider(limited, httpx.MockTransport(handler))
    messages = await provider.poll(
        PollRequest(
            connector_ref="gmail:me",
            mailbox_connection_id="mailbox-fixture-1",
            registrar="CAMS",
        ),
        "partial-response-oauth-token",
    )
    await provider.close()

    assert returned_lengths and returned_lengths[0] < generic_limit
    assert [message.message_id for message in messages] == ["partialMessage"]


@pytest.mark.asyncio
async def test_gmail_detail_partial_response_preserves_nested_mime_parts(settings) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": "nestedMessage"}]})
        assert request.url.params["fields"] == GMAIL_MESSAGE_DETAIL_FIELDS
        return httpx.Response(200, json=gmail_nested_message("nestedMessage"))

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    messages = await provider.poll(
        PollRequest(
            connector_ref="gmail:me",
            mailbox_connection_id="mailbox-fixture-1",
            registrar="CAMS",
        ),
        "nested-message-oauth-token",
    )
    await provider.close()

    assert len(messages) == 1
    assert messages[0].sender_address == "statements@example.test"
    assert len(messages[0].attachments) == 1
    assert messages[0].attachments[0].attachment_id == "nested-attachment-nestedMessage"
    assert messages[0].attachments[0].filename == "nested-cams.dbf"


@pytest.mark.asyncio
async def test_gmail_detail_fetch_is_bounded_ordered_and_faster_than_serial(settings) -> None:
    message_ids = [f"orderedMessage{index}" for index in range(6)]

    serial_rounds, serial_max_active, serial_order = await controlled_delayed_gmail_poll(
        settings,
        1,
        message_ids,
    )
    (
        concurrent_rounds,
        concurrent_max_active,
        concurrent_order,
    ) = await controlled_delayed_gmail_poll(
        settings,
        3,
        message_ids,
    )

    assert serial_rounds == 6
    assert serial_max_active == 1
    assert concurrent_rounds == 2
    assert concurrent_max_active == 3
    assert serial_order == message_ids
    assert concurrent_order == message_ids


@pytest.mark.asyncio
async def test_gmail_concurrent_details_preserve_listing_order_after_reverse_completion(
    settings,
) -> None:
    message_ids = ["listedFirst", "listedSecond", "listedThird"]
    release = {message_id: asyncio.Event() for message_id in message_ids}
    started: asyncio.Queue[str] = asyncio.Queue()
    completed: asyncio.Queue[str] = asyncio.Queue()

    async def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": item} for item in message_ids]})
        message_id = request.url.path.rsplit("/", 1)[-1]
        await started.put(message_id)
        await release[message_id].wait()
        await completed.put(message_id)
        return httpx.Response(200, json=gmail_message(message_id))

    limited = settings.model_copy(
        update={
            "max_mailbox_messages": 3,
            "max_mailbox_pages_per_poll": 1,
            "max_mailbox_candidates_per_poll": 3,
            "gmail_detail_fetch_concurrency": 3,
        }
    )
    provider = GmailProvider(limited, httpx.MockTransport(handler))
    poll_task = asyncio.create_task(
        provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "reverse-completion-oauth-token",
        )
    )
    try:
        for _message_id in message_ids:
            await started.get()
        completion_order: list[str] = []
        for message_id in reversed(message_ids):
            release[message_id].set()
            completion_order.append(await completed.get())

        messages = await poll_task
        assert completion_order == list(reversed(message_ids))
        assert [message.message_id for message in messages] == message_ids
    finally:
        if not poll_task.done():
            poll_task.cancel()
            await asyncio.gather(poll_task, return_exceptions=True)
        await provider.close()


@pytest.mark.asyncio
async def test_gmail_detail_failure_cancels_and_awaits_sibling_workers(settings) -> None:
    limited = settings.model_copy(
        update={
            "max_mailbox_messages": 3,
            "max_mailbox_pages_per_poll": 1,
            "max_mailbox_candidates_per_poll": 3,
            "gmail_detail_fetch_concurrency": 3,
        }
    )
    all_started = asyncio.Event()
    never_release = asyncio.Event()
    started = 0
    active = 0
    cancelled: set[str] = set()

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal active, started
        if request.url.path.endswith("/messages"):
            return httpx.Response(
                200,
                json={
                    "messages": [
                        {"id": "failedDetail"},
                        {"id": "cancelledDetail1"},
                        {"id": "cancelledDetail2"},
                    ]
                },
            )

        message_id = request.url.path.rsplit("/", 1)[-1]
        active += 1
        started += 1
        if started == 3:
            all_started.set()
        try:
            await all_started.wait()
            if message_id == "failedDetail":
                return httpx.Response(503)
            try:
                await never_release.wait()
            except asyncio.CancelledError:
                cancelled.add(message_id)
                raise
            return httpx.Response(200, json=gmail_message(message_id))
        finally:
            active -= 1

    provider = GmailProvider(limited, httpx.MockTransport(handler))
    with pytest.raises(ServiceError, match="provider_request_failed"):
        await provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "failure-cancellation-oauth-token",
        )
    await provider.close()

    assert active == 0
    assert cancelled == {"cancelledDetail1", "cancelledDetail2"}


@pytest.mark.asyncio
async def test_gmail_poll_rejects_duplicate_listing_ids_before_detail_fetch(settings) -> None:
    detail_calls = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal detail_calls
        if request.url.path.endswith("/messages"):
            return httpx.Response(
                200,
                json={"messages": [{"id": "duplicateMessage"}, {"id": "duplicateMessage"}]},
            )
        detail_calls += 1
        return httpx.Response(200, json=gmail_message("duplicateMessage"))

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        await provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "duplicate-listing-oauth-token",
        )
    await provider.close()
    assert detail_calls == 0


@pytest.mark.asyncio
async def test_gmail_poll_rejects_malformed_concurrent_detail_response(settings) -> None:
    limited = settings.model_copy(update={"gmail_detail_fetch_concurrency": 2})

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(
                200,
                json={"messages": [{"id": "validDetail"}, {"id": "malformedDetail"}]},
            )
        message_id = request.url.path.rsplit("/", 1)[-1]
        if message_id == "malformedDetail":
            return httpx.Response(200, json={"id": message_id})
        return httpx.Response(200, json=gmail_message(message_id))

    provider = GmailProvider(limited, httpx.MockTransport(handler))
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        await provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "malformed-detail-oauth-token",
        )
    await provider.close()


@pytest.mark.parametrize("invalid_concurrency", ["0", "11"])
def test_gmail_detail_fetch_concurrency_configuration_is_bounded(
    monkeypatch,
    invalid_concurrency: str,
) -> None:
    monkeypatch.setenv("GMAIL_DETAIL_FETCH_CONCURRENCY", invalid_concurrency)
    with pytest.raises(ValidationError, match="GMAIL_DETAIL_FETCH_CONCURRENCY"):
        Settings()


@pytest.mark.parametrize("invalid_limit", ["1048575", "4194305"])
def test_gmail_message_detail_response_limit_configuration_is_bounded(
    monkeypatch,
    invalid_limit: str,
) -> None:
    monkeypatch.setenv("MAX_GMAIL_MESSAGE_DETAIL_RESPONSE_BYTES", invalid_limit)
    with pytest.raises(ValidationError, match="MAX_GMAIL_MESSAGE_DETAIL_RESPONSE_BYTES"):
        Settings()


def test_gmail_message_detail_limit_cannot_be_below_generic_provider_limit(monkeypatch) -> None:
    monkeypatch.setenv("MAX_PROVIDER_RESPONSE_BYTES", "2097152")
    monkeypatch.setenv("MAX_GMAIL_MESSAGE_DETAIL_RESPONSE_BYTES", "1048576")
    with pytest.raises(
        ValidationError,
        match="MAX_GMAIL_MESSAGE_DETAIL_RESPONSE_BYTES must be greater than or equal to",
    ):
        Settings()


def test_oversized_required_gmail_detail_fails_closed_without_logging_provider_content(
    settings,
    diagnostic_stream,
) -> None:
    detail_limit = 1_048_576
    limited = settings.model_copy(update={"max_gmail_message_detail_response_bytes": detail_limit})
    oauth_token = "oversized-detail-oauth-token"
    message_id = "oversizedProviderMessage"
    filename = "provider-filename-must-not-be-logged.dbf"
    content_marker = "required-provider-content-marker"
    required_data = content_marker + "A" * detail_limit

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["Authorization"] == f"Bearer {oauth_token}"
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": message_id}]})
        assert request.url.params["fields"] == GMAIL_MESSAGE_DETAIL_FIELDS
        return httpx.Response(
            200,
            json={
                "id": message_id,
                "internalDate": "1787392800000",
                "payload": {
                    "headers": [
                        {
                            "name": "From",
                            "value": "private-sender@example.test",
                        }
                    ],
                    "parts": [
                        {
                            "filename": filename,
                            "mimeType": "application/octet-stream",
                            "body": {
                                "data": required_data,
                                "size": 786_432,
                            },
                        }
                    ],
                },
            },
        )

    app = create_app(
        limited, GmailProvider(limited, httpx.MockTransport(handler)), FakeMalwareScanner()
    )
    with TestClient(app) as client:
        response = client.post(
            "/poll",
            headers={
                **mailbox_headers(limited),
                "X-Mailbox-OAuth-Token": oauth_token,
            },
            json=poll_body(),
        )

    assert response.status_code == 502
    assert response.json() == {"error": {"code": "provider_response_too_large"}}
    logs = diagnostic_stream.getvalue()
    assert '"error_code":"provider_response_too_large"' in logs
    for forbidden in (
        oauth_token,
        message_id,
        filename,
        content_marker,
        "private-sender@example.test",
    ):
        assert forbidden not in logs


def test_inline_gmail_dbf_poll_metadata_and_fetch_contract(settings) -> None:
    inline_content = b"\x03" + b"\x00" * 617
    encoded_inline = base64.urlsafe_b64encode(inline_content).decode().rstrip("=")
    oauth_token = "inline-worker-oauth-token"
    message_requests = 0

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal message_requests
        assert request.headers["Authorization"] == f"Bearer {oauth_token}"
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": "inlineDbfMessage"}]})
        if request.url.path.endswith("/messages/inlineDbfMessage"):
            message_requests += 1
            assert request.url.params["format"] == "full"
            assert request.url.params["fields"] == GMAIL_MESSAGE_DETAIL_FIELDS
            return httpx.Response(
                200,
                json=gmail_inline_message("inlineDbfMessage", inline_content),
            )
        return httpx.Response(404)

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    app = create_app(settings, provider, FakeMalwareScanner())
    headers = mailbox_headers(settings)
    with TestClient(app) as client:
        poll = client.post(
            "/poll",
            headers={**headers, "X-Mailbox-OAuth-Token": oauth_token},
            json=poll_body(),
        )
        assert poll.status_code == 200
        response_body = poll.json()
        attachments = response_body["messages"][0]["attachments"]
        assert len(attachments) == 1
        assert attachments[0]["filename"] == "synthetic-cams.dbf"
        assert attachments[0]["declared_mime"] == "application/octet-stream"
        inline_attachment_id = attachments[0]["attachment_id"]
        assert inline_attachment_id.startswith("inline:")
        assert len(inline_attachment_id) == 71
        assert encoded_inline not in poll.text
        assert oauth_token not in poll.text

        repeated_poll = client.post(
            "/poll",
            headers={**headers, "X-Mailbox-OAuth-Token": oauth_token},
            json=poll_body(),
        )
        assert repeated_poll.status_code == 200
        assert (
            repeated_poll.json()["messages"][0]["attachments"][0]["attachment_id"]
            == inline_attachment_id
        )

        unissued = client.post(
            "/attachments/fetch",
            headers=headers,
            json={
                **poll_body(),
                "message_id": "inlineDbfMessage",
                "attachment_id": "inline:" + "0" * 64,
            },
        )
        assert unissued.status_code == 409
        assert unissued.json() == {"error": {"code": "inline_attachment_context_required"}}

        fetched = client.post(
            "/attachments/fetch",
            headers=headers,
            json={
                **poll_body(),
                "message_id": "inlineDbfMessage",
                "attachment_id": inline_attachment_id,
            },
        )
        assert fetched.status_code == 200
        assert fetched.content == inline_content
        assert fetched.headers["content-type"] == "application/octet-stream"

    assert message_requests == 3


@pytest.mark.parametrize("malformed", ["not+gmail/base64url", "c3ludGhldGlj="])
@pytest.mark.asyncio
async def test_gmail_poll_rejects_malformed_inline_base64url(settings, malformed) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": "malformedInline"}]})
        return httpx.Response(
            200,
            json=gmail_inline_message(
                "malformedInline",
                b"synthetic",
                encoded=malformed,
            ),
        )

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        await provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "malformed-inline-oauth-token",
        )
    await provider.close()


@pytest.mark.asyncio
async def test_gmail_poll_rejects_oversized_inline_content(settings) -> None:
    limited = settings.model_copy(update={"max_attachment_bytes": 1024})
    oversized = b"x" * 1025

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": "oversizedInline"}]})
        return httpx.Response(
            200,
            json=gmail_inline_message("oversizedInline", oversized),
        )

    provider = GmailProvider(limited, httpx.MockTransport(handler))
    with pytest.raises(ServiceError, match="provider_response_too_large"):
        await provider.poll(
            PollRequest(
                connector_ref="gmail:me",
                mailbox_connection_id="mailbox-fixture-1",
                registrar="CAMS",
            ),
            "oversized-inline-oauth-token",
        )
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
    settings, diagnostic_stream, later_failure: str, expected_code: str
) -> None:
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
    assert oauth_token not in diagnostic_stream.getvalue()


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


def test_mailbox_provider_tokens_are_not_logged(client, settings, diagnostic_stream) -> None:
    secret_oauth = "oauth-value-that-must-never-be-logged"
    client.post(
        "/poll",
        headers={**mailbox_headers(settings), "X-Mailbox-OAuth-Token": secret_oauth},
        json=poll_body(),
    )
    assert secret_oauth not in diagnostic_stream.getvalue()
    assert settings.mailbox_connector_service_token not in diagnostic_stream.getvalue()


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


@pytest.mark.asyncio
async def test_inline_attachment_cache_expiry_and_lru_eviction_fail_closed(
    monkeypatch,
) -> None:
    now = 100.0
    monkeypatch.setattr("app.mailbox.time.monotonic", lambda: now)
    cache = InlineAttachmentCache(ttl_seconds=5, max_entries=2)
    first = ("gmail:me", "mailbox-1", "CAMS", "message-1", "inline:" + "1" * 64)
    second = ("gmail:me", "mailbox-2", "CAMS", "message-2", "inline:" + "2" * 64)
    third = ("gmail:me", "mailbox-3", "CAMS", "message-3", "inline:" + "3" * 64)

    await cache.put_many([(first, 1), (second, 2)])
    assert await cache.get(first) == 1
    await cache.put_many([(third, 3)])

    with pytest.raises(ServiceError, match="inline_attachment_context_required"):
        await cache.get(second)
    assert await cache.get(first) == 1
    assert await cache.get(third) == 3

    now = 106.0
    with pytest.raises(ServiceError, match="inline_attachment_context_required"):
        await cache.get(first)
