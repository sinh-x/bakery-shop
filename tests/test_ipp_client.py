"""Tests for IPP client module using mock CUPS HTTP server."""

import http.server
import struct
import socket
import threading
import time

import pytest

from baker.ipp_client import (
    IPP_VERSION,
    OP_PRINT_JOB,
    TAG_END_OF_ATTRS,
    TAG_OPERATION_ATTRS,
    VTAG_CHARSET,
    VTAG_MIME_MEDIA_TYPE,
    VTAG_NAME_WITHOUT_LANGUAGE,
    VTAG_NATURAL_LANGUAGE,
    VTAG_URI,
    IppConnectionError,
    IppError,
    IppHttpError,
    _attr_value_pair,
    _build_ipp_print_job_request,
    _parse_ipp_status,
    _parse_url,
    _send_single_request,
    send_tspl_to_ipp,
)


def _free_port():
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def _ipp_success_response(request_id=1):
    buf = bytearray()
    buf.extend(IPP_VERSION)
    buf.extend(b"\x00\x00")
    buf.extend(struct.pack("!I", request_id))
    buf.append(TAG_OPERATION_ATTRS)
    buf.extend(_attr_value_pair(VTAG_CHARSET, "attributes-charset", b"utf-8"))
    buf.append(TAG_END_OF_ATTRS)
    return bytes(buf)


def _ipp_error_response(status_code, request_id=1):
    buf = bytearray()
    buf.extend(IPP_VERSION)
    buf.extend(struct.pack("!H", status_code))
    buf.extend(struct.pack("!I", request_id))
    buf.append(TAG_OPERATION_ATTRS)
    buf.extend(_attr_value_pair(VTAG_CHARSET, "attributes-charset", b"utf-8"))
    buf.append(TAG_END_OF_ATTRS)
    return bytes(buf)


class MockIppHandler(http.server.BaseHTTPRequestHandler):

    def do_POST(self):
        content_type = self.headers.get("Content-Type", "")
        if content_type != "application/ipp":
            self.send_response(400)
            self.end_headers()
            return

        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        if hasattr(self.server, "response_code"):
            self.send_response(self.server.response_code)
            self.end_headers()
            self.wfile.write(b"")
            return

        if hasattr(self.server, "ipp_status_code"):
            resp = _ipp_error_response(self.server.ipp_status_code)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(resp)
            return

        self.send_response(200)
        self.end_headers()
        self.wfile.write(_ipp_success_response())

    def log_message(self, format, *args):
        pass


def _start_server(handler_class=None, **kwargs):
    # Retry bind on OSError to tolerate ephemeral-port races with other
    # pytest-xdist workers (DG-029 Post-UAT Item 1). _free_port() closes the
    # probe socket before the server re-binds, leaving a small window where
    # another worker can grab the port; retrying picks a fresh port.
    handler = handler_class or MockIppHandler

    class _Server(http.server.HTTPServer):
        allow_reuse_address = True

    for _ in range(10):
        port = _free_port()
        try:
            server = _Server(("127.0.0.1", port), handler)
            break
        except OSError:
            continue
    else:
        raise RuntimeError("could not bind a free port after 10 attempts")
    for k, v in kwargs.items():
        setattr(server, k, v)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    # Wait until the server socket is actually accepting connections so the
    # client does not race ahead of the listener under xdist parallel load.
    for _ in range(50):
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                break
        except OSError:
            time.sleep(0.02)
    return server, port, thread


class TestBuildIppPrintJobRequest:

    def test_header_version_and_operation(self):
        tspl = b"\x00" * 100
        url = "http://lily:631/printers/Y41BT"
        req = _build_ipp_print_job_request(tspl, url)

        assert req[:2] == IPP_VERSION
        assert req[2:4] == OP_PRINT_JOB

    def test_request_id_is_nonzero(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        request_id = struct.unpack("!I", req[4:8])[0]
        assert request_id > 0

    def test_contains_charset_attribute(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        assert b"attributes-charset" in req
        assert b"utf-8" in req

    def test_contains_natural_language_attribute(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        assert b"attributes-natural-language" in req
        assert b"en-us" in req

    def test_contains_printer_uri(self):
        url = "http://lily:631/printers/Y41BT"
        req = _build_ipp_print_job_request(b"tspl", url)
        assert b"printer-uri" in req
        assert b"ipp://localhost/printers/Y41BT" in req

    def test_contains_job_name(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        assert b"job-name" in req
        assert b"Bakery Receipt" in req

    def test_contains_document_format(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        assert b"document-format" in req
        assert b"application/octet-stream" in req

    def test_contains_requesting_user_name(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        assert b"requesting-user-name" in req
        assert b"baker" in req

    def test_end_of_attributes_tag_present(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        assert TAG_END_OF_ATTRS.to_bytes(1, "big") in req

    def test_tspl_bytes_after_end_tag(self):
        tspl = b"TSPL_COMMANDS_HERE"
        req = _build_ipp_print_job_request(tspl, "http://lily:631/printers/Y41BT")
        # Use rindex: the request_id field (bytes 4-7) may contain 0x03 (e.g.
        # request_id=3), which would make index() match too early. The
        # end-of-attributes tag is the last 0x03 before the TSPL payload.
        end_tag = req.rindex(bytes([TAG_END_OF_ATTRS]))
        assert req[end_tag + 1 :] == tspl

    def test_document_format_is_octet_stream(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        assert b"application/octet-stream" in req

    def test_operation_attributes_tag_first_attribute_group(self):
        req = _build_ipp_print_job_request(b"tspl", "http://lily:631/printers/Y41BT")
        assert req[8] == TAG_OPERATION_ATTRS


class TestParseIppStatus:

    def test_success_status_zero(self):
        resp = _ipp_success_response(42)
        status, req_id = _parse_ipp_status(resp)
        assert status == 0x0000
        assert req_id == 42

    def test_client_error_not_possible_status(self):
        resp = _ipp_error_response(0x0401, 7)
        status, req_id = _parse_ipp_status(resp)
        assert status == 0x0401
        assert req_id == 7

    def test_server_error_internal_error_status(self):
        resp = _ipp_error_response(0x0500, 3)
        status, req_id = _parse_ipp_status(resp)
        assert status == 0x0500
        assert req_id == 3

    def test_short_response_raises(self):
        with pytest.raises(IppError, match="too short"):
            _parse_ipp_status(b"\x02\x00\x00")


class TestParseUrl:

    def test_standard_ipp_url(self):
        host, port, path = _parse_url("http://lily:631/printers/Y41BT")
        assert host == "lily"
        assert port == 631
        assert path == "/printers/Y41BT"

    def test_default_port_when_absent(self):
        host, port, path = _parse_url("http://lily/printers/Y41BT")
        assert host == "lily"
        assert port == 631
        assert path == "/printers/Y41BT"

    def test_ip_address_url(self):
        host, port, path = _parse_url("http://100.64.0.5:631/printers/Y41BT")
        assert host == "100.64.0.5"
        assert port == 631
        assert path == "/printers/Y41BT"

    def test_tailscale_magicdns_url(self):
        host, port, path = _parse_url("http://lily.tailnet-name.ts.net:631/printers/Y41BT")
        assert host == "lily.tailnet-name.ts.net"
        assert port == 631
        assert path == "/printers/Y41BT"

    def test_custom_port(self):
        host, port, path = _parse_url("http://lily:8631/printers/Y41BT")
        assert host == "lily"
        assert port == 8631
        assert path == "/printers/Y41BT"

    def test_malformed_url_no_hostname_raises_value_error(self):
        with pytest.raises(ValueError, match="cannot extract hostname"):
            _parse_url("not-a-valid-url")

    def test_empty_string_raises_value_error(self):
        with pytest.raises(ValueError, match="cannot extract hostname"):
            _parse_url("")


class TestSendSingleRequest:

    def test_successful_print_job(self):
        server, port, thread = _start_server()
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            tspl = b"SIZE 76 mm,50.0 mm\r\nGAP 3 mm,0 mm\r\nPRINT 1,1\r\n"
            _send_single_request(tspl, url)
        finally:
            server.shutdown()
            thread.join(timeout=2)

    def test_http_error_raises(self):
        server, port, thread = _start_server(response_code=500)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            with pytest.raises(IppHttpError) as exc:
                _send_single_request(b"tspl", url)
            assert exc.value.http_status == 500
        finally:
            server.shutdown()
            thread.join(timeout=2)

    def test_ipp_error_raises(self):
        server, port, thread = _start_server(ipp_status_code=0x0501)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            with pytest.raises(IppError) as exc:
                _send_single_request(b"tspl", url)
            assert exc.value.status_code == 0x0501
        finally:
            server.shutdown()
            thread.join(timeout=2)

    def test_wrong_content_type_rejected(self):
        server, port, thread = _start_server(response_code=400)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            with pytest.raises(IppHttpError) as exc:
                _send_single_request(b"tspl", url)
            assert exc.value.http_status == 400
        finally:
            server.shutdown()
            thread.join(timeout=2)


class TestSendTsplToIppRetry:

    def test_retry_on_connection_error_then_succeed(self):
        attempts = []

        class RetryHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                content_length = int(self.headers.get("Content-Length", 0))
                self.rfile.read(content_length)
                if len(attempts) == 0:
                    attempts.append(1)
                    self.wfile.close()
                    self.connection.close()
                    return
                attempts.append(2)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(_ipp_success_response())

            def log_message(self, format, *args):
                pass

        server, port, _ = _start_server(handler_class=RetryHandler)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            tspl = b"TSPL_DATA"
            send_tspl_to_ipp(tspl, url, retries=3, retry_delay=0.1, timeout=2)

            assert len(attempts) >= 2
            assert attempts[-1] == 2
        finally:
            server.shutdown()

    def test_raises_after_all_retries_exhausted(self):
        class FailHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                content_length = int(self.headers.get("Content-Length", 0))
                self.rfile.read(content_length)
                self.wfile.close()
                self.connection.close()

            def log_message(self, format, *args):
                pass

        server, port, _ = _start_server(handler_class=FailHandler)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            with pytest.raises(IppConnectionError, match="Failed after 2 attempts"):
                send_tspl_to_ipp(
                    b"TSPL_DATA", url, retries=2, retry_delay=0.1, timeout=2,
                )
        finally:
            server.shutdown()

    def test_no_retry_on_ipp_error(self):
        call_count = []

        class IppErrHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                content_length = int(self.headers.get("Content-Length", 0))
                self.rfile.read(content_length)
                call_count.append(1)
                resp = _ipp_error_response(0x0501)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(resp)

            def log_message(self, format, *args):
                pass

        server, port, _ = _start_server(handler_class=IppErrHandler)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            with pytest.raises(IppError, match="0x0501"):
                send_tspl_to_ipp(
                    b"TSPL_DATA", url, retries=3, retry_delay=0.1, timeout=2,
                )
            assert len(call_count) == 1
        finally:
            server.shutdown()

    def test_no_retry_on_http_error(self):
        call_count = []

        class HttpErrHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                content_length = int(self.headers.get("Content-Length", 0))
                self.rfile.read(content_length)
                call_count.append(1)
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"Internal Server Error")

            def log_message(self, format, *args):
                pass

        server, port, _ = _start_server(handler_class=HttpErrHandler)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            with pytest.raises(IppHttpError, match="500"):
                send_tspl_to_ipp(
                    b"TSPL_DATA", url, retries=3, retry_delay=0.1, timeout=2,
                )
            assert len(call_count) == 1
        finally:
            server.shutdown()


class TestIppClientIntegration:

    def test_full_flow_sends_correct_content_type(self):
        content_type_received = []

        class InspectHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                content_type_received.append(self.headers.get("Content-Type", ""))
                content_length = int(self.headers.get("Content-Length", 0))
                self.rfile.read(content_length)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(_ipp_success_response())

            def log_message(self, format, *args):
                pass

        server, port, _ = _start_server(handler_class=InspectHandler)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            send_tspl_to_ipp(b"TSPL_DATA", url)
            assert content_type_received[0] == "application/ipp"
        finally:
            server.shutdown()

    def test_full_flow_tspl_bytes_arrive_intact(self):
        tspl_received = []

        class InspectHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                content_length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(content_length)
                # Use rindex: the request_id field (bytes 4-7) may contain 0x03
                # (e.g. request_id=3), which would make index() match too early.
                end_idx = body.rindex(bytes([TAG_END_OF_ATTRS]))
                tspl_received.append(body[end_idx + 1 :])
                self.send_response(200)
                self.end_headers()
                self.wfile.write(_ipp_success_response())

            def log_message(self, format, *args):
                pass

        server, port, _ = _start_server(handler_class=InspectHandler)
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            original_tspl = b"SIZE 76 mm,50.0 mm\r\nGAP 3 mm,0 mm\r\nPRINT 1,1\r\n"
            send_tspl_to_ipp(original_tspl, url)
            assert tspl_received[0] == original_tspl
        finally:
            server.shutdown()

    def test_full_flow_with_empty_tspl(self):
        server, port, thread = _start_server()
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            send_tspl_to_ipp(b"", url)
        finally:
            server.shutdown()
            thread.join(timeout=2)

    def test_full_flow_with_large_tspl_payload(self):
        server, port, thread = _start_server()
        try:
            url = f"http://127.0.0.1:{port}/printers/Y41BT"
            large_tspl = b"X" * 50000
            send_tspl_to_ipp(large_tspl, url, timeout=5)
        finally:
            server.shutdown()
            thread.join(timeout=2)


class TestIppClientExceptionHierarchy:
    def test_ipp_error_is_exception(self):
        assert issubclass(IppError, Exception)

    def test_ipp_http_error_is_exception(self):
        assert issubclass(IppHttpError, Exception)

    def test_ipp_connection_error_is_exception(self):
        assert issubclass(IppConnectionError, Exception)

    def test_ipp_error_message_includes_hex(self):
        exc = IppError(0x0501)
        assert "0x0501" in str(exc)

    def test_ipp_http_error_message_includes_status(self):
        exc = IppHttpError(503)
        assert "503" in str(exc)
