"""App config API routes — general key/value configuration (e.g. order sources)."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from baker.api.auth import RequireRole, record_audit_log
from baker.config import (
    DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY,
    DELIVERY_CRITICAL_THRESHOLD_MINUTES,
    TIMEZONE,
    get_delivery_critical_threshold,
)
from baker.db.connection import get_db
from baker.utils.time import now_utc


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


class DeliveryCriticalThresholdIn(BaseModel):
    minutes: int = Field(ge=1, le=10080)


@router.get("/delivery_critical_threshold_minutes")
def get_delivery_critical_threshold_endpoint():
    """Return the effective delivery critical threshold (minutes).

    DB override (app_config.delivery_critical_threshold_minutes) takes
    precedence over the env var default (NFR1, DG-253 Phase 5.6-c1). Mirrors
    the paper-mode GET pattern. Declared before the generic ``/{config_key}``
    route so the literal path wins.
    """
    with get_db() as conn:
        return {
            "minutes": get_delivery_critical_threshold(conn),
            "default": DELIVERY_CRITICAL_THRESHOLD_MINUTES,
        }


@router.put("/delivery_critical_threshold_minutes")
def set_delivery_critical_threshold(
    body: DeliveryCriticalThresholdIn,
    actor: str = Depends(RequireRole("admin")),
):
    """Set the delivery critical threshold runtime override (persists to app_config).

    Takes effect on the next order/list/detail request (no restart required).
    Mirrors the ``set_paper_mode`` upsert pattern. Rejects values < 1 or > 10080
    (7 days) — values above 10080 overflow ``timedelta`` and break all order
    endpoints with 500s (DG-253 review-auto r2 MAJOR).
    """
    value = body.minutes
    if value < 1:
        raise HTTPException(
            status_code=422,
            detail="Threshold phải ≥ 1 phút",
        )
    if value > 10080:
        raise HTTPException(
            status_code=422,
            detail="Threshold phải ≤ 10080 phút (7 ngày)",
        )
    with get_db() as conn:
        existing = conn.execute(
            "SELECT id, config_value FROM app_config WHERE config_key = ?",
            (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY,),
        ).fetchone()
        if existing is not None:
            old_value_payload = {
                "config_key": DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY,
                "config_value": existing["config_value"],
            }
            conn.execute(
                "UPDATE app_config SET config_value = ?, active = 1 WHERE config_key = ?",
                (str(value), DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY),
            )
        else:
            old_value_payload = None
            conn.execute(
                "INSERT INTO app_config (config_key, config_value, sort_order, active, created_at)"
                " VALUES (?, ?, 0, 1, ?)",
                (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, str(value), now_utc()),
            )
        record_audit_log(
            conn,
            actor,
            "update",
            "config",
            f"{DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY}",
            old_value=old_value_payload,
            new_value={"config_key": DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY, "config_value": str(value)},
        )
    return {"minutes": value}


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
def create_config(config_key: str, body: ConfigValueIn, actor: str = Depends(RequireRole("admin"))):
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
            "INSERT INTO app_config (config_key, config_value, sort_order, created_at) VALUES (?, ?, ?, ?)",
            (config_key, body.value, body.sort_order, now_utc()),
        )
        new_id = cursor.lastrowid
        record_audit_log(
            conn,
            actor,
            "create",
            "config",
            f"{config_key}:{body.value}",
            old_value=None,
            new_value={"config_key": config_key, "config_value": body.value, "sort_order": body.sort_order},
        )
        return {"id": new_id, "config_key": config_key, "value": body.value, "sort_order": body.sort_order}





@router.get("/{config_key}/usage")
def get_config_usage(config_key: str, key: str = Query(...)):
    """Trả về thông tin sử dụng của một key trong config.
    
    Chỉ áp dụng cho config_key = 'catalog_tag'. Trả về count và product_ids
    của các catalog_photo_tags đang sử dụng key này.
    """
    if config_key != "catalog_tag":
        raise HTTPException(status_code=404, detail="Usage endpoint chỉ hỗ trợ catalog_tag")
    
    with get_db() as conn:
        # Kiểm tra key có tồn tại trong app_config không (match only the key segment)
        tag_row = conn.execute(
            "SELECT 1 FROM app_config WHERE config_key = 'catalog_tag' AND config_value LIKE ?",
            (f"%:{key}:%",)
        ).fetchone()
        
        if not tag_row:
            raise HTTPException(status_code=404, detail="Key không tồn tại")
        
        # Đếm số lượng và lấy product_ids từ catalog_photo_tags
        rows = conn.execute("""
            SELECT DISTINCT pcp.product_id 
            FROM catalog_photo_tags cpt
            JOIN product_catalog_photos pcp ON cpt.photo_id = pcp.id
            WHERE cpt.tag_key = ?
        """, (key,)).fetchall()
        
        product_ids = [row["product_id"] for row in rows]
        count = len(product_ids)
        
        return {
            "key": key,
            "count": count,
            "product_ids": product_ids
        }


def _apply_config_update(conn, config_key: str, old_value: str, new_value: str,
                         sort_order: int | None) -> None:
    """Apply a single UPDATE on app_config, optionally setting sort_order.

    Extracted (QUAL-1) to remove ~50 lines of duplicated UPDATE blocks across
    the catalog_tag key-change, label-only-change, and non-catalog_tag paths.
    """
    if sort_order is not None:
        conn.execute(
            "UPDATE app_config SET config_value = ?, sort_order = ?"
            " WHERE config_key = ? AND config_value = ?",
            (new_value, sort_order, config_key, old_value),
        )
    else:
        conn.execute(
            "UPDATE app_config SET config_value = ?"
            " WHERE config_key = ? AND config_value = ?",
            (new_value, config_key, old_value),
        )


def _parse_catalog_tag_key(value: str) -> str | None:
    """Extract the key segment from a 'category:key:label' config value.

    Uses split(':', 2) so labels containing colons do not break parsing
    (BUG-2). Returns None if the value has fewer than 2 segments.
    """
    parts = value.split(":", 2)
    if len(parts) < 2:
        return None
    return parts[1]


@router.put("/{config_key}")
def update_config(config_key: str, body: ConfigValueUpdate, actor: str = Depends(RequireRole("admin"))):
    """Cập nhật giá trị cấu hình (theo old_value).

    Với config_key = 'catalog_tag', nếu key trong config_value thay đổi thì
    cập nhật tất cả catalog_photo_tags.tag_key cùng transaction.
    """
    with get_db() as conn:
        if config_key == "catalog_tag":
            old_key = _parse_catalog_tag_key(body.old_value)
            new_key = _parse_catalog_tag_key(body.new_value)

            # Nếu key thay đổi, kiểm tra xem new_key đã tồn tại chưa
            if old_key is not None and new_key is not None and old_key != new_key:
                existing = conn.execute(
                    "SELECT 1 FROM app_config WHERE config_key = 'catalog_tag' AND config_value LIKE ?",
                    (f"%:{new_key}:%",)
                ).fetchone()

                if existing:
                    raise HTTPException(status_code=409, detail=f"Khoá '{new_key}' đã tồn tại")

                _apply_config_update(conn, config_key, body.old_value, body.new_value, body.sort_order)

                # Cập nhật tất cả catalog_photo_tags có tag_key = old_key
                conn.execute(
                    "UPDATE catalog_photo_tags SET tag_key = ? WHERE tag_key = ?",
                    (new_key, old_key)
                )
            else:
                _apply_config_update(conn, config_key, body.old_value, body.new_value, body.sort_order)

            record_audit_log(
                conn,
                actor,
                "update",
                "config",
                f"{config_key}:{body.old_value}",
                old_value={"config_key": config_key, "config_value": body.old_value},
                new_value={"config_key": config_key, "config_value": body.new_value, "sort_order": body.sort_order},
            )
            return {"config_key": config_key, "old_value": body.old_value, "new_value": body.new_value}
        else:
            _apply_config_update(conn, config_key, body.old_value, body.new_value, body.sort_order)
            record_audit_log(
                conn,
                actor,
                "update",
                "config",
                f"{config_key}:{body.old_value}",
                old_value={"config_key": config_key, "config_value": body.old_value},
                new_value={"config_key": config_key, "config_value": body.new_value, "sort_order": body.sort_order},
            )
            return {"config_key": config_key, "old_value": body.old_value, "new_value": body.new_value}


@router.delete("/{config_key}")
def delete_config(config_key: str, value: str, actor: str = Depends(RequireRole("admin"))):
    """Xóa một giá trị cấu hình theo config_key và value.

    Với config_key = 'catalog_tag', kiểm tra xem key có đang được sử dụng
    trong catalog_photo_tags hay không.
    """
    with get_db() as conn:
        if config_key == "catalog_tag":
            # Parse value để lấy key (split(':', 2) so colons in label don't break)
            key = _parse_catalog_tag_key(value)
            # Delete-in-use guard ALWAYS runs when a key can be extracted (BUG-2):
            # previously skipped when len(parts) != 3, which happened whenever
            # the label contained a colon.
            if key is not None:
                usage = conn.execute(
                    "SELECT COUNT(*) as count FROM catalog_photo_tags WHERE tag_key = ?",
                    (key,)
                ).fetchone()

                if usage and usage["count"] > 0:
                    raise HTTPException(status_code=409, detail="Tag đang được sử dụng bởi các ảnh")

        conn.execute(
            "DELETE FROM app_config WHERE config_key = ? AND config_value = ?",
            (config_key, value),
        )
        record_audit_log(
            conn,
            actor,
            "delete",
            "config",
            f"{config_key}:{value}",
            old_value={"config_key": config_key, "config_value": value},
            new_value=None,
        )
        return {"config_key": config_key, "value": value}
