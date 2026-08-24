from __future__ import annotations

import json
import logging

from conftest import (
    FakeMailboxProvider,
    FakeMalwareScanner,
    mailbox_headers,
    poll_body,
)
from fastapi.testclient import TestClient

from app.diagnostics import HANDLER_NAME, LOGGER, configure_application_logging
from app.errors import ServiceError
from app.mailbox import PollRequest
from app.main import create_app


def _events(diagnostic_stream) -> list[dict[str, object]]:
    return [json.loads(line) for line in diagnostic_stream.getvalue().splitlines() if line]


def test_application_logger_has_one_explicit_info_stdout_handler() -> None:
    configure_application_logging()
    configure_application_logging()

    handlers = [handler for handler in LOGGER.handlers if handler.get_name() == HANDLER_NAME]
    assert len(handlers) == 1
    assert LOGGER.handlers == handlers
    assert LOGGER.level == logging.INFO
    assert handlers[0].level == logging.INFO
    assert handlers[0].formatter is not None
    assert handlers[0].formatter._fmt == "%(message)s"
    assert LOGGER.propagate is False


def test_poll_emits_safe_outcome_and_request_events(settings, diagnostic_stream) -> None:
    provider = FakeMailboxProvider()
    app = create_app(settings, provider, FakeMalwareScanner())
    oauth_marker = "oauth-marker-that-must-not-appear"
    body_marker = "body-marker-that-must-not-appear"

    with TestClient(app) as client:
        response = client.post(
            "/poll",
            headers={**mailbox_headers(settings), "X-Mailbox-OAuth-Token": oauth_marker},
            json=poll_body(mailbox_connection_id=body_marker),
        )

    assert response.status_code == 200
    events = _events(diagnostic_stream)
    assert [event["event"] for event in events] == ["mailbox_poll_outcome", "http_request"]
    outcome = next(event for event in events if event["event"] == "mailbox_poll_outcome")
    request = next(event for event in events if event["event"] == "http_request")
    assert outcome == {
        "attachment_count": 1,
        "event": "mailbox_poll_outcome",
        "message_count": 1,
        "request_id": response.headers["X-Request-ID"],
    }
    assert request == {
        "duration_ms": request["duration_ms"],
        "event": "http_request",
        "method": "POST",
        "request_id": response.headers["X-Request-ID"],
        "route": "/poll",
        "status": 200,
    }
    assert isinstance(request["duration_ms"], int)

    logs = diagnostic_stream.getvalue()
    for forbidden in (
        oauth_marker,
        body_marker,
        settings.mailbox_connector_service_token,
        "gmail-message-1",
        "gmail-attachment-1",
        "synthetic-cams.pdf",
        "statements@example.test",
    ):
        assert forbidden not in logs


def test_successful_empty_poll_is_distinguishable(settings, diagnostic_stream) -> None:
    class EmptyMailboxProvider(FakeMailboxProvider):
        async def poll(self, request: PollRequest, access_token: str):
            self.access_tokens.append(access_token)
            return []

    app = create_app(settings, EmptyMailboxProvider(), FakeMalwareScanner())
    with TestClient(app) as client:
        response = client.post(
            "/poll",
            headers={
                **mailbox_headers(settings),
                "X-Mailbox-OAuth-Token": "empty-poll-oauth-marker",
            },
            json=poll_body(),
        )

    assert response.status_code == 200
    assert response.json() == {"messages": []}
    events = _events(diagnostic_stream)
    assert [event["event"] for event in events] == ["mailbox_poll_outcome", "http_request"]
    outcome = events[0]
    assert outcome["message_count"] == 0
    assert outcome["attachment_count"] == 0


def test_service_error_logs_only_code_status_and_request_id(
    settings,
    diagnostic_stream,
) -> None:
    provider = FakeMailboxProvider()
    provider.failure = ServiceError(503, "provider_unavailable")
    app = create_app(settings, provider, FakeMalwareScanner())
    oauth_marker = "failed-poll-oauth-marker"
    body_marker = "failed-body-marker"

    with TestClient(app) as client:
        response = client.post(
            "/poll",
            headers={**mailbox_headers(settings), "X-Mailbox-OAuth-Token": oauth_marker},
            json=poll_body(mailbox_connection_id=body_marker),
        )

    assert response.status_code == 503
    assert response.json() == {"error": {"code": "provider_unavailable"}}
    events = _events(diagnostic_stream)
    assert [event["event"] for event in events] == ["service_error", "http_request"]
    service_error = next(event for event in events if event["event"] == "service_error")
    assert service_error == {
        "error_code": "provider_unavailable",
        "event": "service_error",
        "request_id": response.headers["X-Request-ID"],
        "status": 503,
    }
    assert not any(event["event"] == "mailbox_poll_outcome" for event in events)
    request = next(event for event in events if event["event"] == "http_request")
    assert request["status"] == 503

    logs = diagnostic_stream.getvalue()
    assert oauth_marker not in logs
    assert body_marker not in logs
    assert "ServiceError" not in logs
    assert "Traceback" not in logs
