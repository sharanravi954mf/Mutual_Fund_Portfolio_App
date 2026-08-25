from __future__ import annotations

import base64
from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr, ValidationError

from conftest import FakeMalwareScanner, mailbox_headers, poll_body

from app.cams_mailback import (
    download_cams_zip,
    extract_cams_dbf,
    parse_cams_mailback,
    required_html_text,
    validate_cams_download_url,
)
from app.config import Settings
from app.errors import ServiceError
from app.mailbox import FetchRequest, GmailProvider, PollRequest
from app.main import create_app

FIXTURES = Path(__file__).parent / "fixtures"
CAMS_WBR2_URL = (
    "https://mailback12.camsonline.com/mailback_result/synthetic-wbr2.zip"
)
ENCRYPTED_DBF_ZIP_B64 = (
    "UEsDBBQACQAIADB1GV3Nlnr1CgEAAGoCAAASABwAc3ludGhldGljLXdicjIuZGJmVVQJAANEXI1q"
    "RFyNanV4CwABBPUBAAAEFAAAAEeomJyplYw9e61/7158uHTU7CAT1U6yXpYHm7+xZqT1Ok7yXmso"
    "X557zmBl4qPsh5zdHY32ZyVwyE38mvLlmFdnWeXdoy24wjTSwX56wECABxUucYkwwzIAZjNcVnhH"
    "4h/TEfoToGYtsC18HyNn8mUL8p8Nf5FS3I75B3uGM0PLbIZxhbptT//bAJdgkJwGeZarIb9NltYj"
    "WR/nG3QlSIY5rDL+lnIBe1B5atAP6XqLy7XC2H9Cpyre11h1luPl40VkLBvMZW+5HlZMGegQZSSN"
    "WvB3aCrgcBaRId8b4rQRSH6pOZMzZHZfdQM+mdxelLk5hNRQ4S/jcpTjXuFzXQ9Xzs1Pa3JtZZwAU"
    "EsHCM2WevUKAQAAagIAAFBLAQIeAxQACQAIADB1GV3Nlnr1CgEAAGoCAAASABgAAAAAAAAAAACkgQ"
    "AAAABzeW50aGV0aWMtd2JyMi5kYmZVVAUAA0RcjWp1eAsAAQT1AQAABBQAAABQSwUGAAAAAAEAAQ"
    "BYAAAAZgEAAAAA"
)
ENCRYPTED_ZIP_BOMB_B64 = (
    "UEsDBBQACQAIAEt1GV1Kb0wwiwAAAKCGAQAIABwAYm9tYi5kYmZVVAkAA3VcjWp1XI1qdXgLAAEE"
    "9QEAAAQUAAAAZYXXlp9blOOu3tTAV3EVmRuU1sCUvsKvt1BXegoIGjenPfRKs191HemdYDPdWsn6r"
    "rcfcEJTyOn7SEMjljR0T0GZVpDtLvIG0+nip7AdKf9iB2bv+ZaHrGsNNGNJddgXhS/1ftwORRQYp"
    "8SZFjdv8r4kdhKxCFU6ttzHppUs9icwThcgIxUqom3Mv1BLBwhKb0wwiwAAAKCGAQBQSwECHgMUAA"
    "kACABLdRldSm9MMIsAAACghgEACAAYAAAAAAAAAAAApIEAAAAAYm9tYi5kYmZVVAUAA3VcjWp1eAsA"
    "AQT1AQAABBQAAABQSwUGAAAAAAEAAQBOAAAA3QAAAAAA"
)


def _mailback_fixture(name: str) -> str:
    return required_html_text((FIXTURES / name).read_text(encoding="utf-8"))


def _gmail_mailback_message(
    message_id: str,
    fixture: str,
    report_type: str,
) -> dict[str, object]:
    html = (FIXTURES / fixture).read_bytes()
    return {
        "id": message_id,
        "internalDate": "1787392800000",
        "payload": {
            "headers": [
                {"name": "From", "value": "CAMS <donotreply@camsonline.com>"},
                {"name": "Subject", "value": f"CAMS {report_type} mailback"},
            ],
            "mimeType": "multipart/alternative",
            "parts": [
                {
                    "filename": "",
                    "mimeType": "text/html",
                    "body": {
                        "data": base64.urlsafe_b64encode(html).decode().rstrip("="),
                        "size": len(html),
                    },
                }
            ],
        },
    }


@pytest.mark.parametrize(
    ("fixture", "report_type"),
    [
        ("cams_wbr2_mailback.html", "WBR2"),
        ("cams_wbr9_mailback.html", "WBR9"),
    ],
    ids=["wbr2-link-url", "wbr9-link-url"],
)
def test_supported_cams_html_mailbacks(fixture: str, report_type: str) -> None:
    text = _mailback_fixture(fixture)
    result = parse_cams_mailback(
        subject=f"CAMS {report_type} mailback",
        body_text=text,
    )

    assert result.outcome == "supported"
    assert result.report_type == report_type
    assert result.download_url is not None
    assert result.download_url.startswith("https://mailback")
    assert "\nLink\n" in f"\n{text}\n"


def test_unrelated_html_link_cannot_replace_download_url() -> None:
    html = (FIXTURES / "cams_wbr2_mailback.html").read_text(encoding="utf-8")
    text = required_html_text(
        html.replace("</body>", '<a href="https://example.test/footer">Footer</a></body>')
    )
    result = parse_cams_mailback(subject="CAMS WBR2 mailback", body_text=text)

    assert result.download_url == CAMS_WBR2_URL


def test_wbr49_is_explicitly_unsupported() -> None:
    text = _mailback_fixture("cams_wbr49_mailback.html")
    result = parse_cams_mailback(
        subject="CAMS WBR49 mailback",
        body_text=text,
    )

    assert result.outcome == "unsupported_report"
    assert result.report_type == "WBR49"
    assert result.download_url is None


def test_no_data_na_is_legitimate_outcome() -> None:
    text = _mailback_fixture("cams_wbr2_no_data.html")
    result = parse_cams_mailback(
        subject="CAMS WBR2 mailback",
        body_text=text,
    )

    assert result.outcome == "no_data"
    assert result.download_url is None


def test_completed_with_url_fails_closed() -> None:
    text = _mailback_fixture("cams_wbr2_mailback.html")
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        parse_cams_mailback(
            subject="CAMS WBR2 mailback",
            body_text=text.replace("Link", "Completed", 1),
        )


def test_unknown_request_status_with_url_fails_closed() -> None:
    text = _mailback_fixture("cams_wbr2_mailback.html")
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        parse_cams_mailback(
            subject="CAMS WBR2 mailback",
            body_text=text.replace("Link", "Processing", 1),
        )


def test_link_with_na_fails_closed() -> None:
    text = _mailback_fixture("cams_wbr2_mailback.html")
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        parse_cams_mailback(
            subject="CAMS WBR2 mailback",
            body_text=text.replace(CAMS_WBR2_URL, "NA", 1),
        )


def test_no_data_with_url_fails_closed() -> None:
    text = _mailback_fixture("cams_wbr2_no_data.html")
    with pytest.raises(ServiceError, match="provider_response_invalid"):
        parse_cams_mailback(
            subject="CAMS WBR2 mailback",
            body_text=text.replace("NA", CAMS_WBR2_URL, 1),
        )


@pytest.mark.parametrize(
    "url",
    [
        "http://mailback1.camsonline.com/mailback_result/a.zip",
        "https://mailback1.camsonline.com.evil.test/mailback_result/a.zip",
        "https://mailback1-camsonline.com/mailback_result/a.zip",
        "https://camsonline.com/mailback_result/a.zip",
        "https://127.0.0.1/mailback_result/a.zip",
        "https://localhost/mailback_result/a.zip",
        "https://10.0.0.1/mailback_result/a.zip",
        "https://[::1]/mailback_result/a.zip",
        "https://user:pass@mailback1.camsonline.com/mailback_result/a.zip",
        "https://mailback1.camsonline.com:443/mailback_result/a.zip",
        "https://mailback1.camsonline.com/mailback_result/a.zip#fragment",
        "https://mailback1.camsonline.com/other/a.zip",
        "https://mailback1.camsonline.com/mailback_result/%2e%2e%2fa.zip",
    ],
)
def test_cams_download_url_rejects_untrusted_variants(url: str) -> None:
    with pytest.raises(ServiceError, match="cams_mailback_url_rejected"):
        validate_cams_download_url(url)


def test_cams_download_url_accepts_exact_https_host_and_path() -> None:
    url = "https://mailback123.camsonline.com/mailback_result/opaque-file.zip"
    assert validate_cams_download_url(url) == url


@pytest.mark.asyncio
async def test_cams_download_rejects_redirect_and_oversized_response() -> None:
    url = "https://mailback1.camsonline.com/mailback_result/a.zip"

    redirect_client = httpx.AsyncClient(
        follow_redirects=False,
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(302, headers={"Location": url})
        ),
    )
    with pytest.raises(ServiceError, match="provider_redirect_rejected"):
        await download_cams_zip(redirect_client, url, max_bytes=1024)
    await redirect_client.aclose()

    oversized_client = httpx.AsyncClient(
        follow_redirects=False,
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(200, content=b"x" * 1025)
        ),
    )
    with pytest.raises(ServiceError, match="provider_response_too_large"):
        await download_cams_zip(oversized_client, url, max_bytes=1024)
    await oversized_client.aclose()

    timeout_client = httpx.AsyncClient(
        follow_redirects=False,
        transport=httpx.MockTransport(
            lambda request: (_ for _ in ()).throw(httpx.ReadTimeout("timeout", request=request))
        ),
    )
    with pytest.raises(ServiceError, match="provider_unavailable"):
        await download_cams_zip(timeout_client, url, max_bytes=1024)
    await timeout_client.aclose()


def test_password_protected_zip_extracts_dbf_with_correct_password() -> None:
    result = extract_cams_dbf(
        base64.b64decode(ENCRYPTED_DBF_ZIP_B64),
        password="cams123",
        max_uncompressed_bytes=4096,
        max_entries=4,
        max_ratio=100,
    )

    assert result[0] == 0x03
    assert b"Synthetic Investor" in result
    assert b"SYNTH-FOLIO-1" in result


def test_password_protected_zip_wrong_password_and_corruption_fail_closed() -> None:
    encrypted = base64.b64decode(ENCRYPTED_DBF_ZIP_B64)
    for payload, password in ((encrypted, "wrong"), (encrypted[:-12], "cams123")):
        with pytest.raises(ServiceError, match="cams_mailback_zip_invalid"):
            extract_cams_dbf(
                payload,
                password=password,
                max_uncompressed_bytes=4096,
                max_entries=4,
                max_ratio=100,
            )


def test_zip_bomb_ratio_fails_closed() -> None:
    with pytest.raises(ServiceError, match="cams_mailback_zip_invalid"):
        extract_cams_dbf(
            base64.b64decode(ENCRYPTED_ZIP_BOMB_B64),
            password="cams123",
            max_uncompressed_bytes=200_000,
            max_entries=4,
            max_ratio=100,
        )


@pytest.mark.parametrize(
    "entry_name",
    ["../escape.dbf", "/absolute.dbf", "C:\\absolute.dbf", "nested/a.dbf", "nested.zip"],
)
def test_zip_slip_and_non_exact_payload_paths_fail_closed(entry_name: str) -> None:
    buffer = BytesIO()
    with ZipFile(buffer, "w", ZIP_DEFLATED) as archive:
        archive.writestr(entry_name, b"\x03" + b"x" * 64)
    with pytest.raises(ServiceError, match="cams_mailback_zip_invalid"):
        extract_cams_dbf(
            buffer.getvalue(),
            password="cams123",
            max_uncompressed_bytes=4096,
            max_entries=4,
            max_ratio=100,
        )


def test_zip_entry_count_limit_fails_closed() -> None:
    buffer = BytesIO()
    with ZipFile(buffer, "w", ZIP_DEFLATED) as archive:
        for index in range(5):
            archive.writestr(f"entry-{index}.dbf", b"\x03" + b"x" * 64)
    with pytest.raises(ServiceError, match="cams_mailback_zip_invalid"):
        extract_cams_dbf(
            buffer.getvalue(),
            password="cams123",
            max_uncompressed_bytes=4096,
            max_entries=4,
            max_ratio=100,
        )


def test_duplicate_zip_entries_fail_closed() -> None:
    buffer = BytesIO()
    with pytest.warns(UserWarning, match="Duplicate name"):
        with ZipFile(buffer, "w", ZIP_DEFLATED) as archive:
            archive.writestr("duplicate.dbf", b"\x03" + b"x" * 64)
            archive.writestr("duplicate.dbf", b"\x03" + b"y" * 64)
    with pytest.raises(ServiceError, match="cams_mailback_zip_invalid"):
        extract_cams_dbf(
            buffer.getvalue(),
            password="cams123",
            max_uncompressed_bytes=4096,
            max_entries=4,
            max_ratio=100,
        )


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("fixture", "report_type", "message_id"),
    [
        ("cams_wbr2_mailback.html", "WBR2", "mailbackWbr2"),
        ("cams_wbr9_mailback.html", "WBR9", "mailbackWbr9"),
    ],
)
async def test_gmail_mailback_poll_fetches_password_zip_and_returns_dbf(
    settings,
    fixture: str,
    report_type: str,
    message_id: str,
) -> None:
    encrypted = base64.b64decode(ENCRYPTED_DBF_ZIP_B64)

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            query = request.url.params["q"]
            assert query.startswith("from:(donotreply@camsonline.com)")
            assert "WBR OR has:attachment" in query
            return httpx.Response(200, json={"messages": [{"id": message_id}]})
        if request.url.host == "gmail.googleapis.com":
            return httpx.Response(
                200,
                json=_gmail_mailback_message(message_id, fixture, report_type),
            )
        assert request.url.host.startswith("mailback")
        assert request.url.host.endswith(".camsonline.com")
        return httpx.Response(200, content=encrypted)

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    poll_request = PollRequest(
        connector_ref="gmail:me",
        mailbox_connection_id="mailbox-fixture-1",
        registrar="CAMS",
    )
    messages = await provider.poll(poll_request, "mailback-oauth-token")

    assert len(messages) == 1
    assert messages[0].sender_address == "donotreply@camsonline.com"
    assert messages[0].outcome is None
    assert len(messages[0].attachments) == 1
    attachment = messages[0].attachments[0]
    assert attachment.attachment_id.startswith("mailback:")
    assert attachment.filename == f"cams-{report_type.lower()}.dbf"
    assert "camsonline.com" not in attachment.attachment_id

    dbf = await provider.fetch_attachment(
        FetchRequest(
            **poll_request.model_dump(),
            message_id=message_id,
            attachment_id=attachment.attachment_id,
        ),
        "mailback-oauth-token",
        4096,
    )
    await provider.close()

    assert dbf[0] == 0x03
    assert b"Synthetic Investor" in dbf


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("fixture", "report_type", "expected_outcome"),
    [
        ("cams_wbr49_mailback.html", "WBR49", "unsupported_report"),
        ("cams_wbr2_no_data.html", "WBR2", "no_data"),
    ],
)
async def test_gmail_mailback_returns_sanitized_non_attachment_outcomes(
    settings,
    fixture: str,
    report_type: str,
    expected_outcome: str,
) -> None:
    message_id = f"mailback{report_type}Outcome"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": message_id}]})
        return httpx.Response(
            200,
            json=_gmail_mailback_message(message_id, fixture, report_type),
        )

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    messages = await provider.poll(
        PollRequest(
            connector_ref="gmail:me",
            mailbox_connection_id="mailbox-fixture-1",
            registrar="CAMS",
        ),
        "mailback-oauth-token",
    )
    await provider.close()

    assert len(messages) == 1
    assert messages[0].attachments == []
    assert messages[0].outcome == expected_outcome


@pytest.mark.asyncio
async def test_dev_synthetic_sender_is_added_only_through_configuration(settings) -> None:
    configured = settings.model_copy(
        update={
            "cams_mailback_candidate_senders": (
                "donotreply@camsonline.com,statements@example.test"
            )
        }
    )
    observed_query = ""

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal observed_query
        observed_query = request.url.params["q"]
        return httpx.Response(200, json={"messages": []})

    provider = GmailProvider(configured, httpx.MockTransport(handler))
    messages = await provider.poll(
        PollRequest(
            connector_ref="gmail:me",
            mailbox_connection_id="mailbox-fixture-1",
            registrar="CAMS",
        ),
        "mailback-oauth-token",
    )
    await provider.close()

    assert messages == []
    assert observed_query.startswith(
        "from:(donotreply@camsonline.com OR statements@example.test)"
    )


@pytest.mark.parametrize(
    "configured_senders",
    [
        "donotreply@camsonline.com,donotreply@camsonline.com",
        "report|from:attacker@example.test",
        "local@localhost",
    ],
)
def test_cams_candidate_sender_configuration_rejects_unsafe_values(
    monkeypatch,
    configured_senders: str,
) -> None:
    monkeypatch.setenv("CAMS_MAILBACK_CANDIDATE_SENDERS", configured_senders)

    with pytest.raises(ValidationError, match="CAMS_MAILBACK_CANDIDATE_SENDERS"):
        Settings()


@pytest.mark.asyncio
async def test_non_cams_gmail_attachment_discovery_query_is_unchanged(settings) -> None:
    observed_query = ""

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal observed_query
        observed_query = request.url.params["q"]
        return httpx.Response(200, json={"messages": []})

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    await provider.poll(
        PollRequest(
            connector_ref="gmail:me",
            mailbox_connection_id="mailbox-fixture-1",
            registrar="KFINTECH",
        ),
        "mailback-oauth-token",
    )
    await provider.close()

    assert observed_query == "has:attachment {filename:pdf filename:dbf}"


@pytest.mark.asyncio
async def test_mailback_wrong_configured_password_fails_closed(settings) -> None:
    encrypted = base64.b64decode(ENCRYPTED_DBF_ZIP_B64)
    wrong_password_settings = settings.model_copy(
        update={"cams_mailback_zip_password": SecretStr("wrong")}
    )

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": "wrongPassword"}]})
        if request.url.host == "gmail.googleapis.com":
            return httpx.Response(
                200,
                json=_gmail_mailback_message(
                    "wrongPassword", "cams_wbr2_mailback.html", "WBR2"
                ),
            )
        return httpx.Response(200, content=encrypted)

    provider = GmailProvider(wrong_password_settings, httpx.MockTransport(handler))
    poll_request = PollRequest(
        connector_ref="gmail:me",
        mailbox_connection_id="mailbox-fixture-1",
        registrar="CAMS",
    )
    messages = await provider.poll(poll_request, "mailback-oauth-token")
    with pytest.raises(ServiceError, match="cams_mailback_zip_invalid"):
        await provider.fetch_attachment(
            FetchRequest(
                **poll_request.model_dump(),
                message_id="wrongPassword",
                attachment_id=messages[0].attachments[0].attachment_id,
            ),
            "mailback-oauth-token",
            4096,
        )
    await provider.close()


def test_cams_mailback_fields_and_password_never_reach_logs(
    settings,
    diagnostic_stream,
) -> None:
    message_id = "provider-message-id-must-not-be-logged"

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/messages"):
            return httpx.Response(200, json={"messages": [{"id": message_id}]})
        return httpx.Response(
            200,
            json=_gmail_mailback_message(
                message_id, "cams_wbr2_mailback.html", "WBR2"
            ),
        )

    provider = GmailProvider(settings, httpx.MockTransport(handler))
    app = create_app(settings, provider, FakeMalwareScanner())
    with TestClient(app) as client:
        response = client.post(
            "/poll",
            headers={
                **mailbox_headers(settings),
                "X-Mailbox-OAuth-Token": "mailback-oauth-token",
            },
            json=poll_body(),
        )

    assert response.status_code == 200
    logs = diagnostic_stream.getvalue()
    for forbidden in (
        message_id,
        "donotreply@camsonline.com",
        "mailback12.camsonline.com",
        "SYNTHETIC-REQUEST-ID-MUST-NOT-BE-PARSED-OR-LOGGED",
        settings.cams_mailback_zip_password.get_secret_value(),
        "Synthetic Investor",
    ):
        assert forbidden not in logs
