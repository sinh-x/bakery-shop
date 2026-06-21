"""Events API routes — create, list, and detail."""

import json
import logging
import re
from datetime import datetime
from typing import Any

from fastapi import APIRouter, Form, HTTPException, Query, UploadFile
from PIL import UnidentifiedImageError
from pydantic import BaseModel

from baker.api.photos import read_image_upload, save_photo
from baker.db.connection import get_db
from baker.db.queries import fetch_events, find_staff_by_name, link_event_person
from baker.models.event import Event
from baker.models.order import Order

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/events", tags=["events"])

VALID_TYPES = {"note", "equipment", "production", "inventory", "expense", "delivery", "order"}

STAFF_ADVANCE_PAYMENT_SOURCE = "Nhân viên ứng trước"


class EventCreate(BaseModel):
    summary: str
    type: str = "note"
    tags: list[str] = []
    logged_by: str = ""
    data: dict[str, Any] = {}
    source: str = "app"
    timestamp: str | None = None
    orderId: int | None = None


def _row_to_dict(row) -> dict:
    """Convert event sqlite Row to a clean API dict."""
    d = dict(row)
    tags_str = d.get("tags") or ""
    d["tags"] = [t for t in tags_str.split(",") if t]
    try:
        d["data"] = json.loads(d["data"]) if d.get("data") else {}
    except (json.JSONDecodeError, TypeError):
        d["data"] = {}
    if "order_id" in d:
        d["orderId"] = d.pop("order_id")
    else:
        d["orderId"] = None
    d.pop("order_id", None)
    d.pop("deleted_at", None)
    d.pop("deleted_by", None)
    return d


@router.post("", status_code=201)
def create_event(body: EventCreate):
    """Tạo sự kiện mới."""
    if not body.summary.strip():
        raise HTTPException(status_code=422, detail="summary không được để trống")

    _validate_expense_data(body.type, body.data)
    timestamp = _normalize_timestamp(body.timestamp)

    if body.orderId is not None:
        if not Order.exists(body.orderId):
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")

    event = Event(
        summary=body.summary.strip(),
        type=body.type,
        tags=body.tags,
        logged_by=body.logged_by,
        data=body.data,
        source=body.source,
        timestamp=timestamp,
        order_id=body.orderId,
    )

    with get_db() as conn:
        event_id = event.save(conn)

        actor = body.logged_by if body.logged_by else ("CLI" if body.source == "cli" else "")
        _log_event_history(conn, event_id, "create", actor=actor)

        # Link logger to event_people if they exist in staff table
        if body.logged_by:
            staff = find_staff_by_name(conn, body.logged_by)
            if staff:
                link_event_person(conn, event_id, staff["id"], "logged_by")

        row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
        return _row_to_dict(row)


@router.get("")
def list_events(
    type: str | None = Query(None, description="Lọc theo loại sự kiện"),
    tag: str | None = Query(None, description="Lọc theo tag (phân cách bằng dấu phẩy)"),
    search: str | None = Query(None, description="Tìm trong nội dung"),
    since: str | None = Query(None, description="Từ ngày (ISO format)"),
    until: str | None = Query(None, description="Đến ngày (ISO format)"),
    logged_by: str | None = Query(None, description="Lọc theo người ghi"),
    expense_category: str | None = Query(None, description="Lọc chi phí theo danh mục"),
    expense_payment_method: str | None = Query(None, description="Lọc chi phí theo phương thức thanh toán"),
    expense_staff_name: str | None = Query(None, description="Lọc chi phí theo nhân viên"),
    expense_paid_by_name: str | None = Query(None, description="Lọc chi phí theo người trả"),
    expense_payment_source: str | None = Query(None, description="Lọc chi phí theo nguồn tiền"),
    expense_search: str | None = Query(None, description="Tìm kiếm chi phí trong tóm tắt, NCC, ghi chú, nhân viên, người trả, nguồn tiền"),
    limit: int = Query(50, ge=1, le=500, description="Số kết quả tối đa"),
):
    """Danh sách sự kiện với bộ lọc."""
    tags = [t.strip() for t in tag.split(",") if t.strip()] if tag else None

    with get_db() as conn:
        rows = fetch_events(
            conn,
            event_type=type,
            tags=tags,
            since=since,
            until=until,
            search=search,
            logged_by=logged_by,
            expense_category=expense_category,
            expense_payment_method=expense_payment_method,
            expense_staff_name=expense_staff_name,
            expense_paid_by_name=expense_paid_by_name,
            expense_payment_source=expense_payment_source,
            expense_search=expense_search,
            limit=limit,
        )
        return [_row_to_dict(r) for r in rows]


@router.get("/{event_id}")
def get_event(event_id: int):
    """Chi tiết một sự kiện."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM events WHERE id = ? AND deleted_at IS NULL", (event_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sự kiện")
        return _row_to_dict(row)


class EventUpdate(BaseModel):
    summary: str | None = None
    type: str | None = None
    tags: list[str] | None = None
    logged_by: str | None = None
    data: dict[str, Any] | None = None
    timestamp: str | None = None


def _log_event_history(conn, event_id, action_type, actor="", field_name="", old_value="", new_value=""):
    conn.execute(
        """INSERT INTO event_history (event_id, action_type, actor, field_name, old_value, new_value)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (event_id, action_type, actor, field_name, old_value, new_value),
    )


_TZ_RE = re.compile(r'(Z|[+-]\d{2}:?\d{2})$')


def _normalize_timestamp(raw: str | None) -> str | None:
    if raw is None:
        return None
    value = raw.strip()
    if not value:
        raise HTTPException(status_code=422, detail="timestamp không được để trống")
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="timestamp không đúng định dạng ISO") from exc
    if not _TZ_RE.search(value):
        return f"{value}+07:00"
    return value


def _validate_expense_data(event_type: str, data: dict[str, Any]) -> None:
    if event_type != "expense":
        return

    required_keys = {
        "amount_vnd",
        "category",
        "payment_method",
        "payment_source",
        "vendor",
        "note",
        "staff_name",
        "paid_by_name",
    }
    missing_keys = [key for key in required_keys if key not in data]
    if missing_keys:
        raise HTTPException(
            status_code=422,
            detail=f"expense data thiếu trường bắt buộc: {', '.join(sorted(missing_keys))}",
        )

    amount_vnd = data.get("amount_vnd")
    if not isinstance(amount_vnd, int) or amount_vnd <= 0:
        raise HTTPException(status_code=422, detail="amount_vnd phải là số nguyên lớn hơn 0")

    payment_source = data.get("payment_source", "")
    if payment_source == STAFF_ADVANCE_PAYMENT_SOURCE and not data.get("staff_name", "").strip():
        raise HTTPException(
            status_code=422,
            detail="Tên nhân viên là bắt buộc khi chọn Nhân viên ứng trước",
        )

    paid_by_name = data.get("paid_by_name", "")
    if paid_by_name.strip():
        with get_db() as conn:
            staff = find_staff_by_name(conn, paid_by_name.strip())
            if not staff:
                raise HTTPException(
                    status_code=422,
                    detail=f"paid_by_name '{paid_by_name}' không khớp với nhân viên nào trong hệ thống",
                )


@router.patch("/{event_id}")
def update_event(event_id: int, body: EventUpdate):
    """Cập nhật sự kiện (summary, type, tags, logged_by, data)."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM events WHERE id = ? AND deleted_at IS NULL", (event_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sự kiện")

        data = body.model_dump(exclude_unset=True)
        if not data:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        fields: list[str] = []
        values: list = []

        if "summary" in data:
            if not data["summary"].strip():
                raise HTTPException(status_code=422, detail="summary không được để trống")
            fields.append("summary = ?")
            values.append(data["summary"].strip())

        if "type" in data:
            fields.append("type = ?")
            values.append(data["type"])

        if "tags" in data:
            fields.append("tags = ?")
            values.append(",".join(data["tags"]))

        if "logged_by" in data:
            fields.append("logged_by = ?")
            values.append(data["logged_by"])

        if "timestamp" in data:
            fields.append("timestamp = ?")
            values.append(_normalize_timestamp(data["timestamp"]))

        next_type = data.get("type", row["type"])
        next_data = data.get("data")
        if next_data is None:
            try:
                next_data = json.loads(row["data"]) if row["data"] else {}
            except (json.JSONDecodeError, TypeError):
                next_data = {}

        _validate_expense_data(next_type, next_data)

        if "data" in data:
            fields.append("data = ?")
            values.append(json.dumps(data["data"]))

        # Log edit entries for each changed field before executing the update
        for field_name, new_val in data.items():
            if field_name == "data":
                old_json = row["data"] or ""
                new_json = json.dumps(data["data"])
                if old_json != new_json:
                    _log_event_history(conn, event_id, "edit", field_name=field_name,
                                       old_value=old_json, new_value=new_json)
            elif field_name == "tags":
                old_tags = row["tags"] or ""
                new_tags = ",".join(data["tags"])
                if old_tags != new_tags:
                    _log_event_history(conn, event_id, "edit", field_name=field_name,
                                       old_value=old_tags, new_value=new_tags)
            elif field_name == "timestamp":
                old_ts = row["timestamp"] or ""
                new_ts = _normalize_timestamp(data["timestamp"]) or ""
                if old_ts != new_ts:
                    _log_event_history(conn, event_id, "edit", field_name=field_name,
                                       old_value=old_ts, new_value=new_ts)
            else:
                old_val = str(row[field_name]) if row[field_name] is not None else ""
                new_val = str(new_val) if new_val is not None else ""
                if old_val != new_val:
                    _log_event_history(conn, event_id, "edit", field_name=field_name,
                                       old_value=old_val, new_value=new_val)

        values.append(event_id)
        conn.execute(f"UPDATE events SET {', '.join(fields)} WHERE id = ?", values)

        row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
        return _row_to_dict(row)


@router.delete("/{event_id}", status_code=204)
def delete_event(event_id: int, deleted_by: str = Query("", description="Người thực hiện xóa")):
    """Xóa mềm sự kiện theo id."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM events WHERE id = ? AND deleted_at IS NULL", (event_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sự kiện")

        now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
        conn.execute(
            "UPDATE events SET deleted_at = ?, deleted_by = ? WHERE id = ?",
            (now, deleted_by, event_id),
        )
        _log_event_history(conn, event_id, "delete", actor=deleted_by)


def _get_event_or_404(conn, event_id: int):
    row = conn.execute(
        "SELECT * FROM events WHERE id = ? AND deleted_at IS NULL", (event_id,)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy sự kiện")
    return row


@router.get("/{event_id}/photos")
def list_event_photos(event_id: int):
    """Danh sách ảnh đính kèm sự kiện."""
    with get_db() as conn:
        _get_event_or_404(conn, event_id)
        rows = conn.execute(
            "SELECT ep.*, ph.hash as photo_hash "
            "FROM event_photos ep "
            "LEFT JOIN photos ph ON ep.photo_id = ph.id "
            "WHERE ep.event_id = ? ORDER BY ep.position, ep.id",
            (event_id,),
        ).fetchall()
        return [dict(r) for r in rows]


@router.post("/{event_id}/photos", status_code=201)
async def upload_event_photo(
    event_id: int,
    file: UploadFile,
    tags: str = Form(""),
):
    """Tải lên ảnh đính kèm cho sự kiện."""
    with get_db() as conn:
        _get_event_or_404(conn, event_id)

    data = await read_image_upload(file)

    try:
        hash_hex = save_photo(data, file.filename or "")
    except (UnidentifiedImageError, OSError, ValueError):
        logger.exception("Event photo upload failed for event %d, file: %s", event_id, file.filename)
        raise HTTPException(status_code=400, detail="Không thể xử lý hình ảnh")

    with get_db() as conn:
        photo_row = conn.execute(
            "SELECT id FROM photos WHERE hash = ?", (hash_hex,)
        ).fetchone()
        photo_id = photo_row[0] if photo_row else None

        if photo_id is not None:
            existing = conn.execute(
                "SELECT ep.*, ph.hash as photo_hash "
                "FROM event_photos ep "
                "LEFT JOIN photos ph ON ep.photo_id = ph.id "
                "WHERE ep.event_id = ? AND ep.photo_id = ?",
                (event_id, photo_id),
            ).fetchone()
            if existing:
                return dict(existing)

        result = conn.execute(
            "SELECT COALESCE(MAX(position), -1) + 1 FROM event_photos WHERE event_id = ?",
            (event_id,),
        ).fetchone()
        next_position = result[0]

        cursor = conn.execute(
            "INSERT INTO event_photos (event_id, photo_id, tags, position) "
            "VALUES (?, ?, ?, ?)",
            (event_id, photo_id, tags, next_position),
        )
        new_id = cursor.lastrowid

        row = conn.execute(
            "SELECT ep.*, ph.hash as photo_hash "
            "FROM event_photos ep "
            "LEFT JOIN photos ph ON ep.photo_id = ph.id "
            "WHERE ep.id = ?",
            (new_id,),
        ).fetchone()
        return dict(row)


@router.delete("/{event_id}/photos/{photo_id}", status_code=200)
def delete_event_photo(event_id: int, photo_id: int):
    """Xóa ảnh khỏi sự kiện (chỉ xóa bản ghi DB, giữ file hash trên đĩa)."""
    with get_db() as conn:
        _get_event_or_404(conn, event_id)

        row = conn.execute(
            "SELECT * FROM event_photos WHERE id = ? AND event_id = ?",
            (photo_id, event_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")

        conn.execute("DELETE FROM event_photos WHERE id = ?", (photo_id,))

    return {"message": "Đã xóa ảnh"}
