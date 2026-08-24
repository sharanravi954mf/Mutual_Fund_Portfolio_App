from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse

from .diagnostics import log_service_error


class ServiceError(Exception):
    def __init__(self, status_code: int, code: str) -> None:
        super().__init__(code)
        self.status_code = status_code
        self.code = code


async def service_error_handler(request: Request, error: ServiceError) -> JSONResponse:
    log_service_error(
        request_id=getattr(request.state, "request_id", "unavailable"),
        error_code=error.code,
        status=error.status_code,
    )
    headers = {"Cache-Control": "no-store"}
    if error.status_code == 503:
        headers["Retry-After"] = "5"
    return JSONResponse(
        status_code=error.status_code,
        content={"error": {"code": error.code}},
        headers=headers,
    )
