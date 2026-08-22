from __future__ import annotations

import hashlib

import pytest
from pydantic import ValidationError

from app.config import Settings
from conftest import mailbox_headers, poll_body, synthetic_pdf
from test_malware_contract import malware_headers
from test_pdf_contract import pdf_headers


@pytest.mark.parametrize(
    ("path", "content_type", "body"),
    [
        ("/oauth/refresh", "application/json", b"{}"),
        ("/poll", "application/json", b"{}"),
        ("/attachments/fetch", "application/json", b"{}"),
        ("/pdf/extract", "application/pdf", b"%PDF-invalid\n%%EOF"),
        ("/malware/scan", "application/octet-stream", b"clean"),
    ],
)
def test_protected_routes_reject_missing_malformed_and_wrong_bearers(
    client, path: str, content_type: str, body: bytes
) -> None:
    for authorization in (None, "Basic abc", "Bearer", "Bearer wrong-token"):
        headers = {"Content-Type": content_type}
        if authorization is not None:
            headers["Authorization"] = authorization
        response = client.post(path, headers=headers, content=body)
        assert response.status_code == 401
        assert response.json() == {"error": {"code": "unauthorized"}}


def test_correct_tokens_are_capability_specific(client, settings) -> None:
    pdf = synthetic_pdf("CAMS")
    wrong_pdf = client.post(
        "/pdf/extract",
        headers={
            **pdf_headers(settings, "CAMS"),
            "Authorization": f"Bearer {settings.mailbox_connector_service_token}",
        },
        content=pdf,
    )
    assert wrong_pdf.status_code == 401

    body = b"clean"
    wrong_scanner = client.post(
        "/malware/scan",
        headers={
            **malware_headers(settings, body),
            "Authorization": f"Bearer {settings.pdf_text_extractor_service_token}",
        },
        content=body,
    )
    assert wrong_scanner.status_code == 401


def test_unexpected_methods_and_host_headers_fail_closed(client, settings) -> None:
    assert client.get("/poll").status_code == 405
    response = client.get("/health", headers={"Host": "attacker.example"})
    assert response.status_code == 400


def test_health_exposes_no_configuration(client) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_service_tokens_must_be_distinct(monkeypatch) -> None:
    shared = "shared-test-token-000000000000000000"
    monkeypatch.setenv("MAILBOX_CONNECTOR_SERVICE_TOKEN", shared)
    monkeypatch.setenv("PDF_TEXT_EXTRACTOR_SERVICE_TOKEN", shared)
    monkeypatch.setenv("MALWARE_SCANNER_SERVICE_TOKEN", shared)
    with pytest.raises(ValidationError, match="must be distinct"):
        Settings()
