from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import create_app
from conftest import (
    CAMS_HEADERS,
    CAMS_ROW,
    KFINTECH_HEADERS,
    KFINTECH_ROW,
    FakeMailboxProvider,
    FakeMalwareScanner,
    synthetic_pdf,
)


def pdf_headers(settings, registrar: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {settings.pdf_text_extractor_service_token}",
        "Content-Type": "application/pdf",
        "X-Registrar": registrar,
        "X-Statement-Format": "CAS_PDF",
        "X-File-Name": f"synthetic-{registrar.lower()}.pdf",
    }


def test_cams_and_kfintech_pdf_rows_match_edge_schema(client, settings) -> None:
    fixtures = [
        ("CAMS", CAMS_HEADERS, CAMS_ROW),
        ("KFINTECH", KFINTECH_HEADERS, KFINTECH_ROW),
    ]
    for registrar, headers, values in fixtures:
        response = client.post(
            "/pdf/extract",
            headers=pdf_headers(settings, registrar),
            content=synthetic_pdf(registrar),
        )
        assert response.status_code == 200, response.text
        assert response.json() == {
            "version": "moneybowl.pdf-extraction.v1",
            "registrar": registrar,
            "statement_format": "CAS_PDF",
            "rows": [dict(zip(headers, values, strict=True))],
        }


def test_pdf_rejects_malformed_layout_media_type_and_filename(client, settings) -> None:
    headers = pdf_headers(settings, "CAMS")
    malformed = client.post("/pdf/extract", headers=headers, content=b"%PDF-invalid\n%%EOF")
    assert malformed.status_code == 422

    wrong_type = client.post(
        "/pdf/extract",
        headers={**headers, "Content-Type": "application/octet-stream"},
        content=synthetic_pdf("CAMS"),
    )
    assert wrong_type.status_code == 415

    bad_filename = client.post(
        "/pdf/extract",
        headers={**headers, "X-File-Name": "bad\x00.pdf"},
        content=synthetic_pdf("CAMS"),
    )
    assert bad_filename.status_code == 400


def test_pdf_rejects_oversized_body(settings) -> None:
    limited = settings.model_copy(update={"max_pdf_bytes": 1024})
    app = create_app(limited, FakeMailboxProvider(), FakeMalwareScanner())
    with TestClient(app) as client:
        response = client.post(
            "/pdf/extract",
            headers=pdf_headers(limited, "CAMS"),
            content=b"%PDF-" + b"x" * 1100 + b"%%EOF",
        )
    assert response.status_code == 413
    assert response.json() == {"error": {"code": "body_too_large"}}


def test_pdf_response_contains_no_statement_content_on_failure(client, settings) -> None:
    sensitive_fixture = b"%PDF-1.7\nSYNTHETIC-SENSITIVE-CONTENT\n%%EOF"
    response = client.post(
        "/pdf/extract", headers=pdf_headers(settings, "CAMS"), content=sensitive_fixture
    )
    assert response.status_code == 422
    assert b"SYNTHETIC-SENSITIVE-CONTENT" not in response.content
