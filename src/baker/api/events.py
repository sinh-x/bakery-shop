"""Events API routes — create, list, and detail."""

import json
from datetime import datetime
from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.db.queries import fetch_events, find_staff_by_name, link_event_person
from baker.models.event import Event

router = APIRouter(prefix="/api/events", tags=["events"])

VALID_TYPES = {"note", "equipment", "production", "inventory", "expense", "delivery", "order"}


class EventCreate(BaseModel):
    summary: str
    type: str = "note"
    tags: list[str] = []
    logged_by: str = ""
    data: dict[str, Any] = {}
    source: str = "app"


def _row_to_dict(row) -> dict:
    """Convert event sqlite Row to a clean API dict."""
    d = dict(row)
    tags_str = d.get("tags") or ""
    d["tags"] = [t for t in tags_str.split(",") if t]
    try:
        d["data"] = json.loads(d["data"]) if d.get("data") else {}
    except (json.JSONDecodeError, TypeError):
        d["data"] = {}
    return d


@router.post("", status_code=201)
def create_event(body: EventCreate):
    """Tạo sự kiện mới."""
    if not body.summary.strip():
        raise HTTPException(status_code=422, detail="summary không được để trống")

    event = Event(
        summary=body.summary.strip(),
        type=body.type,
        tags=body.tags,
        logged_by=body.logged_by,
        data=body.data,
        source=body.source,
    )

    with get_db() as conn:
        event_id = event.save(conn)

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
            limit=limit,
        )
        return [_row_to_dict(r) for r in rows]


@router.get("/{event_id}")
def get_event(event_id: int):
    """Chi tiết một sự kiện."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy sự kiện")
        return _row_to_dict(row)


class EventUpdate(BaseModel):
    summary: str | None = None
    type: str | None = None
    tags: list[str] | None = None
    logged_by: str | None = None


@router.patch("/{event_id}")
def update_event(event_id: int, body: EventUpdate):
    """Cập nhật sự kiện (summary, type, tags)."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
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

        values.append(event_id)
        conn.execute(f"UPDATE events SET {', '.join(fields)} WHERE id = ?", values)

        row = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
        return _row_to_dict(row)
