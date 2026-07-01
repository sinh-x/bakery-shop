"""Global exception handler for Baker API."""
from fastapi import Request
from fastapi.responses import JSONResponse

from baker.logging import log_to_db, log_to_file, logger
from baker.utils.time import now_utc


async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Catch unhandled exceptions, log safely, return 500."""

    # Extract device headers and ref context
    device_model = request.headers.get("x-device-model", "")
    app_version = request.headers.get("x-app-version", "")
    os_version = request.headers.get("x-os-version", "")
    client_ip = request.client.host if request.client else ""
    ctx = getattr(request.state, "_log_ctx", {})

    entry = {
        "timestamp": now_utc(),
        "level": "ERROR",
        "method": request.method,
        "path": request.url.path,
        "status_code": 500,
        "duration_ms": 0,
        "client_ip": client_ip,
        "device_model": device_model,
        "app_version": app_version,
        "os_version": os_version,
        "ref_type": ctx.get("ref_type", ""),
        "ref_id": ctx.get("ref_id"),
        "message": f"Unhandled exception: {type(exc).__name__}: {exc}",
        "detail": {
            "error_type": type(exc).__name__,
            "error_message": str(exc),
        },
    }

    logger.exception("Unhandled exception on %s %s", request.method, request.url.path)
    log_to_file(entry)
    log_to_db(entry)

    return JSONResponse(
        status_code=500,
        content={"detail": "Lỗi máy chủ nội bộ"},
    )
