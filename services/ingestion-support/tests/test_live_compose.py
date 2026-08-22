from __future__ import annotations

import hashlib
import os

import httpx
import pytest

from conftest import synthetic_pdf
from test_malware_contract import eicar_fixture


BASE_URL = os.getenv("INGESTION_SUPPORT_BASE_URL")


@pytest.mark.integration
@pytest.mark.skipif(not BASE_URL, reason="set INGESTION_SUPPORT_BASE_URL for Compose tests")
def test_live_compose_readiness_pdf_and_clamav() -> None:
    assert BASE_URL is not None
    mailbox_token = os.environ["MAILBOX_CONNECTOR_SERVICE_TOKEN"]
    pdf_token = os.environ["PDF_TEXT_EXTRACTOR_SERVICE_TOKEN"]
    malware_token = os.environ["MALWARE_SCANNER_SERVICE_TOKEN"]
    del mailbox_token  # Mailbox provider calls remain mocked; the token is still required at startup.

    with httpx.Client(
        base_url=BASE_URL,
        timeout=20,
        follow_redirects=False,
        headers={"Host": "localhost"},
    ) as client:
        assert client.get("/health").json() == {"status": "ok"}
        assert client.get("/ready").json() == {"status": "ready"}

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
