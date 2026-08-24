from __future__ import annotations

import asyncio
import json
import time
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response
from starlette.middleware.trustedhost import TrustedHostMiddleware

from .clamav import ClamavScanner, MalwareScanner
from .config import Settings, get_settings
from .diagnostics import (
    configure_application_logging,
    log_http_request,
    log_mailbox_poll_outcome,
)
from .errors import ServiceError, service_error_handler
from .mailbox import (
    AccessTokenCache,
    AuthorizationUrlRequest,
    AuthorizationUrlResult,
    ExchangeRequest,
    ExchangeResult,
    FetchRequest,
    GmailProvider,
    MailboxProvider,
    PollRequest,
    RefreshRequest,
    RefreshResult,
    RevokeRequest,
    cache_key,
    validate_model,
)
from .pdf_extractor import LAYOUTS, RegistrarPdfExtractor
from .security import (
    read_bounded_body,
    read_json_object,
    require_bearer,
    require_media_type,
    require_sha256,
    validated_filename,
    verify_sha256,
)

KNOWN_PATHS = frozenset(
    {
        "/health",
        "/ready",
        "/oauth/refresh",
        "/oauth/authorization-url",
        "/oauth/exchange",
        "/oauth/revoke",
        "/poll",
        "/attachments/fetch",
        "/pdf/extract",
        "/malware/scan",
    }
)


def _bounded_json_response(payload: Any, max_bytes: int) -> JSONResponse:
    encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    if len(encoded) > max_bytes:
        raise ServiceError(502, "response_too_large")
    return JSONResponse(payload, headers={"Cache-Control": "no-store"})


def create_app(
    settings: Settings | None = None,
    mailbox_provider: MailboxProvider | None = None,
    malware_scanner: MalwareScanner | None = None,
) -> FastAPI:
    configure_application_logging()
    config = settings or get_settings()
    provider = mailbox_provider or GmailProvider(config)
    scanner = malware_scanner or ClamavScanner(
        config.clamav_host, config.clamav_port, config.clamav_timeout_seconds
    )
    token_cache = AccessTokenCache(
        config.mailbox_token_cache_ttl_seconds,
        config.mailbox_token_cache_max_entries,
    )
    pdf_extractor = RegistrarPdfExtractor(
        config.max_pdf_rows,
        config.max_pdf_response_bytes,
    )

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        yield
        close = getattr(provider, "close", None)
        if close is not None:
            await close()

    app = FastAPI(
        title="Money Bowl ingestion support",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=config.trusted_hosts)
    app.add_exception_handler(ServiceError, service_error_handler)

    @app.middleware("http")
    async def sanitized_request_log(request: Request, call_next):
        started = time.monotonic()
        request_id = uuid.uuid4().hex
        request.state.request_id = request_id
        route = request.url.path if request.url.path in KNOWN_PATHS else "unknown"
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            response.headers["X-Request-ID"] = request_id
            return response
        finally:
            log_http_request(
                request_id=request_id,
                method=request.method,
                route=route,
                status=status,
                duration_ms=round((time.monotonic() - started) * 1000),
            )

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(
        _request: Request, _error: RequestValidationError
    ) -> JSONResponse:
        return JSONResponse(status_code=400, content={"error": {"code": "invalid_request"}})

    @app.exception_handler(TimeoutError)
    async def timeout_error_handler(_request: Request, _error: TimeoutError) -> JSONResponse:
        return JSONResponse(
            status_code=408,
            content={"error": {"code": "request_timeout"}},
            headers={"Cache-Control": "no-store"},
        )

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/ready")
    async def ready() -> JSONResponse:
        if not await scanner.ready():
            raise ServiceError(503, "not_ready")
        return JSONResponse({"status": "ready"}, headers={"Cache-Control": "no-store"})

    @app.post("/oauth/refresh")
    async def oauth_refresh(request: Request) -> JSONResponse:
        require_bearer(request, config.mailbox_connector_service_token)
        async with asyncio.timeout(config.request_body_timeout_seconds):
            payload = await read_json_object(request, config.max_json_body_bytes)
        parsed = validate_model(RefreshRequest, payload)
        result: RefreshResult = await provider.refresh(parsed)
        await token_cache.put(cache_key(parsed), result.access_token)
        return _bounded_json_response(
            result.model_dump(exclude_none=True), config.max_provider_response_bytes
        )

    @app.post("/oauth/authorization-url")
    async def oauth_authorization_url(request: Request) -> JSONResponse:
        require_bearer(request, config.mailbox_connector_service_token)
        async with asyncio.timeout(config.request_body_timeout_seconds):
            payload = await read_json_object(request, config.max_json_body_bytes)
        parsed = validate_model(AuthorizationUrlRequest, payload)
        result: AuthorizationUrlResult = provider.authorization_url(parsed)
        return _bounded_json_response(result.model_dump(), 4096)

    @app.post("/oauth/exchange")
    async def oauth_exchange(request: Request) -> JSONResponse:
        require_bearer(request, config.mailbox_connector_service_token)
        async with asyncio.timeout(config.request_body_timeout_seconds):
            payload = await read_json_object(request, config.max_json_body_bytes)
        parsed = validate_model(ExchangeRequest, payload)
        result: ExchangeResult = await provider.exchange(parsed)
        return _bounded_json_response(result.model_dump(), config.max_provider_response_bytes)

    @app.post("/oauth/revoke", status_code=204)
    async def oauth_revoke(request: Request) -> Response:
        require_bearer(request, config.mailbox_connector_service_token)
        async with asyncio.timeout(config.request_body_timeout_seconds):
            payload = await read_json_object(request, config.max_json_body_bytes)
        parsed = validate_model(RevokeRequest, payload)
        await provider.revoke(parsed)
        return Response(status_code=204, headers={"Cache-Control": "no-store"})

    @app.post("/poll")
    async def poll(request: Request) -> JSONResponse:
        require_bearer(request, config.mailbox_connector_service_token)
        oauth_token = request.headers.get("x-mailbox-oauth-token", "")
        if not oauth_token or len(oauth_token) > 8192:
            raise ServiceError(401, "mailbox_oauth_token_required")
        async with asyncio.timeout(config.request_body_timeout_seconds):
            payload = await read_json_object(request, config.max_json_body_bytes)
        parsed = validate_model(PollRequest, payload)
        messages = await provider.poll(parsed, oauth_token)
        log_mailbox_poll_outcome(
            request_id=request.state.request_id,
            message_count=len(messages),
            attachment_count=sum(len(message.attachments) for message in messages),
        )
        await token_cache.put(cache_key(parsed), oauth_token)
        response = {"messages": [message.model_dump(exclude_none=True) for message in messages]}
        return _bounded_json_response(response, config.max_provider_response_bytes)

    @app.post("/attachments/fetch")
    async def fetch_attachment(request: Request) -> Response:
        require_bearer(request, config.mailbox_connector_service_token)
        async with asyncio.timeout(config.request_body_timeout_seconds):
            payload = await read_json_object(request, config.max_json_body_bytes)
        parsed = validate_model(FetchRequest, payload)
        oauth_token = await token_cache.get(cache_key(parsed))
        content = await provider.fetch_attachment(parsed, oauth_token, config.max_attachment_bytes)
        if not content or len(content) > config.max_attachment_bytes:
            raise ServiceError(502, "provider_response_invalid")
        return Response(
            content=content,
            media_type="application/octet-stream",
            headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
        )

    @app.post("/pdf/extract")
    async def extract_pdf(request: Request) -> JSONResponse:
        require_bearer(request, config.pdf_text_extractor_service_token)
        require_media_type(request, "application/pdf")
        filename = validated_filename(request.headers.get("x-file-name"))
        registrar = request.headers.get("x-registrar", "")
        statement_format = request.headers.get("x-statement-format", "")
        if registrar not in LAYOUTS:
            raise ServiceError(400, "unsupported_registrar")
        async with asyncio.timeout(config.request_body_timeout_seconds):
            body = await read_bounded_body(request, config.max_pdf_bytes)
        try:
            payload = await asyncio.wait_for(
                asyncio.to_thread(
                    pdf_extractor.extract,
                    body,
                    registrar,
                    statement_format,
                ),
                timeout=config.pdf_timeout_seconds,
            )
        except TimeoutError as error:
            raise ServiceError(503, "pdf_extractor_timeout") from error
        del filename
        return _bounded_json_response(payload, config.max_pdf_response_bytes)

    @app.post("/malware/scan")
    async def scan_malware(request: Request) -> JSONResponse:
        require_bearer(request, config.malware_scanner_service_token)
        require_media_type(request, "application/octet-stream")
        validated_filename(request.headers.get("x-file-name"))
        digest = require_sha256(request.headers.get("x-content-sha256"))
        async with asyncio.timeout(config.request_body_timeout_seconds):
            body = await read_bounded_body(request, config.max_attachment_bytes)
        verify_sha256(body, digest)
        verdict = await scanner.scan(body)
        return _bounded_json_response(
            {"version": "moneybowl.malware-scan.v1", "verdict": verdict},
            4096,
        )

    return app


app = create_app()
