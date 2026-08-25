from __future__ import annotations

import re
import stat
import unicodedata
import zlib
from dataclasses import dataclass
from html.parser import HTMLParser
from io import BytesIO
from pathlib import PurePosixPath
from typing import Literal
from urllib.parse import unquote, urlsplit
from zipfile import BadZipFile, ZIP_DEFLATED, ZIP_STORED, ZipFile

import httpx

from .errors import ServiceError

SUPPORTED_CAMS_REPORTS = frozenset({"WBR2", "WBR9"})
CAMS_HOST_RE = re.compile(r"^mailback[0-9]+\.camsonline\.com$")
CAMS_PATH_RE = re.compile(r"^/mailback_result/[A-Za-z0-9._~-]+\.zip$")
CAMS_REPORT_RE = re.compile(r"\bWBR[0-9]+\b", re.IGNORECASE)


class _RequiredHtmlText(HTMLParser):
    _block_tags = frozenset({"br", "div", "p", "tr", "td", "th", "li", "table"})

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.fragments: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() in self._block_tags:
            self.fragments.append("\n")
        if tag.lower() == "a":
            for name, value in attrs:
                if name.lower() == "href" and value is not None:
                    self.fragments.append(f"\n{value.strip()}\n")

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in self._block_tags:
            self.fragments.append("\n")

    def handle_data(self, data: str) -> None:
        self.fragments.append(data)


@dataclass(frozen=True)
class CamsMailbackResult:
    outcome: Literal["supported", "no_data", "unsupported_report"]
    report_type: str | None = None
    download_url: str | None = None


def required_html_text(value: str) -> str:
    parser = _RequiredHtmlText()
    try:
        parser.feed(value)
        parser.close()
    except (ValueError, AssertionError) as error:
        raise ServiceError(502, "provider_response_invalid") from error
    text = "\n".join(
        line.strip()
        for fragment in parser.fragments
        for line in fragment.splitlines()
        if line.strip()
    )
    return text


def _field(lines: list[str], label: str) -> str | None:
    normalized_label = re.sub(r"[^a-z0-9]", "", label.lower())
    for index, line in enumerate(lines):
        normalized_line = re.sub(r"[^a-z0-9]", "", line.lower())
        if normalized_line == normalized_label:
            return lines[index + 1].strip() if index + 1 < len(lines) else None
        match = re.match(rf"^\s*{re.escape(label)}\s*[:=-]\s*(.+?)\s*$", line, re.I)
        if match is not None:
            return match.group(1).strip()
    return None


def _report_type(subject: str, report_value: str | None) -> str | None:
    body_match = CAMS_REPORT_RE.search(report_value or "")
    subject_match = CAMS_REPORT_RE.search(subject)
    body_report = body_match.group(0).upper() if body_match is not None else None
    subject_report = subject_match.group(0).upper() if subject_match is not None else None
    if body_report is not None and subject_report is not None and body_report != subject_report:
        raise ServiceError(502, "provider_response_invalid")
    return body_report or subject_report


def validate_cams_download_url(value: str) -> str:
    if not value.isascii() or len(value) > 2048:
        raise ServiceError(502, "cams_mailback_url_rejected")
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as error:
        raise ServiceError(502, "cams_mailback_url_rejected") from error
    hostname = parsed.hostname.lower() if parsed.hostname is not None else ""
    if (
        parsed.scheme != "https"
        or parsed.username is not None
        or parsed.password is not None
        or parsed.fragment
        or parsed.query
        or port is not None
        or CAMS_HOST_RE.fullmatch(hostname) is None
        or parsed.netloc.lower() != hostname
        or CAMS_PATH_RE.fullmatch(parsed.path) is None
        or unquote(parsed.path) != parsed.path
    ):
        raise ServiceError(502, "cams_mailback_url_rejected")
    return parsed.geturl()


def parse_cams_mailback(
    *,
    subject: str,
    body_text: str,
) -> CamsMailbackResult:
    lines = [line.strip() for line in body_text.splitlines() if line.strip()]
    request_status = _field(lines, "Request Status")
    download_value = _field(lines, "DownloadURL")
    report_type = _report_type(subject, _field(lines, "Report No"))
    file_type = _field(lines, "File Type")

    if report_type not in SUPPORTED_CAMS_REPORTS:
        return CamsMailbackResult("unsupported_report", report_type=report_type)

    if (file_type or "").strip().upper() != "DBF" or not request_status:
        raise ServiceError(502, "provider_response_invalid")

    normalized_status = (request_status or "").strip().casefold()
    no_data = normalized_status == "no data"
    unavailable_url = (download_value or "").strip().upper() == "NA"
    if no_data or unavailable_url:
        if no_data and unavailable_url:
            return CamsMailbackResult("no_data", report_type=report_type)
        raise ServiceError(502, "provider_response_invalid")
    if normalized_status != "link":
        raise ServiceError(502, "provider_response_invalid")

    if download_value is None:
        raise ServiceError(502, "provider_response_invalid")
    download_url = validate_cams_download_url(download_value.strip())
    return CamsMailbackResult(
        "supported",
        report_type=report_type,
        download_url=download_url,
    )


async def download_cams_zip(
    client: httpx.AsyncClient,
    url: str,
    *,
    max_bytes: int,
) -> bytes:
    trusted_url = validate_cams_download_url(url)
    try:
        async with client.stream(
            "GET",
            trusted_url,
            headers={"Accept": "application/zip, application/octet-stream"},
        ) as response:
            if 300 <= response.status_code < 400:
                raise ServiceError(502, "provider_redirect_rejected")
            if response.status_code < 200 or response.status_code >= 300:
                raise ServiceError(502, "provider_request_failed")
            declared = response.headers.get("content-length")
            if declared is not None:
                try:
                    declared_size = int(declared)
                except ValueError as error:
                    raise ServiceError(502, "provider_response_invalid") from error
                if declared_size < 1 or declared_size > max_bytes:
                    raise ServiceError(502, "provider_response_too_large")
            chunks: list[bytes] = []
            total = 0
            async for chunk in response.aiter_bytes():
                total += len(chunk)
                if total > max_bytes:
                    raise ServiceError(502, "provider_response_too_large")
                chunks.append(chunk)
    except ServiceError:
        raise
    except (httpx.TimeoutException, httpx.NetworkError) as error:
        raise ServiceError(503, "provider_unavailable") from error
    if total == 0:
        raise ServiceError(502, "provider_response_invalid")
    return b"".join(chunks)


def _safe_dbf_entry_name(name: str) -> bool:
    normalized = unicodedata.normalize("NFC", name).replace("\\", "/")
    path = PurePosixPath(normalized)
    return (
        normalized == name
        and normalized == path.name
        and not normalized.startswith(("/", "\\"))
        and re.match(r"^[A-Za-z]:", normalized) is None
        and all(part not in {"", ".", ".."} for part in path.parts)
        and path.suffix.casefold() == ".dbf"
    )


def extract_cams_dbf(
    zip_bytes: bytes,
    *,
    password: str,
    max_uncompressed_bytes: int,
    max_entries: int,
    max_ratio: int,
) -> bytes:
    if not password:
        raise ServiceError(500, "provider_configuration_invalid")
    try:
        with ZipFile(BytesIO(zip_bytes)) as archive:
            entries = archive.infolist()
            if not entries or len(entries) > max_entries:
                raise ServiceError(422, "cams_mailback_zip_invalid")

            names = [unicodedata.normalize("NFC", entry.filename).casefold() for entry in entries]
            if len(set(names)) != len(names):
                raise ServiceError(422, "cams_mailback_zip_invalid")
            if len(entries) != 1:
                raise ServiceError(422, "cams_mailback_zip_invalid")

            entry = entries[0]
            mode = (entry.external_attr >> 16) & 0o170000
            if (
                entry.is_dir()
                or mode == stat.S_IFLNK
                or not _safe_dbf_entry_name(entry.filename)
                or entry.compress_type not in {ZIP_STORED, ZIP_DEFLATED}
                or entry.flag_bits & 0x1 == 0
                or entry.file_size < 33
                or entry.file_size > max_uncompressed_bytes
                or entry.compress_size <= 0
                or entry.file_size / entry.compress_size > max_ratio
            ):
                raise ServiceError(422, "cams_mailback_zip_invalid")

            chunks: list[bytes] = []
            total = 0
            with archive.open(entry, "r", pwd=password.encode("utf-8")) as extracted:
                while True:
                    chunk = extracted.read(min(65_536, max_uncompressed_bytes - total + 1))
                    if not chunk:
                        break
                    total += len(chunk)
                    if total > max_uncompressed_bytes:
                        raise ServiceError(422, "cams_mailback_zip_invalid")
                    chunks.append(chunk)
            result = b"".join(chunks)
            if len(result) != entry.file_size:
                raise ServiceError(422, "cams_mailback_zip_invalid")
            return result
    except ServiceError:
        raise
    except (BadZipFile, RuntimeError, EOFError, OSError, ValueError, NotImplementedError, zlib.error) as error:
        raise ServiceError(422, "cams_mailback_zip_invalid") from error
