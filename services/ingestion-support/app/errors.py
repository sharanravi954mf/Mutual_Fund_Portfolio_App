from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse

from .diagnostics import DiagnosticReason, log_service_error


class ServiceError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        *,
        diagnostic_reason: DiagnosticReason | None = None,
    ) -> None:
        if diagnostic_reason is not None and not isinstance(
            diagnostic_reason, DiagnosticReason
        ):
            raise TypeError("diagnostic_reason must be allowlisted")
        super().__init__(code)
        self.status_code = status_code
        self.code = code
        self.diagnostic_reason = diagnostic_reason


async def service_error_handler(request: Request, error: ServiceError) -> JSONResponse:
    log_service_error(
        request_id=getattr(request.state, "request_id", "unavailable"),
        error_code=error.code,
        status=error.status_code,
        diagnostic_reason=error.diagnostic_reason,
    )
    headers = {"Cache-Control": "no-store"}
    if error.status_code == 503:
        headers["Retry-After"] = "5"
    return JSONResponse(
        status_code=error.status_code,
        content={"error": {"code": error.code}},
        headers=headers,
    )
