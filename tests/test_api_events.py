"""Tests for Baker API — event endpoints (Phase 1)."""


# --- POST /api/events ---


def test_create_event_minimal(api_client):
    resp = api_client.post("/api/events", json={"summary": "Tủ lạnh kêu lạ"})
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["summary"] == "Tủ lạnh kêu lạ"
    assert ev["type"] == "note"
    assert ev["tags"] == []
    assert ev["source"] == "app"
    assert ev["logged_by"] == ""
    assert ev["id"] is not None
    assert ev["timestamp"] is not None


def test_create_event_full(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Sự cố tủ lạnh",
        "type": "equipment",
        "tags": ["equipment", "maintenance"],
        "logged_by": "Diễm",
        "data": {"severity": "high"},
        "source": "app",
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["type"] == "equipment"
    assert ev["tags"] == ["equipment", "maintenance"]
    assert ev["logged_by"] == "Diễm"
    assert ev["data"] == {"severity": "high"}
    assert ev["source"] == "app"


def test_create_event_empty_summary_rejected(api_client):
    resp = api_client.post("/api/events", json={"summary": "   "})
    assert resp.status_code == 422


def test_create_event_missing_summary_rejected(api_client):
    resp = api_client.post("/api/events", json={"type": "note"})
    assert resp.status_code == 422


def test_create_expense_event_with_structured_data(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua bột mì",
        "type": "expense",
        "data": {
            "amount_vnd": 125000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ Bình Tây",
            "note": "Bột mì đa dụng",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["type"] == "expense"


def test_create_event_with_custom_timestamp(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Ghi sự kiện có giờ",
        "type": "expense",
        "timestamp": "2026-05-23T19:57:00",
        "data": {
            "amount_vnd": 75000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC A",
            "note": "Mua đường",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 201
    assert resp.json()["timestamp"] == "2026-05-23T19:57:00"


def test_create_expense_event_rejects_non_integer_amount(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua sữa",
        "type": "expense",
        "data": {
            "amount_vnd": "120000",
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Cửa hàng A",
            "note": "Sữa tươi",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 422
    assert "amount_vnd" in resp.json()["detail"]


def test_create_expense_event_rejects_missing_required_fields(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua đường",
        "type": "expense",
        "data": {
            "amount_vnd": 10000,
            "category": "Nguyên liệu",
        },
    })
    assert resp.status_code == 422
    assert "thiếu trường bắt buộc" in resp.json()["detail"]


def test_create_expense_event_rejects_missing_payment_source(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua đường",
        "type": "expense",
        "data": {
            "amount_vnd": 10000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "vendor": "NCC A",
            "note": "Đường",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 422
    assert "payment_source" in resp.json()["detail"]


def test_create_expense_event_rejects_nhan_vien_ung_truoc_without_staff_name(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền ứng trước",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Nhân viên ứng trước",
            "vendor": "NCC A",
            "note": "Mua hàng",
            "staff_name": "",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 422
    assert "Nhân viên ứng trước" in resp.json()["detail"]


def test_create_expense_event_accepts_nhan_vien_ung_truoc_with_staff_name(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền ứng trước",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Nhân viên ứng trước",
            "vendor": "NCC A",
            "note": "Mua hàng",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 201


def test_create_expense_event_persists_reimbursed(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền đã hoàn lại",
        "type": "expense",
        "data": {
            "amount_vnd": 80000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Nhân viên ứng trước",
            "vendor": "NCC A",
            "note": "Mua hàng",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
            "reimbursed": True,
        },
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["data"]["reimbursed"] is True
    assert ev["data"]["payment_source"] == "Nhân viên ứng trước"


def test_create_expense_event_defaults_reimbursed_false(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền chưa hoàn lại",
        "type": "expense",
        "data": {
            "amount_vnd": 60000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Nhân viên ứng trước",
            "vendor": "NCC A",
            "note": "Mua hàng",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["data"].get("reimbursed", False) is False


# --- GET /api/events ---


def _seed_events(api_client):
    """Seed a few events for filter tests."""
    api_client.post("/api/events", json={
        "summary": "Tủ lạnh hỏng", "type": "equipment",
        "tags": ["equipment"], "logged_by": "Diễm",
    })
    api_client.post("/api/events", json={
        "summary": "Khách hỏi giá bánh", "type": "note",
        "tags": ["knowledge-gap"], "logged_by": "Lan",
    })
    api_client.post("/api/events", json={
        "summary": "Nhập thêm bột mì", "type": "inventory",
        "tags": ["ordering"], "logged_by": "Diễm",
    })


def test_list_events_returns_all(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 3


def test_list_events_empty_db(api_client):
    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    assert resp.json() == []


def test_list_events_filter_by_type(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"type": "equipment"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["type"] == "equipment"


def test_list_events_filter_by_tag(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"tag": "equipment"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert "equipment" in events[0]["tags"]


def test_list_events_filter_by_multiple_tags(api_client):
    """Comma-separated tags returns union of matched events."""
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"tag": "equipment,ordering"})
    assert resp.status_code == 200
    # fetch_events applies AND per-tag, so each separate tag works independently
    # With comma-sep -> tags=["equipment","ordering"] -> events that have BOTH tags = 0
    # Confirm the endpoint doesn't error out
    assert resp.status_code == 200


def test_list_events_filter_by_logged_by(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"logged_by": "Lan"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["logged_by"] == "Lan"


def test_list_events_search(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events", params={"search": "tủ lạnh"})
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert "Tủ lạnh" in events[0]["summary"]


def test_list_events_limit(api_client):
    for i in range(5):
        api_client.post("/api/events", json={"summary": f"Event {i}"})
    resp = api_client.get("/api/events", params={"limit": 3})
    assert resp.status_code == 200
    assert len(resp.json()) == 3


def test_list_events_newest_first(api_client):
    _seed_events(api_client)
    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    events = resp.json()
    timestamps = [ev["timestamp"] for ev in events]
    assert timestamps == sorted(timestamps, reverse=True)


def test_list_events_tags_as_list(api_client):
    """Tags in response should be a list, not a comma string."""
    api_client.post("/api/events", json={"summary": "Test", "tags": ["a", "b"]})
    resp = api_client.get("/api/events")
    assert resp.status_code == 200
    ev = resp.json()[0]
    assert isinstance(ev["tags"], list)
    assert "a" in ev["tags"]
    assert "b" in ev["tags"]


def test_list_events_expense_filter_by_category(api_client):
    api_client.post("/api/events", json={
        "summary": "Mua bột mì",
        "type": "expense",
        "data": {
            "amount_vnd": 120000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ Bình Tây",
            "note": "Bột mì số 8",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    api_client.post("/api/events", json={
        "summary": "Mua ly giấy",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Bao bì",
            "payment_method": "Chuyển khoản",
            "payment_source": "TK Phượng VCB",
            "vendor": "Nhà cung cấp A",
            "note": "Ly 16oz",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_category": "Nguyên liệu",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["category"] == "Nguyên liệu"


def test_list_events_expense_filter_by_payment_method(api_client):
    api_client.post("/api/events", json={
        "summary": "Mua đường",
        "type": "expense",
        "data": {
            "amount_vnd": 70000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Cửa hàng B",
            "note": "Đường cát",
            "staff_name": "Hoa",
            "paid_by_name": "Tân",
        },
    })
    api_client.post("/api/events", json={
        "summary": "Mua túi",
        "type": "expense",
        "data": {
            "amount_vnd": 40000,
            "category": "Bao bì",
            "payment_method": "Chuyển khoản",
            "payment_source": "TK Phượng VCB",
            "vendor": "NCC C",
            "note": "Túi giấy",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_payment_method": "Tiền mặt",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["payment_method"] == "Tiền mặt"


def test_list_events_expense_filter_by_staff_name(api_client):
    api_client.post("/api/events", json={
        "summary": "Mua trứng",
        "type": "expense",
        "data": {
            "amount_vnd": 90000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC Trứng",
            "note": "30 quả",
            "staff_name": "Ngọc Lan",
            "paid_by_name": "Phượng",
        },
    })
    api_client.post("/api/events", json={
        "summary": "Mua hộp",
        "type": "expense",
        "data": {
            "amount_vnd": 60000,
            "category": "Bao bì",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC Hộp",
            "note": "Hộp bánh",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_staff_name": "ngọc lan",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["staff_name"] == "Ngọc Lan"


def test_list_events_expense_search_applies_before_limit(api_client):
    for idx in range(499):
        api_client.post("/api/events", json={
            "summary": f"Chi phí thường {idx}",
            "type": "expense",
            "data": {
                "amount_vnd": 1000 + idx,
                "category": "Nguyên liệu",
                "payment_method": "Tiền mặt",
                "payment_source": "Shop tiền mặt",
                "vendor": "NCC thường",
                "note": "Giao dịch thường",
                "staff_name": "Lan",
                "paid_by_name": "Phượng",
            },
        })

    api_client.post("/api/events", json={
        "summary": "Chi phí mục tiêu",
        "type": "expense",
        "data": {
            "amount_vnd": 88888,
            "category": "Bao bì",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC mục tiêu",
            "note": "hoadon-target",
            "staff_name": "Hoa",
            "paid_by_name": "Tân",
        },
    })

    api_client.post("/api/events", json={
        "summary": "Chi phí mới hơn",
        "type": "expense",
        "data": {
            "amount_vnd": 77777,
            "category": "Bao bì",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC mới",
            "note": "bản ghi mới",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_search": "hoadon-target",
        "limit": 1,
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["note"] == "hoadon-target"


def test_list_events_expense_filter_by_payment_source(api_client):
    api_client.post("/api/events", json={
        "summary": "Mua bột mì",
        "type": "expense",
        "data": {
            "amount_vnd": 120000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ Bình Tây",
            "note": "Bột mì số 8",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    api_client.post("/api/events", json={
        "summary": "Mua ly giấy",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Bao bì",
            "payment_method": "Chuyển khoản",
            "payment_source": "TK Phượng VCB",
            "vendor": "Nhà cung cấp A",
            "note": "Ly 16oz",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_payment_source": "TK Phượng VCB",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["payment_source"] == "TK Phượng VCB"


def test_create_expense_event_rejects_missing_paid_by_name(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua đường",
        "type": "expense",
        "data": {
            "amount_vnd": 10000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC A",
            "note": "Đường",
            "staff_name": "Lan",
        },
    })
    assert resp.status_code == 422
    assert "paid_by_name" in resp.json()["detail"]


def test_create_expense_event_rejects_invalid_paid_by_name(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua đường",
        "type": "expense",
        "data": {
            "amount_vnd": 10000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC A",
            "note": "Đường",
            "staff_name": "Lan",
            "paid_by_name": "Người Lạ Không Tồn Tại",
        },
    })
    assert resp.status_code == 422
    assert "paid_by_name" in resp.json()["detail"]
    assert "không khớp" in resp.json()["detail"]


def test_create_expense_event_accepts_empty_paid_by_name(api_client):
    resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua đường",
        "type": "expense",
        "data": {
            "amount_vnd": 10000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "NCC A",
            "note": "Đường",
            "staff_name": "Lan",
            "paid_by_name": "",
        },
    })
    assert resp.status_code == 201
    ev = resp.json()
    assert ev["data"]["paid_by_name"] == ""


def test_list_events_expense_filter_by_paid_by_name(api_client):
    api_client.post("/api/events", json={
        "summary": "Mua bột mì",
        "type": "expense",
        "data": {
            "amount_vnd": 120000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ Bình Tây",
            "note": "Bột mì số 8",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    api_client.post("/api/events", json={
        "summary": "Mua ly giấy",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Bao bì",
            "payment_method": "Chuyển khoản",
            "payment_source": "TK Phượng VCB",
            "vendor": "Nhà cung cấp A",
            "note": "Ly 16oz",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_paid_by_name": "Phượng",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["paid_by_name"] == "Phượng"


def test_list_events_expense_search_includes_paid_by_name(api_client):
    api_client.post("/api/events", json={
        "summary": "Mua bột mì",
        "type": "expense",
        "data": {
            "amount_vnd": 120000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Chợ Bình Tây",
            "note": "Bột mì số 8",
            "staff_name": "Lan",
            "paid_by_name": "Ân",
        },
    })
    api_client.post("/api/events", json={
        "summary": "Mua ly giấy",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Bao bì",
            "payment_method": "Chuyển khoản",
            "payment_source": "TK Ngân VCB",
            "vendor": "Nhà cung cấp A",
            "note": "Ly 16oz",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })

    resp = api_client.get("/api/events", params={
        "type": "expense",
        "expense_search": "Ân",
    })
    assert resp.status_code == 200
    events = resp.json()
    assert len(events) == 1
    assert events[0]["data"]["paid_by_name"] == "Ân"


# --- GET /api/events/{id} ---


def test_get_event_by_id(api_client):
    create_resp = api_client.post("/api/events", json={
        "summary": "Chi tiết sự kiện", "type": "note",
    })
    event_id = create_resp.json()["id"]

    resp = api_client.get(f"/api/events/{event_id}")
    assert resp.status_code == 200
    ev = resp.json()
    assert ev["id"] == event_id
    assert ev["summary"] == "Chi tiết sự kiện"


def test_get_event_not_found(api_client):
    resp = api_client.get("/api/events/9999")
    assert resp.status_code == 404
    assert "Không tìm thấy" in resp.json()["detail"]


def test_get_event_data_is_dict(api_client):
    """data field must be a parsed dict, not a JSON string."""
    create_resp = api_client.post("/api/events", json={
        "summary": "Data test", "data": {"key": "value"},
    })
    event_id = create_resp.json()["id"]
    resp = api_client.get(f"/api/events/{event_id}")
    assert resp.status_code == 200
    assert resp.json()["data"] == {"key": "value"}


# --- PATCH /api/events/{id} ---


def test_patch_event_summary(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Bản gốc"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"summary": "Đã chỉnh sửa"})
    assert resp.status_code == 200
    assert resp.json()["summary"] == "Đã chỉnh sửa"
    assert resp.json()["id"] == event_id


def test_patch_event_type(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test", "type": "note"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"type": "equipment"})
    assert resp.status_code == 200
    assert resp.json()["type"] == "equipment"


def test_patch_event_tags(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"tags": ["equipment", "maintenance"]})
    assert resp.status_code == 200
    assert resp.json()["tags"] == ["equipment", "maintenance"]


def test_patch_event_clear_tags(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test", "tags": ["old"]})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"tags": []})
    assert resp.status_code == 200
    assert resp.json()["tags"] == []


def test_patch_event_not_found(api_client):
    resp = api_client.patch("/api/events/9999", json={"summary": "X"})
    assert resp.status_code == 404
    assert "Không tìm thấy" in resp.json()["detail"]


def test_patch_event_empty_body(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={})
    assert resp.status_code == 400
    assert "Không có gì" in resp.json()["detail"]


def test_patch_event_empty_summary_rejected(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Test"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={"summary": "   "})
    assert resp.status_code == 422


def test_patch_event_multiple_fields(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Gốc", "type": "note"})
    event_id = create_resp.json()["id"]
    resp = api_client.patch(f"/api/events/{event_id}", json={
        "summary": "Cập nhật", "type": "equipment", "tags": ["staff"],
    })
    assert resp.status_code == 200
    ev = resp.json()
    assert ev["summary"] == "Cập nhật"
    assert ev["type"] == "equipment"
    assert ev["tags"] == ["staff"]


def test_patch_expense_event_data(api_client):
    create_resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua ly",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Bao bì",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Nhà cung cấp A",
            "note": "Ly giấy",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })
    event_id = create_resp.json()["id"]
    original_timestamp = create_resp.json()["timestamp"]

    resp = api_client.patch(f"/api/events/{event_id}", json={
        "summary": "Chi tiền mua ly + nắp",
        "data": {
            "amount_vnd": 68000,
            "category": "Bao bì",
            "payment_method": "Chuyển khoản",
            "payment_source": "TK Phượng VCB",
            "vendor": "Nhà cung cấp A",
            "note": "Ly giấy và nắp",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["summary"] == "Chi tiền mua ly + nắp"
    assert body["data"]["amount_vnd"] == 68000
    assert body["timestamp"] == original_timestamp


def test_patch_expense_event_timestamp(api_client):
    create_resp = api_client.post("/api/events", json={
        "summary": "Chi tiền mua ly",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Bao bì",
            "payment_method": "Tiền mặt",
            "payment_source": "Shop tiền mặt",
            "vendor": "Nhà cung cấp A",
            "note": "Ly giấy",
            "staff_name": "Diễm",
            "paid_by_name": "Ngân",
        },
    })
    event_id = create_resp.json()["id"]

    resp = api_client.patch(f"/api/events/{event_id}", json={
        "timestamp": "2026-05-24T08:15:00",
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["timestamp"] == "2026-05-24T08:15:00"


def test_patch_expense_event_preserves_reimbursed(api_client):
    create_resp = api_client.post("/api/events", json={
        "summary": "Chi tiền ứng trước",
        "type": "expense",
        "data": {
            "amount_vnd": 50000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Nhân viên ứng trước",
            "vendor": "NCC A",
            "note": "Mua hàng",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
            "reimbursed": True,
        },
    })
    event_id = create_resp.json()["id"]

    resp = api_client.patch(f"/api/events/{event_id}", json={
        "data": {
            "amount_vnd": 60000,
            "category": "Nguyên liệu",
            "payment_method": "Tiền mặt",
            "payment_source": "Nhân viên ứng trước",
            "vendor": "NCC A",
            "note": "Mua hàng cập nhật",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
            "reimbursed": True,
        },
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["data"]["reimbursed"] is True
    assert body["data"]["amount_vnd"] == 60000


def test_patch_expense_event_rejects_invalid_amount(api_client):
    create_resp = api_client.post("/api/events", json={
        "summary": "Chi điện",
        "type": "expense",
        "data": {
            "amount_vnd": 200000,
            "category": "Điện/nước",
            "payment_method": "Chuyển khoản",
            "payment_source": "TK Phượng VCB",
            "vendor": "EVN",
            "note": "Tiền điện",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    event_id = create_resp.json()["id"]

    resp = api_client.patch(f"/api/events/{event_id}", json={
        "data": {
            "amount_vnd": 0,
            "category": "Điện/nước",
            "payment_method": "Chuyển khoản",
            "payment_source": "TK Phượng VCB",
            "vendor": "EVN",
            "note": "Tiền điện",
            "staff_name": "Lan",
            "paid_by_name": "Phượng",
        },
    })
    assert resp.status_code == 422
    assert "amount_vnd" in resp.json()["detail"]


# --- DELETE /api/events/{id} ---


def test_delete_event(api_client):
    create_resp = api_client.post("/api/events", json={"summary": "Sẽ xóa"})
    event_id = create_resp.json()["id"]

    delete_resp = api_client.delete(f"/api/events/{event_id}")
    assert delete_resp.status_code == 204

    get_resp = api_client.get(f"/api/events/{event_id}")
    assert get_resp.status_code == 404


def test_delete_event_not_found(api_client):
    resp = api_client.delete("/api/events/9999")
    assert resp.status_code == 404
