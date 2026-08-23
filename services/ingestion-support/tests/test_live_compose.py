from __future__ import annotations

import hashlib
import os
from urllib.parse import urlparse

import httpx
import pytest

from conftest import synthetic_pdf
from test_malware_contract import eicar_fixture


BASE_URL = os.getenv("INGESTION_SUPPORT_BASE_URL")


def _assert_safe_smoke_target(base_url: str) -> None:
    parsed = urlparse(base_url)
    assert parsed.hostname, "integration smoke target must include a hostname"
    assert not parsed.username and not parsed.password, "credentials must not be embedded in URL"
    assert not parsed.query and not parsed.fragment, "smoke target must not contain query/fragment"
    assert parsed.path in {"", "/"}, "smoke target must be an origin, not an endpoint URL"
    if parsed.scheme == "https":
        return
    allow_local_http = os.getenv("ALLOW_INSECURE_LOCAL_SMOKE_URL") == "true"
    if parsed.scheme == "http" and parsed.hostname in {"127.0.0.1", "::1", "localhost"}:
        assert allow_local_http, "set ALLOW_INSECURE_LOCAL_SMOKE_URL=true for loopback only"
        return
    raise AssertionError("integration smoke target must use HTTPS (except explicit loopback tests)")


def _error_code(response: httpx.Response) -> str:
    return str(response.json()["error"]["code"])


def test_smoke_target_requires_https_except_explicit_loopback(monkeypatch: pytest.MonkeyPatch) -> None:
    _assert_safe_smoke_target("https://ingestion-dev.example.test")
    monkeypatch.setenv("ALLOW_INSECURE_LOCAL_SMOKE_URL", "true")
    _assert_safe_smoke_target("http://127.0.0.1:8080")
    with pytest.raises(AssertionError):
        _assert_safe_smoke_target("http://ingestion-dev.example.test")
    with pytest.raises(AssertionError):
        _assert_safe_smoke_target("https://token@example.test")
    with pytest.raises(AssertionError):
        _assert_safe_smoke_target("https://ingestion-dev.example.test/pdf/extract")


@pytest.mark.integration
@pytest.mark.skipif(not BASE_URL, reason="set INGESTION_SUPPORT_BASE_URL for Compose tests")
def test_live_compose_readiness_pdf_and_clamav() -> None:
    assert BASE_URL is not None
    _assert_safe_smoke_target(BASE_URL)
    mailbox_token = os.environ["MAILBOX_CONNECTOR_SERVICE_TOKEN"]
    pdf_token = os.environ["PDF_TEXT_EXTRACTOR_SERVICE_TOKEN"]
    malware_token = os.environ["MALWARE_SCANNER_SERVICE_TOKEN"]
    with httpx.Client(
        base_url=BASE_URL,
        timeout=20,
        follow_redirects=False,
    ) as client:
        assert client.get("/health").json() == {"status": "ok"}
        assert client.get("/ready").json() == {"status": "ready"}

        for path in ("/poll", "/pdf/extract", "/malware/scan"):
            rejected = client.post(path, headers={"Authorization": "Bearer definitely-invalid"})
            assert rejected.status_code == 401
            assert _error_code(rejected) == "unauthorized"

        mailbox_accepted = client.post(
            "/poll",
            headers={"Authorization": f"Bearer {mailbox_token}"},
        )
        assert mailbox_accepted.status_code == 401
        assert _error_code(mailbox_accepted) == "mailbox_oauth_token_required"

        pdf = synthetic_pdf("CAMS")
        extraction = client.post(
            "/pdf/extract",
            headers={
                "Authorization": f"Bearer {pdf_token}",
                "Content-Type": "application/pdf",
                "X-Registrar": "CAMS",
                "X-Statement-Format": "CAS_PDF",
                "X-File-Name": "synthetic-cams.pdf",
            },
            content=pdf,
        )
        assert extraction.status_code == 200, extraction.text
        assert extraction.json()["rows"][0]["SCHEME_CD"] == "CAMS001"

        for body, verdict in ((b"clean fixture", "clean"), (eicar_fixture(), "infected")):
            scan = client.post(
                "/malware/scan",
                headers={
                    "Authorization": f"Bearer {malware_token}",
                    "Content-Type": "application/octet-stream",
                    "X-Content-SHA256": hashlib.sha256(body).hexdigest(),
                    "X-File-Name": "synthetic.bin",
                },
                content=body,
            )
            assert scan.status_code == 200, scan.text
            assert scan.json() == {
                "version": "moneybowl.malware-scan.v1",
                "verdict": verdict,
            }
