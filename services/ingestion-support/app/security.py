from __future__ import annotations

import hashlib
import hmac
import json
import re
from collections.abc import AsyncIterator
from typing import Any

from fastapi import Request

from .errors import ServiceError


SAFE_FILENAME_RE = re.compile(r"^[^\x00-\x1f\x7f]{1,255}$")
SHA256_RE = re.compile(r"^[0-9a-fA-F]{64}$")


def require_bearer(request: Request, expected: str) -> None:
    header = request.headers.get("authorization", "")
    prefix = "Bearer "
    supplied = header[len(prefix) :] if header.startswith(prefix) else ""
    if not supplied or not hmac.compare_digest(supplied.encode(), expected.encode()):
        raise ServiceError(401, "unauthorized")


def media_type(request: Request) -> str:
    return request.headers.get("content-type", "").split(";", 1)[0].strip().lower()


def require_media_type(request: Request, expected: str) -> None:
    if media_type(request) != expected:
        raise ServiceError(415, "unsupported_media_type")


def validated_filename(value: str | None) -> str:
    if value is None or not SAFE_FILENAME_RE.fullmatch(value) or value in {".", ".."}:
        raise ServiceError(400, "invalid_filename")
    return value


async def bounded_chunks(request: Request, limit: int) -> AsyncIterator[bytes]:
    content_length = request.headers.get("content-length")
    if content_length is not None:
        try:
            if int(content_length) > limit or int(content_length) < 0:
                raise ServiceError(413, "body_too_large")
        except ValueError as error:
            raise ServiceError(400, "invalid_content_length") from error

    total = 0
    async for chunk in request.stream():
        total += len(chunk)
        if total > limit:
            raise ServiceError(413, "body_too_large")
        if chunk:
            yield chunk


async def read_bounded_body(request: Request, limit: int) -> bytes:
    body = bytearray()
    async for chunk in bounded_chunks(request, limit):
        body.extend(chunk)
    if not body:
        raise ServiceError(400, "empty_body")
    return bytes(body)


async def read_json_object(request: Request, limit: int) -> dict[str, Any]:
    require_media_type(request, "application/json")
    raw = await read_bounded_body(request, limit)
    try:
        parsed = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ServiceError(400, "invalid_json") from error
    if not isinstance(parsed, dict):
        raise ServiceError(400, "invalid_json")
    return parsed


def require_sha256(value: str | None) -> str:
    if value is None or not SHA256_RE.fullmatch(value):
        raise ServiceError(400, "invalid_digest")
    return value.lower()


def verify_sha256(body: bytes, expected: str) -> None:
    actual = hashlib.sha256(body).hexdigest()
    if not hmac.compare_digest(actual, expected):
        raise ServiceError(422, "digest_mismatch")
