from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import re
import time
from collections import OrderedDict
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from email.utils import parseaddr
from typing import Any, Literal, Protocol
from urllib.parse import quote, urlencode

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .config import Settings
from .errors import ServiceError

Registrar = Literal["CAMS", "KFINTECH"]
CONNECTOR_REF_RE = re.compile(r"^gmail:(me|[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+)$")
PROVIDER_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,1024}$")
INLINE_ATTACHMENT_ID_RE = re.compile(r"^inline:[0-9a-f]{64}$")
GMAIL_BASE64URL_RE = re.compile(r"^[A-Za-z0-9_-]+={0,2}$")
GMAIL_ATTACHMENT_QUERY = "has:attachment {filename:pdf filename:dbf}"
GMAIL_MESSAGE_DETAIL_FIELDS = (
    "id,internalDate,"
    "payload(headers(name,value),filename,mimeType,body(attachmentId,size,data),parts)"
)
GMAIL_READONLY_SCOPE = "https://www.googleapis.com/auth/gmail.readonly"
OAUTH_STATE_RE = re.compile(r"^[A-Za-z0-9_-]{43}$")


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class RefreshRequest(StrictModel):
    workspace_id: str = Field(min_length=1, max_length=128)
    mailbox_connection_id: str = Field(min_length=1, max_length=128)
    connector_ref: str = Field(min_length=1, max_length=320)
    registrar: Registrar
    refresh_token: str = Field(min_length=1, max_length=8192)


class AuthorizationUrlRequest(StrictModel):
    state: str = Field(min_length=43, max_length=43)
    redirect_uri: str = Field(min_length=12, max_length=2048)


class ExchangeRequest(StrictModel):
    code: str = Field(min_length=1, max_length=8192)
    redirect_uri: str = Field(min_length=12, max_length=2048)


class RevokeRequest(StrictModel):
    token: str = Field(min_length=1, max_length=8192)


class PollRequest(StrictModel):
    connector_ref: str = Field(min_length=1, max_length=320)
    mailbox_connection_id: str = Field(min_length=1, max_length=128)
    registrar: Registrar


class FetchRequest(PollRequest):
    message_id: str = Field(min_length=1, max_length=1024)
    attachment_id: str = Field(min_length=1, max_length=1024)


class Attachment(StrictModel):
    attachment_id: str
    filename: str
    declared_mime: str
    received_at: str
    expected_sha256_hex: str | None = None


class Message(StrictModel):
    message_id: str
    sender_address: str
    received_at: str
    attachments: list[Attachment]


class RefreshResult(StrictModel):
    access_token: str
    refresh_token: str | None = None
    expires_at: str | None = None


class AuthorizationUrlResult(StrictModel):
    authorization_url: str


class ExchangeResult(StrictModel):
    access_token: str
    refresh_token: str
    expires_at: str


class MailboxProvider(Protocol):
    def authorization_url(self, request: AuthorizationUrlRequest) -> AuthorizationUrlResult: ...

    async def exchange(self, request: ExchangeRequest) -> ExchangeResult: ...

    async def revoke(self, request: RevokeRequest) -> None: ...

    async def refresh(self, request: RefreshRequest) -> RefreshResult: ...

    async def poll(self, request: PollRequest, access_token: str) -> list[Message]: ...

    async def fetch_attachment(
        self, request: FetchRequest, access_token: str, max_bytes: int
    ) -> bytes: ...


def validate_model(model: type[StrictModel], payload: dict[str, Any]) -> Any:
    try:
        return model.model_validate(payload)
    except ValidationError as error:
        raise ServiceError(400, "invalid_request") from error


def cache_key(request: PollRequest | FetchRequest | RefreshRequest) -> tuple[str, str, str]:
    return (request.connector_ref, request.mailbox_connection_id, request.registrar)


class AccessTokenCache:
    """Bounded process-local bridge for the current fetch contract.

    The Edge poll contract supplies the user OAuth access token, while attachment fetch
    intentionally supplies only provider identities. Tokens are never persisted and are
    scoped to the exact connector/mailbox/registrar tuple.
    """

    def __init__(self, ttl_seconds: int, max_entries: int) -> None:
        self._ttl_seconds = ttl_seconds
        self._max_entries = max_entries
        self._entries: OrderedDict[tuple[str, str, str], tuple[str, float]] = OrderedDict()
        self._lock = asyncio.Lock()

    async def put(self, key: tuple[str, str, str], token: str) -> None:
        if not token or len(token) > 8192:
            raise ServiceError(400, "invalid_oauth_token")
        async with self._lock:
            now = time.monotonic()
            self._prune(now)
            self._entries.pop(key, None)
            self._entries[key] = (token, now + self._ttl_seconds)
            while len(self._entries) > self._max_entries:
                self._entries.popitem(last=False)

    async def get(self, key: tuple[str, str, str]) -> str:
        async with self._lock:
            now = time.monotonic()
            self._prune(now)
            entry = self._entries.get(key)
            if entry is None:
                raise ServiceError(409, "mailbox_oauth_context_required")
            self._entries.move_to_end(key)
            return entry[0]

    def _prune(self, now: float) -> None:
        expired = [key for key, (_token, expires) in self._entries.items() if expires <= now]
        for key in expired:
            self._entries.pop(key, None)


InlineCacheKey = tuple[str, str, str, str, str]


class InlineAttachmentCache:
    """Bounded process-local locators for inline Gmail MIME parts.

    The cache stores only a scoped MIME-part ordinal. Inline bytes are validated during
    poll and fetched again from Gmail after the Edge requests the issued identity.
    """

    def __init__(self, ttl_seconds: int, max_entries: int) -> None:
        self._ttl_seconds = ttl_seconds
        self._max_entries = max_entries
        self._entries: OrderedDict[InlineCacheKey, tuple[int, float]] = OrderedDict()
        self._lock = asyncio.Lock()

    async def put_many(self, entries: list[tuple[InlineCacheKey, int]]) -> None:
        async with self._lock:
            now = time.monotonic()
            self._prune(now)
            for key, part_index in entries:
                self._entries.pop(key, None)
                self._entries[key] = (part_index, now + self._ttl_seconds)
            while len(self._entries) > self._max_entries:
                self._entries.popitem(last=False)

    async def get(self, key: InlineCacheKey) -> int:
        async with self._lock:
            now = time.monotonic()
            self._prune(now)
            entry = self._entries.get(key)
            if entry is None:
                raise ServiceError(409, "inline_attachment_context_required")
            self._entries.move_to_end(key)
            return entry[0]

    def _prune(self, now: float) -> None:
        expired = [key for key, (_part_index, expires) in self._entries.items() if expires <= now]
        for key in expired:
            self._entries.pop(key, None)


@dataclass(frozen=True)
class InlineAttachmentPart:
    attachment_id: str
    part_index: int
    content: bytes


class GmailProvider:
    def __init__(
        self, settings: Settings, transport: httpx.AsyncBaseTransport | None = None
    ) -> None:
        self.settings = settings
        timeout = httpx.Timeout(settings.provider_timeout_seconds)
        self.client = httpx.AsyncClient(
            timeout=timeout,
            follow_redirects=False,
            transport=transport,
        )
        minimum_inline_entries = (
            settings.max_mailbox_messages * settings.max_attachments_per_message
        )
        self.inline_attachment_cache = InlineAttachmentCache(
            settings.mailbox_token_cache_ttl_seconds,
            max(settings.mailbox_token_cache_max_entries, minimum_inline_entries),
        )

    async def close(self) -> None:
        await self.client.aclose()

    def _require_redirect_uri(self, redirect_uri: str) -> None:
        if redirect_uri != self.settings.gmail_oauth_redirect_uri:
            raise ServiceError(400, "oauth_redirect_uri_mismatch")

    def authorization_url(self, request: AuthorizationUrlRequest) -> AuthorizationUrlResult:
        self._require_redirect_uri(request.redirect_uri)
        if OAUTH_STATE_RE.fullmatch(request.state) is None:
            raise ServiceError(400, "invalid_request")
        query = urlencode(
            {
                "client_id": self.settings.gmail_oauth_client_id,
                "redirect_uri": request.redirect_uri,
                "response_type": "code",
                "scope": GMAIL_READONLY_SCOPE,
                "access_type": "offline",
                "prompt": "consent",
                "state": request.state,
            }
        )
        return AuthorizationUrlResult(
            authorization_url=f"{self.settings.gmail_oauth_authorization_url}?{query}"
        )

    async def exchange(self, request: ExchangeRequest) -> ExchangeResult:
        self._require_redirect_uri(request.redirect_uri)
        payload = await self._json_request(
            "POST",
            self.settings.gmail_oauth_token_url,
            headers={"Accept": "application/json"},
            data={
                "client_id": self.settings.gmail_oauth_client_id,
                "client_secret": self.settings.gmail_oauth_client_secret,
                "code": request.code,
                "grant_type": "authorization_code",
                "redirect_uri": request.redirect_uri,
            },
        )
        access_token = payload.get("access_token")
        refresh_token = payload.get("refresh_token")
        expires_in = payload.get("expires_in")
        if (
            not isinstance(access_token, str)
            or not access_token
            or len(access_token) > 8192
            or not isinstance(refresh_token, str)
            or not refresh_token
            or len(refresh_token) > 8192
        ):
            raise ServiceError(502, "oauth_refresh_token_required")
        if not isinstance(expires_in, (int, float)) or expires_in <= 0 or expires_in > 86400:
            raise ServiceError(502, "provider_response_invalid")
        expires_at = (
            (datetime.now(UTC) + timedelta(seconds=int(expires_in)))
            .isoformat()
            .replace("+00:00", "Z")
        )
        return ExchangeResult(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_at=expires_at,
        )

    async def revoke(self, request: RevokeRequest) -> None:
        try:
            response = await self.client.post(
                self.settings.gmail_oauth_revocation_url,
                headers={"Accept": "application/json"},
                data={"token": request.token},
            )
        except (httpx.TimeoutException, httpx.NetworkError) as error:
            raise ServiceError(503, "provider_unavailable") from error
        if 300 <= response.status_code < 400:
            raise ServiceError(502, "provider_redirect_rejected")
        if response.status_code < 200 or response.status_code >= 300:
            raise ServiceError(502, "provider_request_failed")

    async def _json_request(
        self,
        method: str,
        url: str,
        *,
        headers: dict[str, str] | None = None,
        data: dict[str, str] | None = None,
        params: dict[str, str | int] | None = None,
        max_response_bytes: int | None = None,
    ) -> dict[str, Any]:
        response_limit = max_response_bytes or self.settings.max_provider_response_bytes
        try:
            async with self.client.stream(
                method, url, headers=headers, data=data, params=params
            ) as response:
                if 300 <= response.status_code < 400:
                    raise ServiceError(502, "provider_redirect_rejected")
                if response.status_code < 200 or response.status_code >= 300:
                    raise ServiceError(502, "provider_request_failed")
                declared = response.headers.get("content-length")
                if declared is not None and int(declared) > response_limit:
                    raise ServiceError(502, "provider_response_too_large")
                raw = bytearray()
                async for chunk in response.aiter_bytes():
                    raw.extend(chunk)
                    if len(raw) > response_limit:
                        raise ServiceError(502, "provider_response_too_large")
        except ServiceError:
            raise
        except (httpx.TimeoutException, httpx.NetworkError) as error:
            raise ServiceError(503, "provider_unavailable") from error
        except (ValueError, httpx.HTTPError) as error:
            raise ServiceError(502, "provider_response_invalid") from error

        try:
            parsed = json.loads(raw)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ServiceError(502, "provider_response_invalid") from error
        if not isinstance(parsed, dict):
            raise ServiceError(502, "provider_response_invalid")
        return parsed

    @staticmethod
    def _user_id(connector_ref: str) -> str:
        match = CONNECTOR_REF_RE.fullmatch(connector_ref)
        if match is None:
            raise ServiceError(400, "unsupported_connector_ref")
        user_id = match.group(1)
        if user_id != "me" and (".." in user_id or user_id.startswith(".")):
            raise ServiceError(400, "unsupported_connector_ref")
        return user_id

    async def refresh(self, request: RefreshRequest) -> RefreshResult:
        self._user_id(request.connector_ref)
        payload = await self._json_request(
            "POST",
            self.settings.gmail_oauth_token_url,
            headers={"Accept": "application/json"},
            data={
                "client_id": self.settings.gmail_oauth_client_id,
                "client_secret": self.settings.gmail_oauth_client_secret,
                "refresh_token": request.refresh_token,
                "grant_type": "refresh_token",
            },
        )
        access_token = payload.get("access_token")
        expires_in = payload.get("expires_in")
        if not isinstance(access_token, str) or not access_token or len(access_token) > 8192:
            raise ServiceError(502, "provider_response_invalid")
        if not isinstance(expires_in, (int, float)) or expires_in <= 0 or expires_in > 86400:
            raise ServiceError(502, "provider_response_invalid")
        expires_at = (
            (datetime.now(UTC) + timedelta(seconds=int(expires_in)))
            .isoformat()
            .replace("+00:00", "Z")
        )
        rotated = payload.get("refresh_token")
        return RefreshResult(
            access_token=access_token,
            refresh_token=rotated if isinstance(rotated, str) and rotated else None,
            expires_at=expires_at,
        )

    async def poll(self, request: PollRequest, access_token: str) -> list[Message]:
        user_id = quote(self._user_id(request.connector_ref), safe="")
        auth = {"Authorization": f"Bearer {access_token}", "Accept": "application/json"}
        message_pages: list[list[Message]] = []
        seen_message_ids: set[str] = set()
        seen_page_tokens: set[str] = set()
        page_token: str | None = None
        candidate_count = 0
        inline_parts_by_message: dict[str, list[InlineAttachmentPart]] = {}

        for _page_number in range(self.settings.max_mailbox_pages_per_poll):
            remaining_candidates = self.settings.max_mailbox_candidates_per_poll - candidate_count
            if remaining_candidates <= 0:
                break
            page_size = min(self.settings.max_mailbox_messages, remaining_candidates)
            params: dict[str, str | int] = {
                "maxResults": page_size,
                "q": GMAIL_ATTACHMENT_QUERY,
            }
            if page_token is not None:
                params["pageToken"] = page_token

            listing = await self._json_request(
                "GET",
                f"{self.settings.gmail_api_base_url}/users/{user_id}/messages",
                headers=auth,
                params=params,
            )
            raw_messages = listing.get("messages", [])
            if not isinstance(raw_messages, list) or len(raw_messages) > page_size:
                raise ServiceError(502, "provider_response_invalid")

            page_message_ids: list[str] = []
            for listed in raw_messages:
                if not isinstance(listed, dict) or not isinstance(listed.get("id"), str):
                    raise ServiceError(502, "provider_response_invalid")
                message_id = listed["id"]
                if PROVIDER_ID_RE.fullmatch(message_id) is None or message_id in seen_message_ids:
                    raise ServiceError(502, "provider_response_invalid")
                seen_message_ids.add(message_id)
                candidate_count += 1
                page_message_ids.append(message_id)

            page_messages: list[Message] = []
            details = await self._fetch_page_message_details(page_message_ids, user_id, auth)
            for message, inline_parts in details:
                if message.attachments:
                    page_messages.append(message)
                    inline_parts_by_message[message.message_id] = inline_parts
            message_pages.append(page_messages)

            next_page_token = listing.get("nextPageToken")
            if next_page_token is None:
                break
            if not self._valid_page_token(next_page_token) or next_page_token in seen_page_tokens:
                raise ServiceError(502, "provider_response_invalid")
            seen_page_tokens.add(next_page_token)
            page_token = next_page_token

        selected = self._page_fair_messages(message_pages)
        cache_entries: list[tuple[InlineCacheKey, int]] = []
        for message in selected:
            for inline_part in inline_parts_by_message.get(message.message_id, []):
                cache_entries.append(
                    (
                        self._inline_cache_key(
                            request,
                            message.message_id,
                            inline_part.attachment_id,
                        ),
                        inline_part.part_index,
                    )
                )
        await self.inline_attachment_cache.put_many(cache_entries)
        return selected

    async def _fetch_page_message_details(
        self,
        message_ids: list[str],
        user_id: str,
        auth: dict[str, str],
    ) -> list[tuple[Message, list[InlineAttachmentPart]]]:
        """Fetch one Gmail listing page with a fixed worker pool and stable ordering."""

        if not message_ids:
            return []

        results: dict[int, tuple[Message, list[InlineAttachmentPart]]] = {}
        next_index = 0

        async def worker() -> None:
            nonlocal next_index
            while next_index < len(message_ids):
                index = next_index
                next_index += 1
                message_id = message_ids[index]
                raw = await self._json_request(
                    "GET",
                    f"{self.settings.gmail_api_base_url}/users/{user_id}/messages/"
                    f"{quote(message_id, safe='')}",
                    headers=auth,
                    params={"format": "full", "fields": GMAIL_MESSAGE_DETAIL_FIELDS},
                    max_response_bytes=self.settings.max_gmail_message_detail_response_bytes,
                )
                message, inline_parts = self._message_from_gmail(raw)
                if message.message_id != message_id:
                    raise ServiceError(502, "provider_response_invalid")
                results[index] = (message, inline_parts)

        worker_count = min(self.settings.gmail_detail_fetch_concurrency, len(message_ids))
        workers = [asyncio.create_task(worker()) for _worker in range(worker_count)]
        try:
            await asyncio.gather(*workers)
        except BaseException:
            for task in workers:
                task.cancel()
            await asyncio.gather(*workers, return_exceptions=True)
            raise

        if len(results) != len(message_ids):
            raise ServiceError(502, "provider_response_invalid")
        return [results[index] for index in range(len(message_ids))]

    @staticmethod
    def _valid_page_token(value: Any) -> bool:
        return (
            isinstance(value, str)
            and 1 <= len(value) <= 2048
            and value.isascii()
            and all(33 <= ord(character) <= 126 for character in value)
        )

    def _page_fair_messages(self, pages: list[list[Message]]) -> list[Message]:
        """Bound the response while ensuring each inspected Gmail page gets a turn."""

        selected: list[Message] = []
        offset = 0
        while len(selected) < self.settings.max_mailbox_messages:
            added = False
            for page in pages:
                if offset < len(page):
                    selected.append(page[offset])
                    added = True
                    if len(selected) == self.settings.max_mailbox_messages:
                        break
            if not added:
                break
            offset += 1
        return selected

    def _message_from_gmail(
        self, raw: dict[str, Any]
    ) -> tuple[Message, list[InlineAttachmentPart]]:
        message_id = raw.get("id")
        payload = raw.get("payload")
        internal_date = raw.get("internalDate")
        if (
            not isinstance(message_id, str)
            or PROVIDER_ID_RE.fullmatch(message_id) is None
            or not isinstance(payload, dict)
            or not isinstance(internal_date, str)
            or not internal_date.isdigit()
        ):
            raise ServiceError(502, "provider_response_invalid")
        try:
            received_at = (
                datetime.fromtimestamp(int(internal_date) / 1000, UTC)
                .isoformat()
                .replace("+00:00", "Z")
            )
        except (OverflowError, OSError, ValueError) as error:
            raise ServiceError(502, "provider_response_invalid") from error

        sender = ""
        headers = payload.get("headers", [])
        if not isinstance(headers, list):
            raise ServiceError(502, "provider_response_invalid")
        for header in headers:
            if isinstance(header, dict) and str(header.get("name", "")).lower() == "from":
                sender = parseaddr(str(header.get("value", "")))[1].strip().lower()
                break

        attachments: list[Attachment] = []
        inline_parts: list[InlineAttachmentPart] = []
        for part_index, part in enumerate(self._walk_parts(payload)):
            body = part.get("body")
            filename = part.get("filename")
            has_filename = isinstance(filename, str) and filename.strip() != ""
            if not isinstance(body, dict):
                if has_filename:
                    raise ServiceError(502, "provider_response_invalid")
                continue

            attachment_id = body.get("attachmentId")
            encoded = body.get("data")
            if attachment_id not in (None, ""):
                if (
                    not isinstance(attachment_id, str)
                    or PROVIDER_ID_RE.fullmatch(attachment_id) is None
                    or encoded not in (None, "")
                ):
                    raise ServiceError(502, "provider_response_invalid")
                self._validated_declared_size(body.get("size"), self.settings.max_attachment_bytes)
            elif encoded is not None and has_filename:
                content = self._decode_gmail_data(
                    encoded,
                    body.get("size"),
                    self.settings.max_attachment_bytes,
                )
                attachment_id = self._inline_attachment_id(message_id, part_index)
                inline_parts.append(
                    InlineAttachmentPart(
                        attachment_id=attachment_id,
                        part_index=part_index,
                        content=content,
                    )
                )
            elif has_filename:
                raise ServiceError(502, "provider_response_invalid")
            else:
                continue

            safe_filename = self._safe_provider_filename(filename)
            declared_mime = str(part.get("mimeType", "application/octet-stream"))[:128]
            attachments.append(
                Attachment(
                    attachment_id=attachment_id,
                    filename=safe_filename,
                    declared_mime=declared_mime,
                    received_at=received_at,
                )
            )
            if len(attachments) > self.settings.max_attachments_per_message:
                raise ServiceError(502, "provider_response_too_large")
        return (
            Message(
                message_id=message_id,
                sender_address=sender,
                received_at=received_at,
                attachments=attachments,
            ),
            inline_parts,
        )

    @staticmethod
    def _inline_attachment_id(message_id: str, part_index: int) -> str:
        digest = hashlib.sha256(f"{message_id}\0{part_index}".encode()).hexdigest()
        return f"inline:{digest}"

    @staticmethod
    def _inline_cache_key(
        request: PollRequest | FetchRequest,
        message_id: str,
        attachment_id: str,
    ) -> InlineCacheKey:
        return (*cache_key(request), message_id, attachment_id)

    @staticmethod
    def _validated_declared_size(value: Any, max_bytes: int) -> int | None:
        if value is None:
            return None
        if type(value) is not int or value < 0:
            raise ServiceError(502, "provider_response_invalid")
        if value > max_bytes:
            raise ServiceError(502, "provider_response_too_large")
        return value

    @classmethod
    def _decode_gmail_data(cls, encoded: Any, declared_size: Any, max_bytes: int) -> bytes:
        if not isinstance(encoded, str) or GMAIL_BASE64URL_RE.fullmatch(encoded) is None:
            raise ServiceError(502, "provider_response_invalid")
        if len(encoded) > ((max_bytes + 2) // 3) * 4:
            raise ServiceError(502, "provider_response_too_large")
        size = cls._validated_declared_size(declared_size, max_bytes)
        unpadded = encoded.rstrip("=")
        encoded_padding = len(encoded) - len(unpadded)
        expected_padding = (-len(unpadded)) % 4
        if (
            "=" in unpadded
            or len(unpadded) % 4 == 1
            or encoded_padding not in (0, expected_padding)
        ):
            raise ServiceError(502, "provider_response_invalid")
        try:
            padded = unpadded + "=" * (-len(unpadded) % 4)
            content = base64.b64decode(padded, altchars=b"-_", validate=True)
        except (ValueError, base64.binascii.Error) as error:
            raise ServiceError(502, "provider_response_invalid") from error
        if len(content) > max_bytes:
            raise ServiceError(502, "provider_response_too_large")
        if not content or (size is not None and len(content) != size):
            raise ServiceError(502, "provider_response_invalid")
        return content

    @staticmethod
    def _walk_parts(root: dict[str, Any]) -> Iterable[dict[str, Any]]:
        pending = [root]
        seen = 0
        while pending:
            part = pending.pop()
            seen += 1
            if seen > 200:
                raise ServiceError(502, "provider_response_too_large")
            yield part
            children = part.get("parts", [])
            if children is None:
                children = []
            if not isinstance(children, list) or not all(
                isinstance(child, dict) for child in children
            ):
                raise ServiceError(502, "provider_response_invalid")
            pending.extend(reversed(children))

    @staticmethod
    def _safe_provider_filename(value: Any) -> str:
        if not isinstance(value, str):
            return "statement"
        cleaned = "".join(character for character in value if 32 <= ord(character) != 127).strip()
        return cleaned[:255] or "statement"

    async def fetch_attachment(
        self, request: FetchRequest, access_token: str, max_bytes: int
    ) -> bytes:
        user_id = quote(self._user_id(request.connector_ref), safe="")
        if PROVIDER_ID_RE.fullmatch(request.message_id) is None:
            raise ServiceError(400, "invalid_provider_identity")
        if INLINE_ATTACHMENT_ID_RE.fullmatch(request.attachment_id) is not None:
            return await self._fetch_inline_attachment(request, access_token, max_bytes, user_id)
        if PROVIDER_ID_RE.fullmatch(request.attachment_id) is None:
            raise ServiceError(400, "invalid_provider_identity")
        payload = await self._json_request(
            "GET",
            f"{self.settings.gmail_api_base_url}/users/{user_id}/messages/"
            f"{quote(request.message_id, safe='')}/attachments/"
            f"{quote(request.attachment_id, safe='')}",
            headers={"Authorization": f"Bearer {access_token}", "Accept": "application/json"},
        )
        return self._decode_gmail_data(payload.get("data"), payload.get("size"), max_bytes)

    async def _fetch_inline_attachment(
        self,
        request: FetchRequest,
        access_token: str,
        max_bytes: int,
        user_id: str,
    ) -> bytes:
        part_index = await self.inline_attachment_cache.get(
            self._inline_cache_key(request, request.message_id, request.attachment_id)
        )
        raw = await self._json_request(
            "GET",
            f"{self.settings.gmail_api_base_url}/users/{user_id}/messages/"
            f"{quote(request.message_id, safe='')}",
            headers={"Authorization": f"Bearer {access_token}", "Accept": "application/json"},
            params={"format": "full", "fields": GMAIL_MESSAGE_DETAIL_FIELDS},
            max_response_bytes=self.settings.max_gmail_message_detail_response_bytes,
        )
        message, inline_parts = self._message_from_gmail(raw)
        if message.message_id != request.message_id:
            raise ServiceError(502, "provider_response_invalid")
        for inline_part in inline_parts:
            if (
                inline_part.part_index == part_index
                and inline_part.attachment_id == request.attachment_id
            ):
                if len(inline_part.content) > max_bytes:
                    raise ServiceError(502, "provider_response_too_large")
                return inline_part.content
        raise ServiceError(400, "invalid_provider_identity")
