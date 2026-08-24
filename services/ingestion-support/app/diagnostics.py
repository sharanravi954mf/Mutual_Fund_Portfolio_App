from __future__ import annotations

import json
import logging
import re
import sys

LOGGER = logging.getLogger("moneybowl.ingestion_support")
HANDLER_NAME = "moneybowl.ingestion_support.stdout"
ERROR_CODE_RE = re.compile(r"^[a-z][a-z0-9_]{0,63}$")


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


def log_service_error(*, request_id: str, error_code: str, status: int) -> None:
    safe_code = error_code if ERROR_CODE_RE.fullmatch(error_code) is not None else "internal_error"
    _emit(
        {
            "event": "service_error",
            "request_id": request_id,
            "error_code": safe_code,
            "status": status,
        }
    )
