from unittest.mock import patch


def _create_order(client):
    resp = client.post(
        "/api/orders",
        json={
            "customerName": "In phiếu test",
            "dueDate": "2026-03-25",
            "items": [{"productName": "Bánh kem", "quantity": 1, "unitPrice": 120000, "productId": "BKS-16"}],
        },
    )
    assert resp.status_code == 201
    return resp.json()


def _first_work_item_id(client, order_ref: str):
    detail = client.get(f"/api/orders/{order_ref}")
    assert detail.status_code == 200
    return detail.json()["workItems"][0]["id"]


def _print_work_ticket(client, order_ref: str, item_id: int, printed_by=None):
    params = {
        "type": "work_ticket",
        "item_id": item_id,
    }
    if printed_by is not None:
        params["printed_by"] = printed_by
    return client.post(f"/api/orders/{order_ref}/print", params=params)


@patch("baker.api.printing.os.close")
@patch("baker.api.printing.os.write")
@patch("baker.api.printing.usb_printer.open_printer")
@patch("baker.api.printing.usb_printer.png_to_tspl")
def test_work_ticket_print_inserts_log_and_sets_first_print(mock_tspl, mock_open, mock_write, mock_close, api_client):
    mock_tspl.return_value = b"FAKE_TSPL_DATA"
    mock_open.return_value = 3
    mock_write.return_value = len(b"FAKE_TSPL_DATA")
    order = _create_order(api_client)
    order_ref = order["orderRef"]
    item_id = _first_work_item_id(api_client, order_ref)

    resp = _print_work_ticket(api_client, order_ref, item_id, printed_by="An")
    assert resp.status_code == 200
    payload = resp.json()
    assert payload["status"] == "ok"
    assert payload["printedBy"] == "An"
    assert payload["printedAt"] is not None

    log_resp = api_client.get(f"/api/orders/{order_ref}/print-log")
    assert log_resp.status_code == 200
    rows = log_resp.json()
    assert len(rows) == 1
    assert rows[0]["itemId"] == int(item_id)
    assert rows[0]["receiptType"] == "work_ticket"
    assert rows[0]["printedBy"] == "An"

    order_detail = api_client.get(f"/api/orders/{order_ref}").json()
    assert order_detail["workTicketPrintedAt"] is not None
    assert order_detail["workTicketPrintedBy"] == "An"


@patch("baker.api.printing.os.close")
@patch("baker.api.printing.os.write")
@patch("baker.api.printing.usb_printer.open_printer")
@patch("baker.api.printing.usb_printer.png_to_tspl")
def test_second_print_appends_log_without_overwriting_first_print_fields(mock_tspl, mock_open, mock_write, mock_close, api_client):
    mock_tspl.return_value = b"FAKE_TSPL_DATA"
    mock_open.return_value = 3
    mock_write.return_value = len(b"FAKE_TSPL_DATA")
    order = _create_order(api_client)
    order_ref = order["orderRef"]
    item_id = _first_work_item_id(api_client, order_ref)

    first = _print_work_ticket(api_client, order_ref, item_id, printed_by="An")
    assert first.status_code == 200
    first_detail = api_client.get(f"/api/orders/{order_ref}").json()
    first_ts = first_detail["workTicketPrintedAt"]
    assert first_ts is not None

    second = _print_work_ticket(api_client, order_ref, item_id, printed_by="Ngân")
    assert second.status_code == 200

    log_resp = api_client.get(f"/api/orders/{order_ref}/print-log")
    rows = log_resp.json()
    assert len(rows) == 2
    assert rows[0]["printedBy"] == "An"
    assert rows[1]["printedBy"] == "Ngân"
    assert rows[0]["printedAt"] <= rows[1]["printedAt"]

    order_detail = api_client.get(f"/api/orders/{order_ref}").json()
    assert order_detail["workTicketPrintedAt"] == first_ts
    assert order_detail["workTicketPrintedBy"] == "An"


@patch("baker.api.printing.os.close")
@patch("baker.api.printing.os.write")
@patch("baker.api.printing.usb_printer.open_printer")
@patch("baker.api.printing.usb_printer.png_to_tspl")
def test_print_grace_period_attribution(
    mock_tspl, mock_open, mock_write, mock_close, api_client
):
    """AC6-a: AUTH_REQUIRED=false, no JWT → print_log.printed_by and
    orders.work_ticket_printed_by use the client-supplied printed_by value.

    api_client runs with AUTH_REQUIRED=false (grace period), so the
    resolve_actor fallback chain returns the client-supplied name.
    """
    mock_tspl.return_value = b"FAKE_TSPL_DATA"
    mock_open.return_value = 3
    mock_write.return_value = len(b"FAKE_TSPL_DATA")
    order = _create_order(api_client)
    order_ref = order["orderRef"]
    item_id = _first_work_item_id(api_client, order_ref)

    resp = _print_work_ticket(api_client, order_ref, item_id, printed_by="Ngân")
    assert resp.status_code == 200

    order_detail = api_client.get(f"/api/orders/{order_ref}").json()
    order_id = order_detail["id"]

    from baker.db.connection import get_db
    with get_db() as conn:
        log_rows = conn.execute(
            "SELECT printed_by FROM print_log WHERE order_id = ? ORDER BY id",
            (order_id,),
        ).fetchall()
        assert len(log_rows) == 1
        assert log_rows[0]["printed_by"] == "Ngân"

        order_row = conn.execute(
            "SELECT work_ticket_printed_by FROM orders WHERE id = ?",
            (order_id,),
        ).fetchone()
        assert order_row is not None
        assert order_row["work_ticket_printed_by"] == "Ngân"


@patch("baker.api.printing.os.close")
@patch("baker.api.printing.os.write")
@patch("baker.api.printing.usb_printer.open_printer")
@patch("baker.api.printing.usb_printer.png_to_tspl")
def test_print_fills_missing_printed_by_when_legacy_timestamp_exists(mock_tspl, mock_open, mock_write, mock_close, api_client):
    mock_tspl.return_value = b"FAKE_TSPL_DATA"
    mock_open.return_value = 3
    mock_write.return_value = len(b"FAKE_TSPL_DATA")
    order = _create_order(api_client)
    order_ref = order["orderRef"]
    item_id = _first_work_item_id(api_client, order_ref)

    detail_before = api_client.get(f"/api/orders/{order_ref}").json()
    order_id = detail_before["id"]
    legacy_ts = "2026-04-01T08:30:00Z"

    from baker.db.connection import get_db
    with get_db() as conn:
        conn.execute(
            "UPDATE orders SET work_ticket_printed_at = ?, work_ticket_printed_by = '' WHERE id = ?",
            (legacy_ts, order_id),
        )

    resp = _print_work_ticket(api_client, order_ref, item_id, printed_by="Ngân")
    assert resp.status_code == 200

    order_detail = api_client.get(f"/api/orders/{order_ref}").json()
    assert order_detail["workTicketPrintedAt"] == legacy_ts
    assert order_detail["workTicketPrintedBy"] == "Ngân"


@patch("baker.api.printing.os.close")
@patch("baker.api.printing.os.write")
@patch("baker.api.printing.usb_printer.open_printer", side_effect=FileNotFoundError)
@patch("baker.api.printing.usb_printer.png_to_tspl")
def test_print_failure_returns_503_and_does_not_write_logs_or_first_print(
    mock_tspl,
    _mock_open_printer,
    _mock_write,
    _mock_close,
    api_client,
):
    mock_tspl.return_value = b"FAKE_TSPL_DATA"
    order = _create_order(api_client)
    order_ref = order["orderRef"]
    item_id = _first_work_item_id(api_client, order_ref)

    resp = _print_work_ticket(api_client, order_ref, item_id, printed_by="An")
    assert resp.status_code == 503

    log_resp = api_client.get(f"/api/orders/{order_ref}/print-log")
    assert log_resp.status_code == 200
    assert log_resp.json() == []

    order_detail = api_client.get(f"/api/orders/{order_ref}").json()
    assert order_detail["workTicketPrintedAt"] is None
    assert order_detail["workTicketPrintedBy"] == ""


@patch("baker.api.printing.os.close")
@patch("baker.api.printing.os.write")
@patch("baker.api.printing.usb_printer.open_printer")
@patch("baker.api.printing.usb_printer.png_to_tspl")
def test_print_with_empty_staff_name_succeeds_and_records_empty_string(mock_tspl, mock_open, mock_write, mock_close, api_client):
    mock_tspl.return_value = b"FAKE_TSPL_DATA"
    mock_open.return_value = 3
    mock_write.return_value = len(b"FAKE_TSPL_DATA")
    order = _create_order(api_client)
    order_ref = order["orderRef"]
    item_id = _first_work_item_id(api_client, order_ref)

    resp = _print_work_ticket(api_client, order_ref, item_id, printed_by="")
    assert resp.status_code == 200
    assert resp.json()["printedBy"] == ""

    rows = api_client.get(f"/api/orders/{order_ref}/print-log").json()
    assert len(rows) == 1
    assert rows[0]["printedBy"] == ""


def test_print_log_returns_404_when_order_missing(api_client):
    resp = api_client.get("/api/orders/ORD-NOT-FOUND/print-log")
    assert resp.status_code == 404


@patch("baker.api.printing.os.close")
@patch("baker.api.printing.os.write")
@patch("baker.api.printing.usb_printer.open_printer")
@patch("baker.api.printing.usb_printer.png_to_tspl")
@patch("baker.api.printing._split_pages")
def test_print_receipt_iterates_all_pages_through_tspl(
    mock_split, mock_tspl, mock_open, mock_write, mock_close, api_client
):
    """DG-228 Phase 4 / AC-7: multi-page receipt iterates each page through
    png_to_tspl so every page is converted to a TSPL bitmap and written to
    the printer transport."""
    from PIL import Image

    page_one = Image.new("RGB", (576, 1040), "white")
    page_two = Image.new("RGB", (576, 800), "white")
    mock_split.return_value = [page_one, page_two]
    mock_tspl.return_value = b"FAKE_TSPL_DATA"
    mock_open.return_value = 3
    mock_write.return_value = len(b"FAKE_TSPL_DATA")

    order = _create_order(api_client)
    order_ref = order["orderRef"]
    item_id = _first_work_item_id(api_client, order_ref)

    resp = _print_work_ticket(api_client, order_ref, item_id, printed_by="An")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"

    # Each split page must be converted to TSPL and written exactly once.
    assert mock_tspl.call_count == 2, (
        f"Expected png_to_tspl called once per page (2), got {mock_tspl.call_count}"
    )
    assert mock_write.call_count == 2, (
        f"Expected os.write called once per page (2), got {mock_write.call_count}"
    )
    # Confirm each call received a PNG bytes payload (first positional arg).
    for call_args in mock_tspl.call_args_list:
        png_arg = call_args.args[0]
        assert isinstance(png_arg, bytes)
        assert png_arg[:8] == b"\x89PNG\r\n\x1a\n", "First arg must be PNG bytes"


class TestPrintStatusPaperMode:
    """Test GET /api/orders/print/status includes paperMode (FR3, AC4)."""

    def test_status_includes_paper_mode_field(self, api_client):
        """print/status response includes paperMode with effective value."""
        resp = api_client.get("/api/orders/print/status")
        assert resp.status_code == 200
        body = resp.json()
        assert "paperMode" in body
        assert body["paperMode"] in ("label", "roll")
        # Default when no env/DB override is "label" (AC1/AC8 backward compat)
        assert body["paperMode"] == "label"

    def test_status_preserves_printer_and_device_fields(self, api_client):
        """Existing printer/device fields remain present (no regression)."""
        resp = api_client.get("/api/orders/print/status")
        body = resp.json()
        assert "status" in body
        assert "printer" in body
        assert "device" in body

    def test_status_reflects_db_override(self, api_client):
        """DB override for paper_mode is reflected in status (AC6)."""
        set_resp = api_client.put(
            "/api/orders/print/paper-mode", json={"paperMode": "roll"}
        )
        assert set_resp.status_code == 200

        resp = api_client.get("/api/orders/print/status")
        assert resp.json()["paperMode"] == "roll"


class TestPaperModeGetSet:
    """Test GET/PUT /api/orders/print/paper-mode (FR3, AC5 backend, AC6)."""

    def test_get_returns_default_label_when_unset(self, api_client):
        """GET returns label by default (backward compat, AC1)."""
        resp = api_client.get("/api/orders/print/paper-mode")
        assert resp.status_code == 200
        body = resp.json()
        assert body["paperMode"] == "label"
        assert body["default"] == "label"

    def test_set_roll_persists_and_reads_back(self, api_client):
        """PUT roll persists to app_config and subsequent GET reads it (AC6)."""
        set_resp = api_client.put(
            "/api/orders/print/paper-mode", json={"paperMode": "roll"}
        )
        assert set_resp.status_code == 200
        assert set_resp.json()["paperMode"] == "roll"

        get_resp = api_client.get("/api/orders/print/paper-mode")
        assert get_resp.status_code == 200
        assert get_resp.json()["paperMode"] == "roll"

    def test_set_label_overrides_prior_roll(self, api_client):
        """Setting label after roll overrides the prior DB value."""
        api_client.put("/api/orders/print/paper-mode", json={"paperMode": "roll"})
        set_resp = api_client.put(
            "/api/orders/print/paper-mode", json={"paperMode": "label"}
        )
        assert set_resp.status_code == 200
        assert set_resp.json()["paperMode"] == "label"

        get_resp = api_client.get("/api/orders/print/paper-mode")
        assert get_resp.json()["paperMode"] == "label"

    def test_set_invalid_value_rejected_400(self, api_client):
        """Invalid paperMode value is rejected with 400 (FR2)."""
        resp = api_client.put(
            "/api/orders/print/paper-mode", json={"paperMode": "garbage"}
        )
        assert resp.status_code == 400

    def test_set_empty_string_rejected_400(self, api_client):
        """Empty paperMode is rejected."""
        resp = api_client.put(
            "/api/orders/print/paper-mode", json={"paperMode": ""}
        )
        assert resp.status_code == 400

    def test_set_whitespace_value_rejected_400(self, api_client):
        """Whitespace-only paperMode is rejected after trim."""
        resp = api_client.put(
            "/api/orders/print/paper-mode", json={"paperMode": "   "}
        )
        assert resp.status_code == 400

    def test_set_trims_surrounding_whitespace(self, api_client):
        """Surrounding whitespace is trimmed before validation/persistence."""
        resp = api_client.put(
            "/api/orders/print/paper-mode", json={"paperMode": "  roll  "}
        )
        assert resp.status_code == 200
        assert resp.json()["paperMode"] == "roll"

    def test_set_is_idempotent(self, api_client):
        """Setting the same value twice does not duplicate the row."""
        api_client.put("/api/orders/print/paper-mode", json={"paperMode": "roll"})
        second = api_client.put(
            "/api/orders/print/paper-mode", json={"paperMode": "roll"}
        )
        assert second.status_code == 200
        assert second.json()["paperMode"] == "roll"

        # Verify only one active row exists for paper_mode
        from baker.db.connection import get_db
        with get_db() as conn:
            rows = conn.execute(
                "SELECT config_value FROM app_config WHERE config_key = 'paper_mode'"
            ).fetchall()
        assert len(rows) == 1
        assert rows[0]["config_value"] == "roll"


class TestPaperModeBackwardCompat:
    """Test backward compatibility with existing printer tests (AC8)."""

    def test_existing_print_flow_unaffected_by_paper_mode(self, api_client):
        """Print request succeeds regardless of paper mode setting (AC8)."""
        with patch("baker.api.printing.usb_printer.png_to_tspl") as mock_tspl, \
             patch("baker.api.printing.usb_printer.open_printer") as mock_open, \
             patch("baker.api.printing.os.write") as mock_write, \
             patch("baker.api.printing.os.close") as mock_close:
            mock_tspl.return_value = b"FAKE_TSPL_DATA"
            mock_open.return_value = 3
            mock_write.return_value = len(b"FAKE_TSPL_DATA")
            order = _create_order(api_client)
            order_ref = order["orderRef"]
            item_id = _first_work_item_id(api_client, order_ref)

            # Set roll mode, then print — should still succeed
            api_client.put("/api/orders/print/paper-mode", json={"paperMode": "roll"})
            resp = _print_work_ticket(api_client, order_ref, item_id, printed_by="An")
            assert resp.status_code == 200
            assert resp.json()["status"] == "ok"
            mock_tspl.assert_called_once()
