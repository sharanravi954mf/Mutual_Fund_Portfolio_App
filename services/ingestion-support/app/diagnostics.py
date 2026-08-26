from __future__ import annotations

import json
import logging
import re
import sys
from enum import StrEnum

LOGGER = logging.getLogger("moneybowl.ingestion_support")
HANDLER_NAME = "moneybowl.ingestion_support.stdout"
ERROR_CODE_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


class DiagnosticReason(StrEnum):
    GMAIL_LIST_RESPONSE_TOO_LARGE = "gmail_list_response_too_large"
    GMAIL_MESSAGE_DETAIL_RESPONSE_TOO_LARGE = "gmail_message_detail_response_too_large"
    GMAIL_ATTACHMENT_COUNT_EXCEEDED = "gmail_attachment_count_exceeded"
    GMAIL_DETAIL_ID_MISMATCH = "gmail_detail_id_mismatch"
    GMAIL_MESSAGE_SHAPE_INVALID = "gmail_message_shape_invalid"
    GMAIL_MIME_PART_INVALID = "gmail_mime_part_invalid"
    GMAIL_INLINE_BODY_INVALID = "gmail_inline_body_invalid"
    CAMS_MAILBACK_BODY_DATA_SHAPE_INVALID = "cams_mailback_body_data_shape_invalid"
    CAMS_MAILBACK_BODY_DECLARED_SIZE_INVALID = "cams_mailback_body_declared_size_invalid"
    CAMS_MAILBACK_BODY_PADDING_INVALID = "cams_mailback_body_padding_invalid"
    CAMS_MAILBACK_BODY_BASE64_DECODE_INVALID = "cams_mailback_body_base64_decode_invalid"
    CAMS_MAILBACK_BODY_EMPTY_INVALID = "cams_mailback_body_empty_invalid"
    CAMS_MAILBACK_TEXT_UTF8_INVALID = "cams_mailback_text_utf8_invalid"
    CAMS_MAILBACK_HTML_INVALID = "cams_mailback_html_invalid"
    CAMS_MAILBACK_REPORT_MISMATCH = "cams_mailback_report_mismatch"
    CAMS_MAILBACK_REQUIRED_FIELDS_INVALID = "cams_mailback_required_fields_invalid"
    CAMS_MAILBACK_NO_DATA_SHAPE_INVALID = "cams_mailback_no_data_shape_invalid"
    CAMS_MAILBACK_STATUS_INVALID = "cams_mailback_status_invalid"
    CAMS_MAILBACK_DOWNLOAD_URL_MISSING = "cams_mailback_download_url_missing"
    CAMS_MAILBACK_DOWNLOAD_AUTH_REJECTED = "cams_mailback_download_auth_rejected"
    CAMS_MAILBACK_DOWNLOAD_NOT_FOUND = "cams_mailback_download_not_found"
    CAMS_MAILBACK_DOWNLOAD_RATE_LIMITED = "cams_mailback_download_rate_limited"
    CAMS_MAILBACK_DOWNLOAD_CLIENT_ERROR = "cams_mailback_download_client_error"
    CAMS_MAILBACK_DOWNLOAD_SERVER_ERROR = "cams_mailback_download_server_error"
    CAMS_MAILBACK_DOWNLOAD_STATUS_INVALID = "cams_mailback_download_status_invalid"
    CAMS_MAILBACK_MULTIPART_DISAGREEMENT = "cams_mailback_multipart_disagreement"
    GMAIL_DETAIL_RESULT_COUNT_MISMATCH = "gmail_detail_result_count_mismatch"


def configure_application_logging() -> None:
    """Attach one explicit INFO JSON-lines handler for container diagnostics."""

    LOGGER.disabled = False
    LOGGER.setLevel(logging.INFO)
    LOGGER.propagate = False
    for handler in LOGGER.handlers:
        if handler.get_name() == HANDLER_NAME:
            handler.setLevel(logging.INFO)
            handler.setFormatter(logging.Formatter("%(message)s"))
            LOGGER.handlers = [handler]
            return

    handler = logging.StreamHandler(sys.stdout)
    handler.set_name(HANDLER_NAME)
    handler.setLevel(logging.INFO)
    handler.setFormatter(logging.Formatter("%(message)s"))
    LOGGER.handlers = [handler]


def _emit(payload: dict[str, str | int]) -> None:
    LOGGER.info(json.dumps(payload, separators=(",", ":"), sort_keys=True))


def log_http_request(
    *,
    request_id: str,
    method: str,
    route: str,
    status: int,
    duration_ms: int,
) -> None:
    _emit(
        {
            "event": "http_request",
            "request_id": request_id,
            "method": method[:16],
            "route": route,
            "status": status,
            "duration_ms": max(0, duration_ms),
        }
    )


def log_mailbox_poll_outcome(
    *,
    request_id: str,
    message_count: int,
    attachment_count: int,
) -> None:
    _emit(
        {
            "event": "mailbox_poll_outcome",
            "request_id": request_id,
            "message_count": max(0, message_count),
            "attachment_count": max(0, attachment_count),
        }
    )


def log_service_error(
    *,
    request_id: str,
    error_code: str,
    status: int,
    diagnostic_reason: DiagnosticReason | None = None,
) -> None:
    safe_code = error_code if ERROR_CODE_RE.fullmatch(error_code) is not None else "internal_error"
    payload: dict[str, str | int] = {
        "event": "service_error",
        "request_id": request_id,
        "error_code": safe_code,
        "status": status,
    }
    if isinstance(diagnostic_reason, DiagnosticReason):
        payload["diagnostic_reason"] = diagnostic_reason.value
    _emit(payload)
