"""Request logging middleware for Baker API."""

import time
from datetime import datetime

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from baker.logging import log_to_db, log_to_file, logger


class LoggingMiddleware(BaseHTTPMiddleware):
    """Log every API request with metadata to file and DB."""

    async def dispatch(self, request: Request, call_next) -> Response:
        start = time.monotonic()

        # Initialize log context on request state
        request.state._log_ctx = {}

        response = await call_next(request)

        duration_ms = round((time.monotonic() - start) * 1000, 2)

        # Extract device headers
        device_model = request.headers.get("x-device-model", "")
        app_version = request.headers.get("x-app-version", "")
        os_version = request.headers.get("x-os-version", "")
        client_ip = request.client.host if request.client else ""

        # Get ref context set by route handlers
        ctx = getattr(request.state, "_log_ctx", {})

        level = "INFO"
        if response.status_code >= 500:
            level = "ERROR"
        elif response.status_code >= 400:
            level = "WARNING"

        entry = {
            "timestamp": datetime.now().isoformat(),
            "level": level,
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "duration_ms": duration_ms,
            "client_ip": client_ip,
            "device_model": device_model,
            "app_version": app_version,
            "os_version": os_version,
            "ref_type": ctx.get("ref_type", ""),
            "ref_id": ctx.get("ref_id"),
            "message": f"{request.method} {request.url.path} {response.status_code} {duration_ms}ms",
            "detail": {},
        }

        # Log to file and DB (non-blocking for the response)
        log_to_file(entry)
        log_to_db(entry)

        # Evaluate triggers
        try:
            from baker.triggers import evaluate_triggers
            evaluate_triggers(entry)
        except Exception:
            logger.warning("Trigger evaluation failed", exc_info=True)

        return response
