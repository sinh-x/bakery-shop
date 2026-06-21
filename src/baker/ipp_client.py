"""IPP (Internet Printing Protocol) client for sending TSPL print jobs to CUPS.

Implements the IPP Print-Job operation (RFC 8010/8011) using raw binary
encoding over HTTP. Sends pre-rendered TSPL bytes to a CUPS IPP endpoint
(typically Lily's NixOS CUPS server over Tailscale).

Usage:
    from baker.ipp_client import send_tspl_to_ipp

    send_tspl_to_ipp(tspl_bytes, "http://lily:631/printers/Y41BT")
"""

import http.client
import struct
import time
import urllib.parse
from typing import List, Optional, Tuple

IPP_VERSION = b"\x02\x00"
OP_PRINT_JOB = b"\x00\x02"

TAG_OPERATION_ATTRS = 0x01
TAG_END_OF_ATTRS = 0x03

VTAG_NAME_WITHOUT_LANGUAGE = 0x42
VTAG_KEYWORD = 0x44
VTAG_URI = 0x45
VTAG_CHARSET = 0x47
VTAG_NATURAL_LANGUAGE = 0x48
VTAG_MIME_MEDIA_TYPE = 0x49

IPP_STATUS_SUCCESSFUL_OK = 0x0000


class IppError(Exception):
    """Raised when the IPP response indicates a failure status."""

    def __init__(self, status_code: int, message: str = ""):
        self.status_code = status_code
        super().__init__(f"IPP error 0x{status_code:04X}: {message}" if message else f"IPP error 0x{status_code:04X}")


class IppHttpError(Exception):
    """Raised when the HTTP transport fails (non-200 response)."""

    def __init__(self, http_status: int, body: bytes = b""):
        self.http_status = http_status
        self.body = body
        super().__init__(f"HTTP {http_status}")


class IppConnectionError(Exception):
    """Raised when a connection cannot be established."""


def _attr_value_pair(vtag: int, name: str, value: bytes) -> bytes:
    """Encode a single IPP attribute as a tag-length-value sequence."""
    name_encoded = name.encode("ascii")
    return (
        struct.pack("!B", vtag)
        + struct.pack("!H", len(name_encoded))
        + name_encoded
        + struct.pack("!H", len(value))
        + value
    )


def _build_ipp_print_job_request(tspl_bytes: bytes, ipp_url: str) -> bytes:
    """Build a raw IPP Print-Job request binary payload.

    Encodes the IPP request header + operation attributes group +
    document data as a single binary blob ready for HTTP POST with
    Content-Type: application/ipp.

    Args:
        tspl_bytes: Pre-rendered TSPL command bytes to send to the printer.
        ipp_url: Full IPP printer URI (e.g. http://lily:631/printers/Y41BT).

    Returns:
        Complete IPP Print-Job request bytes.
    """
    request_id = 1

    buf = bytearray()

    # --- IPP Request Header ---
    buf.extend(IPP_VERSION)
    buf.extend(OP_PRINT_JOB)
    buf.extend(struct.pack("!I", request_id))

    # --- Operation Attributes Group ---
    buf.append(TAG_OPERATION_ATTRS)

    buf.extend(_attr_value_pair(VTAG_CHARSET, "attributes-charset", b"utf-8"))
    buf.extend(_attr_value_pair(VTAG_NATURAL_LANGUAGE, "attributes-natural-language", b"en-us"))
    buf.extend(_attr_value_pair(VTAG_URI, "printer-uri", ipp_url.encode("ascii")))
    buf.extend(_attr_value_pair(VTAG_NAME_WITHOUT_LANGUAGE, "requesting-user-name", b"baker"))
    buf.extend(_attr_value_pair(VTAG_NAME_WITHOUT_LANGUAGE, "job-name", b"Bakery Receipt"))
    buf.extend(_attr_value_pair(VTAG_MIME_MEDIA_TYPE, "document-format", b"application/octet-stream"))

    # --- End of Attributes + Document Data ---
    buf.append(TAG_END_OF_ATTRS)
    buf.extend(tspl_bytes)

    return bytes(buf)


def _parse_ipp_status(response_body: bytes) -> Tuple[int, int]:
    """Parse the IPP response body and extract the status code and request ID.

    Args:
        response_body: Full IPP response binary payload.

    Returns:
        Tuple of (status_code, request_id).

    Raises:
        IppError: If the response body is too short to contain a valid header.
    """
    if len(response_body) < 8:
        raise IppError(0, "Response too short for IPP header")
    status_code = struct.unpack("!H", response_body[2:4])[0]
    request_id = struct.unpack("!I", response_body[4:8])[0]
    return status_code, request_id


def _parse_url(ipp_url: str) -> Tuple[str, int, str]:
    """Parse an IPP URL into (host, port, path) components.

    Args:
        ipp_url: Full URL (e.g. http://lily:631/printers/Y41BT).

    Returns:
        Tuple of (host, port, path).
    """
    parsed = urllib.parse.urlparse(ipp_url)
    host = parsed.hostname or "localhost"
    port = parsed.port or 631
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query
    return host, port, path


def _send_single_request(tspl_bytes: bytes, ipp_url: str, timeout: float = 10.0) -> bytes:
    """Send a single IPP Print-Job request and return the response body.

    Args:
        tspl_bytes: TSPL command bytes.
        ipp_url: IPP printer URI.
        timeout: HTTP connection timeout in seconds.

    Returns:
        IPP response body bytes.

    Raises:
        IppConnectionError: On connection failure.
        IppHttpError: On non-200 HTTP response.
        IppError: On IPP-level error status.
    """
    host, port, path = _parse_url(ipp_url)
    request_body = _build_ipp_print_job_request(tspl_bytes, ipp_url)

    try:
        conn = http.client.HTTPConnection(host, port, timeout=timeout)
        conn.putrequest("POST", path)
        conn.putheader("Content-Type", "application/ipp")
        conn.putheader("Content-Length", str(len(request_body)))
        conn.endheaders()
        conn.send(request_body)
        response = conn.getresponse()
        response_body = response.read()
        conn.close()
    except (OSError, http.client.HTTPException) as e:
        raise IppConnectionError(str(e)) from e

    if response.status != 200:
        raise IppHttpError(response.status, response_body)

    status_code, _ = _parse_ipp_status(response_body)
    if status_code != IPP_STATUS_SUCCESSFUL_OK:
        raise IppError(status_code)

    return response_body


def send_tspl_to_ipp(
    tspl_bytes: bytes,
    ipp_url: str,
    *,
    retries: int = 3,
    retry_delay: float = 1.0,
    timeout: float = 10.0,
) -> None:
    """Send pre-rendered TSPL bytes to a CUPS IPP endpoint.

    Constructs an IPP Print-Job request with the TSPL payload, sends it
    via HTTP POST, and verifies the response indicates success. Retries
    on transient connection failures.

    Args:
        tspl_bytes: Pre-rendered TSPL command bytes (from png_to_tspl).
        ipp_url: Full IPP printer URI (e.g. http://lily:631/printers/Y41BT).
        retries: Maximum number of attempts (default 3).
        retry_delay: Seconds to wait between retries (default 1.0).
        timeout: HTTP connection timeout in seconds (default 10.0).

    Raises:
        IppConnectionError: If all retry attempts fail on connection.
        IppHttpError: On non-200 HTTP response (not retried).
        IppError: On IPP-level error status (not retried).
    """
    last_exception: Optional[Exception] = None

    for attempt in range(1, retries + 1):
        try:
            _send_single_request(tspl_bytes, ipp_url, timeout=timeout)
            return
        except IppConnectionError as e:
            last_exception = e
            if attempt < retries:
                time.sleep(retry_delay)
        except (IppHttpError, IppError):
            raise

    raise IppConnectionError(
        f"Failed after {retries} attempts: {last_exception}"
    ) from last_exception
