from __future__ import annotations

import json
import logging

import pytest
from conftest import (
    FakeMailboxProvider,
    FakeMalwareScanner,
    mailbox_headers,
    poll_body,
)
from fastapi.testclient import TestClient

from app.diagnostics import (
    HANDLER_NAME,
    LOGGER,
    DiagnosticReason,
    configure_application_logging,
)
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


def test_service_error_rejects_non_allowlisted_diagnostic_reason() -> None:
    with pytest.raises(TypeError, match="diagnostic_reason must be allowlisted"):
        ServiceError(
            502,
            "provider_response_too_large",
            diagnostic_reason="gmail_arbitrary_context",  # type: ignore[arg-type]
        )


@pytest.mark.parametrize(
    "diagnostic_reason",
    [
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_AUTH_REJECTED,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_NOT_FOUND,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_RATE_LIMITED,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_CLIENT_ERROR,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_SERVER_ERROR,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_STATUS_INVALID,
    ],
)
def test_cams_download_diagnostic_is_log_only_and_sanitized(
    settings,
    diagnostic_stream,
    diagnostic_reason: DiagnosticReason,
) -> None:
    provider = FakeMailboxProvider()
    provider.failure = ServiceError(
        502,
        "provider_request_failed",
        diagnostic_reason=diagnostic_reason,
    )
    app = create_app(settings, provider, FakeMalwareScanner())
    oauth_marker = "oauth-download-marker-must-not-appear"
    mailbox_marker = "mailbox-download-marker-must-not-appear"
    forbidden_provider_context = (
        "https://mailback12.camsonline.com/mailback_result/private.zip",
        "private-provider-response-body",
        "private-provider-response-header",
        "private-provider-cookie",
        "private-message-id",
        "private-attachment-id",
        "private-subject",
        "private-investor-data",
    )
    provider.sensitive_context = forbidden_provider_context

    with TestClient(app) as client:
        response = client.post(
            "/poll",
            headers={**mailbox_headers(settings), "X-Mailbox-OAuth-Token": oauth_marker},
            json=poll_body(mailbox_connection_id=mailbox_marker),
        )

    assert response.status_code == 502
    assert response.json() == {"error": {"code": "provider_request_failed"}}
    assert diagnostic_reason.value not in response.text
    service_error = next(
        event for event in _events(diagnostic_stream) if event["event"] == "service_error"
    )
    assert service_error == {
        "diagnostic_reason": diagnostic_reason.value,
        "error_code": "provider_request_failed",
        "event": "service_error",
        "request_id": response.headers["X-Request-ID"],
        "status": 502,
    }

    logs = diagnostic_stream.getvalue()
    for forbidden in (
        oauth_marker,
        mailbox_marker,
        settings.mailbox_connector_service_token,
        *forbidden_provider_context,
    ):
        assert forbidden not in logs


@pytest.mark.parametrize(
    "diagnostic_reason",
    [
        DiagnosticReason.GMAIL_DETAIL_ID_MISMATCH,
        DiagnosticReason.GMAIL_MESSAGE_SHAPE_INVALID,
        DiagnosticReason.GMAIL_MIME_PART_INVALID,
        DiagnosticReason.GMAIL_INLINE_BODY_INVALID,
        DiagnosticReason.CAMS_MAILBACK_BODY_DATA_SHAPE_INVALID,
        DiagnosticReason.CAMS_MAILBACK_BODY_DECLARED_SIZE_INVALID,
        DiagnosticReason.CAMS_MAILBACK_BODY_PADDING_INVALID,
        DiagnosticReason.CAMS_MAILBACK_BODY_BASE64_DECODE_INVALID,
        DiagnosticReason.CAMS_MAILBACK_BODY_EMPTY_INVALID,
        DiagnosticReason.CAMS_MAILBACK_TEXT_UTF8_INVALID,
        DiagnosticReason.CAMS_MAILBACK_HTML_INVALID,
        DiagnosticReason.CAMS_MAILBACK_REPORT_MISMATCH,
        DiagnosticReason.CAMS_MAILBACK_REQUIRED_FIELDS_INVALID,
        DiagnosticReason.CAMS_MAILBACK_NO_DATA_SHAPE_INVALID,
        DiagnosticReason.CAMS_MAILBACK_STATUS_INVALID,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_URL_MISSING,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_AUTH_REJECTED,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_NOT_FOUND,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_RATE_LIMITED,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_CLIENT_ERROR,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_SERVER_ERROR,
        DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_STATUS_INVALID,
        DiagnosticReason.CAMS_MAILBACK_MULTIPART_DISAGREEMENT,
        DiagnosticReason.GMAIL_DETAIL_RESULT_COUNT_MISMATCH,
    ],
)
def test_invalid_diagnostic_reason_is_log_only_and_sanitized(
    settings,
    diagnostic_stream,
    diagnostic_reason: DiagnosticReason,
) -> None:
    provider = FakeMailboxProvider()
    provider.failure = ServiceError(
        502,
        "provider_response_invalid",
        diagnostic_reason=diagnostic_reason,
    )
    app = create_app(settings, provider, FakeMalwareScanner())
    oauth_token = "oauth-token-must-not-appear"
    mailbox_id = "gmail-message-id-must-not-appear"
    forbidden_provider_context = (
        "attachment-id-must-not-appear",
        "sender-private@example.test",
        "recipient-private@example.test",
        "WBR2 private subject must not appear",
        "https://mailback12.camsonline.com/mailback_result/private.zip",
        "private-statement.dbf",
        "private-body-marker",
        "internal-token-must-not-appear",
    )
    provider.sensitive_context = forbidden_provider_context

    with TestClient(app) as client:
        response = client.post(
            "/poll",
            headers={**mailbox_headers(settings), "X-Mailbox-OAuth-Token": oauth_token},
            json=poll_body(mailbox_connection_id=mailbox_id),
        )

    assert response.status_code == 502
    assert response.json() == {"error": {"code": "provider_response_invalid"}}
    assert diagnostic_reason.value not in response.text

    events = _events(diagnostic_stream)
    service_error = next(event for event in events if event["event"] == "service_error")
    assert service_error == {
        "diagnostic_reason": diagnostic_reason.value,
        "error_code": "provider_response_invalid",
        "event": "service_error",
        "request_id": response.headers["X-Request-ID"],
        "status": 502,
    }

    logs = diagnostic_stream.getvalue()
    for forbidden in (
        oauth_token,
        mailbox_id,
        settings.mailbox_connector_service_token,
        *forbidden_provider_context,
    ):
        assert forbidden not in logs
