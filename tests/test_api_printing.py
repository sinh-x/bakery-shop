from unittest.mock import patch


def _create_order(client):
    resp = client.post(
        "/api/orders",
        json={
            "customerName": "In phiếu test",
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


@patch("baker.api.printing.usb_printer.print_receipt")
def test_work_ticket_print_inserts_log_and_sets_first_print(mock_print, api_client):
    mock_print.return_value = None
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


@patch("baker.api.printing.usb_printer.print_receipt")
def test_second_print_appends_log_without_overwriting_first_print_fields(mock_print, api_client):
    mock_print.return_value = None
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


@patch("baker.api.printing.usb_printer.print_receipt")
def test_print_fills_missing_printed_by_when_legacy_timestamp_exists(mock_print, api_client):
    mock_print.return_value = None
    order = _create_order(api_client)
    order_ref = order["orderRef"]
    item_id = _first_work_item_id(api_client, order_ref)

    detail_before = api_client.get(f"/api/orders/{order_ref}").json()
    order_id = detail_before["id"]
    legacy_ts = "2026-04-01T08:30:00"

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


@patch("baker.api.printing.usb_printer.print_receipt", side_effect=FileNotFoundError)
def test_print_failure_returns_503_and_does_not_write_logs_or_first_print(
    _mock_print,
    api_client,
):
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


@patch("baker.api.printing.usb_printer.print_receipt")
def test_print_with_empty_staff_name_succeeds_and_records_empty_string(mock_print, api_client):
    mock_print.return_value = None
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
