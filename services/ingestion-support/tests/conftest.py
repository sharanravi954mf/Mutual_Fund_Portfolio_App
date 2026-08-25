from __future__ import annotations

import os
from io import BytesIO, StringIO
from typing import Literal

import pytest
from fastapi.testclient import TestClient
from reportlab.pdfgen import canvas

os.environ.setdefault("MAILBOX_CONNECTOR_SERVICE_TOKEN", "mailbox-test-token-0000000000000001")
os.environ.setdefault("PDF_TEXT_EXTRACTOR_SERVICE_TOKEN", "pdf-test-token-000000000000000000002")
os.environ.setdefault("MALWARE_SCANNER_SERVICE_TOKEN", "malware-test-token-000000000000003")
os.environ.setdefault("GMAIL_OAUTH_CLIENT_ID", "gmail-test-client-id")
os.environ.setdefault("GMAIL_OAUTH_CLIENT_SECRET", "gmail-test-client-secret")
os.environ.setdefault("CAMS_MAILBACK_ZIP_PASSWORD", "cams123")
os.environ.setdefault(
    "GMAIL_OAUTH_REDIRECT_URI",
    "https://dev.example.test/functions/v1/cams-kfintech-ingestion/oauth/callback",
)

from app.config import Settings
from app.diagnostics import (
    HANDLER_NAME,
    LOGGER,
    configure_application_logging,
)
from app.errors import ServiceError
from app.mailbox import (
    Attachment,
    AuthorizationUrlRequest,
    AuthorizationUrlResult,
    ExchangeRequest,
    ExchangeResult,
    FetchRequest,
    Message,
    PollRequest,
    RefreshRequest,
    RefreshResult,
    RevokeRequest,
)
from app.main import create_app

CAMS_HEADERS = [
    "PAN",
    "INV_NAME",
    "FOLIO_NO",
    "SCHEME_CD",
    "SCHEME_NM",
    "FUND_HOUSE",
    "CATEGORY",
    "TRX_TYPE",
    "UNITS",
    "NAV",
    "AMOUNT",
    "TRX_DATE",
    "TRX_ID",
]
CAMS_ROW = [
    "ABCDE1234F",
    "Synthetic Investor",
    "FOLIO1001",
    "CAMS001",
    "Synthetic Equity Fund",
    "Synthetic AMC",
    "Equity",
    "BUY",
    "12.5000",
    "20.0000",
    "250.00",
    "20260729",
    "CAMS-SYNTH-1",
]
KFINTECH_HEADERS = [
    "PAN1",
    "INVNAME",
    "ACNO",
    "FUNDCODE",
    "FUND_DESC",
    "AMC_NAME",
    "ASSETTYPE",
    "TD_TRTYPE",
    "TD_UNITS",
    "TD_NAV",
    "TD_AMT",
    "TD_TRDATE",
    "TD_TRNO",
]
KFINTECH_ROW = [
    "FGHIJ5678K",
    "Synthetic KFin Investor",
    "KFOLIO1001",
    "KFIN001",
    "Synthetic Debt Fund",
    "Synthetic KFin AMC",
    "Debt",
    "R",
    "-5.0000",
    "10.0000",
    "-50.00",
    "20260729",
    "KFIN-SYNTH-1",
]


def synthetic_pdf(registrar: Literal["CAMS", "KFINTECH"]) -> bytes:
    marker = f"MONEYBOWL_{registrar}_CAS_V1"
    headers = CAMS_HEADERS if registrar == "CAMS" else KFINTECH_HEADERS
    row = CAMS_ROW if registrar == "CAMS" else KFINTECH_ROW
    buffer = BytesIO()
    document = canvas.Canvas(buffer, pageCompression=0)
    document.setFont("Helvetica", 6)
    y = 800
    for line in (marker, "|".join(headers), "|".join(row)):
        document.drawString(20, y, line)
        y -= 20
    document.save()
    return buffer.getvalue()


class FakeMailboxProvider:
    def __init__(self) -> None:
        self.access_tokens: list[str] = []
        self.failure: ServiceError | None = None
        self.attachment_content = b"synthetic attachment"

    def authorization_url(self, request: AuthorizationUrlRequest) -> AuthorizationUrlResult:
        return AuthorizationUrlResult(
            authorization_url=f"https://accounts.example.test/auth?state={request.state}"
        )

    async def exchange(self, request: ExchangeRequest) -> ExchangeResult:
        return ExchangeResult(
            access_token="provisioned-access-token",
            refresh_token="provisioned-refresh-token",
            expires_at="2026-08-22T12:00:00Z",
        )

    async def revoke(self, request: RevokeRequest) -> None:
        del request

    async def refresh(self, request: RefreshRequest) -> RefreshResult:
        if self.failure:
            raise self.failure
        assert request.refresh_token == "refresh-fixture"
        return RefreshResult(
            access_token="refreshed-access-token",
            refresh_token="rotated-refresh-token",
            expires_at="2026-08-22T12:00:00Z",
        )

    async def poll(self, request: PollRequest, access_token: str) -> list[Message]:
        if self.failure:
            raise self.failure
        self.access_tokens.append(access_token)
        return [
            Message(
                message_id="gmail-message-1",
                sender_address="statements@example.test",
                received_at="2026-08-22T10:00:00Z",
                attachments=[
                    Attachment(
                        attachment_id="gmail-attachment-1",
                        filename="synthetic-cams.pdf",
                        declared_mime="application/pdf",
                        received_at="2026-08-22T10:00:00Z",
                    )
                ],
            )
        ]

    async def fetch_attachment(
        self, request: FetchRequest, access_token: str, max_bytes: int
    ) -> bytes:
        if self.failure:
            raise self.failure
        self.access_tokens.append(access_token)
        assert request.message_id == "gmail-message-1"
        assert request.attachment_id == "gmail-attachment-1"
        return self.attachment_content


class FakeMalwareScanner:
    def __init__(self) -> None:
        self.ready_value = True
        self.failure: ServiceError | None = None

    async def ready(self) -> bool:
        return self.ready_value

    async def scan(self, body: bytes) -> Literal["clean", "infected"]:
        if self.failure:
            raise self.failure
        if b"EICAR" in body:
            return "infected"
        return "clean"


@pytest.fixture
def settings() -> Settings:
    return Settings()


@pytest.fixture
def fake_mailbox() -> FakeMailboxProvider:
    return FakeMailboxProvider()


@pytest.fixture
def fake_scanner() -> FakeMalwareScanner:
    return FakeMalwareScanner()


@pytest.fixture
def diagnostic_stream():
    configure_application_logging()
    handler = next(item for item in LOGGER.handlers if item.get_name() == HANDLER_NAME)
    stream = StringIO()
    original_stream = handler.stream
    handler.setStream(stream)
    try:
        yield stream
    finally:
        handler.setStream(original_stream)


@pytest.fixture
def client(
    settings: Settings,
    fake_mailbox: FakeMailboxProvider,
    fake_scanner: FakeMalwareScanner,
):
    app = create_app(settings, fake_mailbox, fake_scanner)
    with TestClient(app) as test_client:
        yield test_client


def mailbox_headers(settings: Settings) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {settings.mailbox_connector_service_token}",
        "Content-Type": "application/json",
    }


def poll_body(**overrides: str) -> dict[str, str]:
    body = {
        "connector_ref": "gmail:me",
        "mailbox_connection_id": "mailbox-fixture-1",
        "registrar": "CAMS",
    }
    body.update(overrides)
    return body
