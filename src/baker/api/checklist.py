"""Checklist API routes — daily opening/closing checklist for staff."""

from datetime import date as date_type
from typing import Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.utils.time import now_utc


router = APIRouter(prefix="/api/checklist", tags=["checklist"])


# ── Pydantic models ──────────────────────────────────────────────────────────


class TemplateCreate(BaseModel):
    name: str
    period: str = "opening"
    sort_order: int = 0
    active: bool = True


class TemplateUpdate(BaseModel):
    name: Optional[str] = None
    period: Optional[str] = None
    sort_order: Optional[int] = None
    active: Optional[bool] = None


class ToggleRequest(BaseModel):
    staff_name: str = ""


# ── Helpers ──────────────────────────────────────────────────────────────────


def _template_row(row) -> dict:
    return {
        "id": row["id"],
        "name": row["name"],
        "period": row["period"],
        "sort_order": row["sort_order"],
        "active": bool(row["active"]),
        "created_at": row["created_at"],
    }


def _entry_row(row) -> dict:
    return {
        "id": row["id"],
        "template_id": row["template_id"],
        "checklist_date": row["checklist_date"],
        "completed": bool(row["completed"]),
        "completed_by": row["completed_by"] or "",
        "completed_at": row["completed_at"],
        "created_at": row["created_at"],
        "template_name": row["template_name"] if "template_name" in row.keys() else None,
        "template_period": row["template_period"] if "template_period" in row.keys() else None,
        "template_sort_order": row["template_sort_order"] if "template_sort_order" in row.keys() else None,
    }


def _ensure_daily_entries(conn, checklist_date: str):
    """Generate checklist_entries for the given date from active templates if not yet created."""
    active_templates = conn.execute(
        "SELECT id FROM checklist_templates WHERE active = 1 ORDER BY period, sort_order",
    ).fetchall()
    for tmpl in active_templates:
        conn.execute(
            "INSERT OR IGNORE INTO checklist_entries (template_id, checklist_date) VALUES (?, ?)",
            (tmpl["id"], checklist_date),
        )


# ── Template endpoints ───────────────────────────────────────────────────────


@router.get("/templates")
def list_templates(period: Optional[str] = None):
    """Danh sách mẫu checklist (lọc theo ca nếu có)."""
    with get_db() as conn:
        if period:
            rows = conn.execute(
                "SELECT * FROM checklist_templates WHERE period = ? ORDER BY sort_order, id",
                (period,),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM checklist_templates ORDER BY period, sort_order, id",
            ).fetchall()
        return [_template_row(r) for r in rows]


@router.post("/templates", status_code=201)
def create_template(body: TemplateCreate):
    """Tạo mẫu checklist mới."""
    if body.period not in ("opening", "closing"):
        raise HTTPException(status_code=400, detail="period phải là 'opening' hoặc 'closing'")
    with get_db() as conn:
        cursor = conn.execute(
            "INSERT INTO checklist_templates (name, period, sort_order, active) VALUES (?, ?, ?, ?)",
            (body.name, body.period, body.sort_order, 1 if body.active else 0),
        )
        row = conn.execute(
            "SELECT * FROM checklist_templates WHERE id = ?", (cursor.lastrowid,)
        ).fetchone()
        return _template_row(row)


@router.put("/templates/{template_id}")
def update_template(template_id: int, body: TemplateUpdate):
    """Cập nhật mẫu checklist."""
    with get_db() as conn:
        existing = conn.execute(
            "SELECT * FROM checklist_templates WHERE id = ?", (template_id,)
        ).fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Không tìm thấy mẫu checklist")

        if body.period is not None and body.period not in ("opening", "closing"):
            raise HTTPException(status_code=400, detail="period phải là 'opening' hoặc 'closing'")

        fields = {}
        if body.name is not None:
            fields["name"] = body.name
        if body.period is not None:
            fields["period"] = body.period
        if body.sort_order is not None:
            fields["sort_order"] = body.sort_order
        if body.active is not None:
            fields["active"] = 1 if body.active else 0

        if fields:
            set_clause = ", ".join(f"{k} = ?" for k in fields)
            values = list(fields.values()) + [template_id]
            conn.execute(
                f"UPDATE checklist_templates SET {set_clause} WHERE id = ?", values
            )

        row = conn.execute(
            "SELECT * FROM checklist_templates WHERE id = ?", (template_id,)
        ).fetchone()
        return _template_row(row)


@router.delete("/templates/{template_id}", status_code=204)
def delete_template(template_id: int):
    """Xóa mẫu checklist."""
    with get_db() as conn:
        existing = conn.execute(
            "SELECT id FROM checklist_templates WHERE id = ?", (template_id,)
        ).fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Không tìm thấy mẫu checklist")
        conn.execute("DELETE FROM checklist_templates WHERE id = ?", (template_id,))


# ── Daily checklist endpoints ────────────────────────────────────────────────


@router.get("/daily")
def get_daily_checklist(date: Optional[str] = None):
    """Lấy checklist trong ngày. Tự động tạo nếu chưa có."""
    checklist_date = date or date_type.today().isoformat()
    with get_db() as conn:
        _ensure_daily_entries(conn, checklist_date)
        rows = conn.execute(
            """SELECT e.*, t.name AS template_name, t.period AS template_period,
                      t.sort_order AS template_sort_order
               FROM checklist_entries e
               JOIN checklist_templates t ON e.template_id = t.id
               WHERE e.checklist_date = ?
               ORDER BY t.period, t.sort_order, e.id""",
            (checklist_date,),
        ).fetchall()
        return {
            "date": checklist_date,
            "entries": [_entry_row(r) for r in rows],
        }


@router.post("/daily/{entry_id}/toggle")
def toggle_entry(entry_id: int, body: ToggleRequest):
    """Đánh dấu hoàn thành / bỏ đánh dấu một mục checklist."""
    with get_db() as conn:
        existing = conn.execute(
            "SELECT * FROM checklist_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not existing:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục checklist")

        if existing["completed"]:
            # Untick
            conn.execute(
                "UPDATE checklist_entries SET completed = 0, completed_by = '', completed_at = NULL WHERE id = ?",
                (entry_id,),
            )
        else:
            # Tick
            conn.execute(
                "UPDATE checklist_entries SET completed = 1, completed_by = ?, "
                "completed_at = ? WHERE id = ?",
                (body.staff_name, now_utc(), entry_id),
            )

        row = conn.execute(
            """SELECT e.*, t.name AS template_name, t.period AS template_period,
                      t.sort_order AS template_sort_order
               FROM checklist_entries e
               JOIN checklist_templates t ON e.template_id = t.id
               WHERE e.id = ?""",
            (entry_id,),
        ).fetchone()
        return _entry_row(row)


# ── History endpoint ─────────────────────────────────────────────────────────


@router.get("/history")
def get_checklist_history(
    from_date: Optional[str] = None,
    to_date: Optional[str] = None,
):
    """Lịch sử checklist theo khoảng ngày."""
    today = date_type.today().isoformat()
    start = from_date or today
    end = to_date or today

    with get_db() as conn:
        rows = conn.execute(
            """SELECT e.*, t.name AS template_name, t.period AS template_period,
                      t.sort_order AS template_sort_order
               FROM checklist_entries e
               JOIN checklist_templates t ON e.template_id = t.id
               WHERE e.checklist_date BETWEEN ? AND ?
               ORDER BY e.checklist_date DESC, t.period, t.sort_order, e.id""",
            (start, end),
        ).fetchall()

        # Group by date
        by_date: dict = {}
        for row in rows:
            d = row["checklist_date"]
            if d not in by_date:
                by_date[d] = []
            by_date[d].append(_entry_row(row))

        return [
            {"date": d, "entries": entries}
            for d, entries in sorted(by_date.items(), reverse=True)
        ]
