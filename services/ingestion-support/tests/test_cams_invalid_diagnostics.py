from __future__ import annotations

import base64
from pathlib import Path

import httpx
import pytest

import app.cams_mailback as cams_mailback_module
from app.cams_mailback import parse_cams_mailback, required_html_text
from app.diagnostics import DiagnosticReason
from app.errors import ServiceError
from app.mailbox import GmailProvider

FIXTURES = Path(__file__).parent / "fixtures"
CAMS_URL = "https://mailback12.camsonline.com/mailback_result/synthetic-wbr2.zip"


def _assert_invalid_reason(
    expected: DiagnosticReason,
    operation,
) -> None:
    with pytest.raises(ServiceError, match="provider_response_invalid") as caught:
        operation()

    assert caught.value.status_code == 502
    assert caught.value.code == "provider_response_invalid"
    assert caught.value.diagnostic_reason is expected


def _encoded_part(
    content: bytes,
    mime_type: str,
    *,
    declared_size: int | None = None,
) -> dict[str, object]:
    return {
        "filename": "",
        "mimeType": mime_type,
        "body": {
            "data": base64.urlsafe_b64encode(content).decode().rstrip("="),
            "size": len(content) if declared_size is None else declared_size,
        },
    }


def _gmail_message(*, message_id: str = "validMessage") -> dict[str, object]:
    return {
        "id": message_id,
        "internalDate": "1787392800000",
        "payload": {"headers": [], "parts": []},
    }


@pytest.mark.asyncio
async def test_gmail_detail_id_mismatch_has_exact_diagnostic(settings) -> None:
    provider = GmailProvider(
        settings,
        httpx.MockTransport(
            lambda _request: httpx.Response(
                200,
                json=_gmail_message(message_id="differentDetailId"),
            )
        ),
    )

    with pytest.raises(ServiceError, match="provider_response_invalid") as caught:
        await provider._fetch_page_message_details(
            ["listedMessageId"],
            "me",
            {"Authorization": "Bearer diagnostic-test-token"},
            "KFINTECH",
        )
    await provider.close()

    assert caught.value.diagnostic_reason is DiagnosticReason.GMAIL_DETAIL_ID_MISMATCH


def test_gmail_detail_result_count_mismatch_has_exact_diagnostic() -> None:
    _assert_invalid_reason(
        DiagnosticReason.GMAIL_DETAIL_RESULT_COUNT_MISMATCH,
        lambda: GmailProvider._ordered_detail_results({}, 1),
    )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("mutate", "expected_reason"),
    [
        (
            lambda raw: raw.pop("payload"),
            DiagnosticReason.GMAIL_MESSAGE_SHAPE_INVALID,
        ),
        (
            lambda raw: raw["payload"]["parts"].append(
                {
                    "filename": "private-statement.dbf",
                    "mimeType": "application/octet-stream",
                    "body": {"attachmentId": "invalid attachment id", "size": 10},
                }
            ),
            DiagnosticReason.GMAIL_MIME_PART_INVALID,
        ),
        (
            lambda raw: raw["payload"]["parts"].append(
                {
                    "filename": "private-statement.dbf",
                    "mimeType": "application/octet-stream",
                    "body": {"data": "not+base64url", "size": 10},
                }
            ),
            DiagnosticReason.GMAIL_INLINE_BODY_INVALID,
        ),
    ],
    ids=["message-shape", "mime-part", "inline-body"],
)
async def test_gmail_message_validation_stages_have_exact_diagnostics(
    settings,
    mutate,
    expected_reason: DiagnosticReason,
) -> None:
    provider = GmailProvider(settings)
    raw = _gmail_message()
    mutate(raw)

    _assert_invalid_reason(
        expected_reason,
        lambda: provider._message_from_gmail(raw, "KFINTECH"),
    )
    await provider.close()


@pytest.mark.asyncio
@pytest.mark.parametrize("encoded", [123, "not+base64url"], ids=["non-string", "invalid-char"])
async def test_cams_body_data_shape_failures_have_exact_diagnostic(
    settings,
    encoded: object,
) -> None:
    provider = GmailProvider(settings)
    payload = {
        "headers": [],
        "parts": [
            {
                "filename": "",
                "mimeType": "text/html",
                "body": {"data": encoded, "size": 10},
            }
        ],
    }

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_BODY_DATA_SHAPE_INVALID,
        lambda: provider._parse_cams_mailback_payload(payload, "CAMS WBR2 mailback"),
    )
    await provider.close()


@pytest.mark.asyncio
@pytest.mark.parametrize("declared_size", [True, -1], ids=["invalid-type", "negative"])
async def test_cams_body_declared_size_failures_have_exact_diagnostic(
    settings,
    declared_size: object,
) -> None:
    provider = GmailProvider(settings)
    payload = {
        "headers": [],
        "parts": [
            {
                "filename": "",
                "mimeType": "text/plain",
                "body": {
                    "data": base64.urlsafe_b64encode(b"valid UTF-8").decode().rstrip("="),
                    "size": declared_size,
                },
            }
        ],
    }

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_BODY_DECLARED_SIZE_INVALID,
        lambda: provider._parse_cams_mailback_payload(payload, "CAMS WBR2 mailback"),
    )
    await provider.close()


@pytest.mark.asyncio
@pytest.mark.parametrize("encoded", ["A", "AA="], ids=["impossible-length", "bad-padding"])
async def test_cams_body_padding_failures_have_exact_diagnostic(
    settings,
    encoded: str,
) -> None:
    provider = GmailProvider(settings)
    payload = {
        "headers": [],
        "parts": [
            {
                "filename": "",
                "mimeType": "text/plain",
                "body": {"data": encoded, "size": 1},
            }
        ],
    }

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_BODY_PADDING_INVALID,
        lambda: provider._parse_cams_mailback_payload(payload, "CAMS WBR2 mailback"),
    )
    await provider.close()


@pytest.mark.asyncio
async def test_cams_body_strict_base64_failure_has_exact_diagnostic(
    settings,
    monkeypatch,
) -> None:
    provider = GmailProvider(settings)
    payload = {
        "headers": [],
        "parts": [_encoded_part(b"valid UTF-8", "text/plain")],
    }

    def reject_decode(*_args, **_kwargs) -> bytes:
        raise base64.binascii.Error("synthetic strict decode failure")

    monkeypatch.setattr(base64, "b64decode", reject_decode)

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_BODY_BASE64_DECODE_INVALID,
        lambda: provider._parse_cams_mailback_payload(payload, "CAMS WBR2 mailback"),
    )
    await provider.close()


@pytest.mark.asyncio
async def test_cams_body_decoded_empty_has_exact_diagnostic(settings, monkeypatch) -> None:
    provider = GmailProvider(settings)
    payload = {
        "headers": [],
        "parts": [_encoded_part(b"valid UTF-8", "text/plain")],
    }

    monkeypatch.setattr(base64, "b64decode", lambda *_args, **_kwargs: b"")

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_BODY_EMPTY_INVALID,
        lambda: provider._parse_cams_mailback_payload(payload, "CAMS WBR2 mailback"),
    )
    await provider.close()


@pytest.mark.asyncio
async def test_cams_body_decoded_size_mismatch_has_exact_diagnostic(settings) -> None:
    provider = GmailProvider(settings)
    payload = {
        "headers": [],
        "parts": [_encoded_part(b"valid UTF-8", "text/plain", declared_size=1)],
    }

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_BODY_SIZE_MISMATCH,
        lambda: provider._parse_cams_mailback_payload(payload, "CAMS WBR2 mailback"),
    )
    await provider.close()


@pytest.mark.asyncio
async def test_valid_base64url_with_invalid_utf8_has_text_diagnostic(settings) -> None:
    provider = GmailProvider(settings)
    invalid_utf8 = b"\xff\xfe"
    payload = {
        "headers": [],
        "parts": [_encoded_part(invalid_utf8, "text/plain")],
    }

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_TEXT_UTF8_INVALID,
        lambda: provider._parse_cams_mailback_payload(payload, "CAMS WBR2 mailback"),
    )
    await provider.close()


def test_cams_html_failure_has_exact_diagnostic(monkeypatch) -> None:
    def fail_feed(_self, _value: str) -> None:
        raise ValueError("synthetic parser failure")

    monkeypatch.setattr(cams_mailback_module._RequiredHtmlText, "feed", fail_feed)

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_HTML_INVALID,
        lambda: required_html_text("<html></html>"),
    )


@pytest.mark.parametrize(
    ("subject", "body_text", "expected_reason"),
    [
        (
            "CAMS WBR9 mailback",
            "\n".join(
                (
                    "DownloadURL",
                    CAMS_URL,
                    "Request Status",
                    "Link",
                    "File Type",
                    "DBF",
                    "Report No",
                    "WBR2",
                )
            ),
            DiagnosticReason.CAMS_MAILBACK_REPORT_MISMATCH,
        ),
        (
            "CAMS WBR2 mailback",
            "\n".join(
                (
                    "DownloadURL",
                    CAMS_URL,
                    "Request Status",
                    "Link",
                    "File Type",
                    "CSV",
                    "Report No",
                    "WBR2",
                )
            ),
            DiagnosticReason.CAMS_MAILBACK_REQUIRED_FIELDS_INVALID,
        ),
        (
            "CAMS WBR2 mailback",
            "\n".join(
                (
                    "DownloadURL",
                    CAMS_URL,
                    "Request Status",
                    "No Data",
                    "File Type",
                    "DBF",
                    "Report No",
                    "WBR2",
                )
            ),
            DiagnosticReason.CAMS_MAILBACK_NO_DATA_SHAPE_INVALID,
        ),
        (
            "CAMS WBR2 mailback",
            "\n".join(
                (
                    "DownloadURL",
                    CAMS_URL,
                    "Request Status",
                    "Completed",
                    "File Type",
                    "DBF",
                    "Report No",
                    "WBR2",
                )
            ),
            DiagnosticReason.CAMS_MAILBACK_STATUS_INVALID,
        ),
        (
            "CAMS WBR2 mailback",
            "\n".join(
                (
                    "Request Status",
                    "Link",
                    "File Type",
                    "DBF",
                    "Report No",
                    "WBR2",
                )
            ),
            DiagnosticReason.CAMS_MAILBACK_DOWNLOAD_URL_MISSING,
        ),
    ],
    ids=[
        "report-mismatch",
        "required-fields",
        "no-data-shape",
        "status",
        "download-url-missing",
    ],
)
def test_cams_field_validation_stages_have_exact_diagnostics(
    subject: str,
    body_text: str,
    expected_reason: DiagnosticReason,
) -> None:
    _assert_invalid_reason(
        expected_reason,
        lambda: parse_cams_mailback(subject=subject, body_text=body_text),
    )


@pytest.mark.asyncio
async def test_cams_multipart_disagreement_has_exact_diagnostic(settings) -> None:
    provider = GmailProvider(settings)
    supported = (FIXTURES / "cams_wbr2_mailback.html").read_bytes()
    no_data = (FIXTURES / "cams_wbr2_no_data.html").read_bytes()
    payload = {
        "headers": [],
        "parts": [
            _encoded_part(supported, "text/html"),
            _encoded_part(no_data, "text/html"),
        ],
    }

    _assert_invalid_reason(
        DiagnosticReason.CAMS_MAILBACK_MULTIPART_DISAGREEMENT,
        lambda: provider._parse_cams_mailback_payload(payload, "CAMS WBR2 mailback"),
    )
    await provider.close()
