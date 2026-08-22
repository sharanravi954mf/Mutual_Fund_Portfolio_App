from __future__ import annotations

import csv
import io
import json
import re
from dataclasses import dataclass
from typing import Literal

from pypdf import PdfReader
from pypdf.errors import PdfReadError

from .errors import ServiceError


Registrar = Literal["CAMS", "KFINTECH"]
HEADER_RE = re.compile(r"^[A-Z][A-Z0-9_]{0,63}$")


@dataclass(frozen=True)
class Layout:
    marker: str
    required_headers: frozenset[str]


LAYOUTS: dict[Registrar, Layout] = {
    "CAMS": Layout(
        marker="MONEYBOWL_CAMS_CAS_V1",
        required_headers=frozenset(
            {
                "PAN",
                "INV_NAME",
                "FOLIO_NO",
                "SCHEME_CD",
                "TRX_TYPE",
                "UNITS",
                "NAV",
                "AMOUNT",
                "TRX_DATE",
            }
        ),
    ),
    "KFINTECH": Layout(
        marker="MONEYBOWL_KFINTECH_CAS_V1",
        required_headers=frozenset(
            {
                "PAN1",
                "INVNAME",
                "ACNO",
                "FUNDCODE",
                "TD_TRTYPE",
                "TD_UNITS",
                "TD_NAV",
                "TD_AMT",
                "TD_TRDATE",
            }
        ),
    ),
}


class RegistrarPdfExtractor:
    """Deterministic parser for synthetic registrar characterization layouts.

    This contract proves the Edge/service boundary; it is not evidence of live
    registrar statement support. It deliberately does not guess fields or use OCR.
    Unsupported or malformed layouts fail closed.
    """

    def __init__(self, max_rows: int, max_response_bytes: int, max_pages: int = 100) -> None:
        self.max_rows = max_rows
        self.max_response_bytes = max_response_bytes
        self.max_pages = max_pages

    def extract(self, body: bytes, registrar: Registrar, statement_format: str) -> dict[str, object]:
        if statement_format != "CAS_PDF":
            raise ServiceError(400, "unsupported_statement_format")
        if not body.startswith(b"%PDF-") or b"%%EOF" not in body[-2048:]:
            raise ServiceError(422, "malformed_pdf")
        try:
            reader = PdfReader(io.BytesIO(body), strict=True)
            if reader.is_encrypted:
                raise ServiceError(422, "encrypted_pdf_unsupported")
            if len(reader.pages) == 0 or len(reader.pages) > self.max_pages:
                raise ServiceError(422, "pdf_page_limit_exceeded")
            text_parts: list[str] = []
            text_size = 0
            for page in reader.pages:
                text = page.extract_text() or ""
                text_size += len(text.encode("utf-8"))
                if text_size > self.max_response_bytes:
                    raise ServiceError(413, "pdf_text_too_large")
                text_parts.append(text)
        except ServiceError:
            raise
        except (PdfReadError, ValueError, TypeError, KeyError) as error:
            raise ServiceError(422, "malformed_pdf") from error

        rows = self._parse_layout("\n".join(text_parts), registrar)
        response: dict[str, object] = {
            "version": "moneybowl.pdf-extraction.v1",
            "registrar": registrar,
            "statement_format": statement_format,
            "rows": rows,
        }
        encoded_size = len(json.dumps(response, separators=(",", ":")).encode("utf-8"))
        if encoded_size > self.max_response_bytes:
            raise ServiceError(413, "pdf_response_too_large")
        return response

    def _parse_layout(self, text: str, registrar: Registrar) -> list[dict[str, str]]:
        layout = LAYOUTS[registrar]
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        if len(lines) < 3 or lines[0] != layout.marker:
            raise ServiceError(422, "unsupported_pdf_layout")
        if any(len(line.encode("utf-8")) > 16_384 for line in lines):
            raise ServiceError(413, "pdf_row_too_large")

        try:
            parsed = list(csv.reader(lines[1:], delimiter="|", strict=True))
        except csv.Error as error:
            raise ServiceError(422, "malformed_pdf_rows") from error
        headers = parsed[0]
        if (
            not headers
            or len(headers) > 64
            or len(headers) != len(set(headers))
            or any(HEADER_RE.fullmatch(header) is None for header in headers)
            or not layout.required_headers.issubset(headers)
        ):
            raise ServiceError(422, "unsupported_pdf_layout")

        data = parsed[1:]
        if not data or len(data) > self.max_rows:
            raise ServiceError(422, "pdf_row_limit_exceeded")
        rows: list[dict[str, str]] = []
        for values in data:
            if len(values) != len(headers) or any(len(value) > 1024 for value in values):
                raise ServiceError(422, "malformed_pdf_rows")
            rows.append(dict(zip(headers, values, strict=True)))
        return rows
