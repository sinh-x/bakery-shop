"""App config API routes — general key/value configuration (e.g. order sources)."""

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.config import TIMEZONE
from baker.db.connection import get_db


router = APIRouter(prefix="/api/config", tags=["config"])


class ConfigValueIn(BaseModel):
    value: str
    sort_order: int = 0


class ConfigValueUpdate(BaseModel):
    old_value: str
    new_value: str
    sort_order: int | None = None


@router.get("")
def get_server_config() -> dict:
    """Trả về cấu hình máy chủ (timezone) để Flutter đồng bộ hiển thị.

    DG-202 FR7/AC6: exposes the configured server timezone so the Flutter client
    can read it at startup and use the offset for display conversion.
    """
    offset = TIMEZONE.utcoffset(datetime.now(timezone.utc))
    offset_minutes = int(offset.total_seconds() // 60) if offset else 0
    return {"timezone": str(TIMEZONE), "timezone_offset": offset_minutes}


@router.get("/{config_key}")
def get_config(config_key: str):
    """Trả về danh sách giá trị cấu hình theo config_key."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT config_value, sort_order, active FROM app_config"
            " WHERE config_key = ? ORDER BY sort_order, id",
            (config_key,),
        ).fetchall()
        return [
            {"value": r["config_value"], "sort_order": r["sort_order"], "active": bool(r["active"])}
            for r in rows
        ]


@router.post("/{config_key}")
def create_config(config_key: str, body: ConfigValueIn):
    """Tạo mới một giá trị cấu hình cho config_key."""
    with get_db() as conn:
        # Check if already exists
        existing = conn.execute(
            "SELECT id FROM app_config WHERE config_key = ? AND config_value = ?",
            (config_key, body.value),
        ).fetchone()
        if existing:
            raise HTTPException(status_code=409, detail="Config value already exists")

        cursor = conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES (?, ?, ?)",
            (config_key, body.value, body.sort_order),
        )
        return {"id": cursor.lastrowid, "config_key": config_key, "value": body.value, "sort_order": body.sort_order}


@router.put("/{config_key}")
def update_config(config_key: str, body: ConfigValueUpdate):
    """Cập nhật giá trị cấu hình (theo old_value)."""
    with get_db() as conn:
        if body.sort_order is not None:
            conn.execute(
                "UPDATE app_config SET config_value = ?, sort_order = ?"
                " WHERE config_key = ? AND config_value = ?",
                (body.new_value, body.sort_order, config_key, body.old_value),
            )
        else:
            conn.execute(
                "UPDATE app_config SET config_value = ?"
                " WHERE config_key = ? AND config_value = ?",
                (body.new_value, config_key, body.old_value),
            )
        return {"config_key": config_key, "old_value": body.old_value, "new_value": body.new_value}


@router.delete("/{config_key}")
def delete_config(config_key: str, value: str):
    """Xóa một giá trị cấu hình theo config_key và value."""
    with get_db() as conn:
        conn.execute(
            "DELETE FROM app_config WHERE config_key = ? AND config_value = ?",
            (config_key, value),
        )
        return {"config_key": config_key, "value": value}
