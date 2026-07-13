"""App config API routes — general key/value configuration (e.g. order sources)."""

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from baker.config import TIMEZONE
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
            "INSERT INTO app_config (config_key, config_value, sort_order, created_at) VALUES (?, ?, ?, ?)",
            (config_key, body.value, body.sort_order, now_utc()),
        )
        return {"id": cursor.lastrowid, "config_key": config_key, "value": body.value, "sort_order": body.sort_order}





@router.get("/{config_key}/usage")
def get_config_usage(config_key: str, key: str = Query(...)):
    """Trả về thông tin sử dụng của một key trong config.
    
    Chỉ áp dụng cho config_key = 'catalog_tag'. Trả về count và product_ids
    của các catalog_photo_tags đang sử dụng key này.
    """
    if config_key != "catalog_tag":
        raise HTTPException(status_code=404, detail="Usage endpoint chỉ hỗ trợ catalog_tag")
    
    with get_db() as conn:
        # Kiểm tra key có tồn tại trong app_config không
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


@router.put("/{config_key}")
def update_config(config_key: str, body: ConfigValueUpdate):
    """Cập nhật giá trị cấu hình (theo old_value).
    
    Với config_key = 'catalog_tag', nếu key trong config_value thay đổi thì
    cập nhật tất cả catalog_photo_tags.tag_key cùng transaction.
    """
    with get_db() as conn:
        # Kiểm tra nếu là catalog_tag và key thay đổi
        if config_key == "catalog_tag":
            # Parse old and new values to check if key changes
            old_parts = body.old_value.split(":")
            new_parts = body.new_value.split(":")
            
            # Kiểm tra định dạng hợp lệ
            if len(old_parts) != 3 or len(new_parts) != 3:
                # Nếu không phải định dạng catalog_tag, thực hiện cập nhật bình thường
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
            
            old_key = old_parts[1]
            new_key = new_parts[1]
            
            # Nếu key thay đổi, kiểm tra xem new_key đã tồn tại chưa
            if old_key != new_key:
                existing = conn.execute(
                    "SELECT 1 FROM app_config WHERE config_key = 'catalog_tag' AND config_value LIKE ?",
                    (f"%:{new_key}:%",)
                ).fetchone()
                
                if existing:
                    raise HTTPException(status_code=409, detail=f"Khoá '{new_key}' đã tồn tại")
                
                # Thực hiện cập nhật trong cùng một transaction
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
                
                # Cập nhật tất cả catalog_photo_tags có tag_key = old_key
                conn.execute(
                    "UPDATE catalog_photo_tags SET tag_key = ? WHERE tag_key = ?",
                    (new_key, old_key)
                )
            else:
                # Chỉ thay đổi label, không thay đổi key
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
        else:
            # Thực hiện cập nhật bình thường cho các config_key khác
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
    """Xóa một giá trị cấu hình theo config_key và value.
    
    Với config_key = 'catalog_tag', kiểm tra xem key có đang được sử dụng
    trong catalog_photo_tags hay không.
    """
    with get_db() as conn:
        if config_key == "catalog_tag":
            # Parse value để lấy key
            parts = value.split(":")
            if len(parts) == 3:
                key = parts[1]
                # Kiểm tra xem key có đang được sử dụng không
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
        return {"config_key": config_key, "value": value}
