"""App config API routes — general key/value configuration (e.g. order sources)."""

from fastapi import APIRouter

from baker.db.connection import get_db


router = APIRouter(prefix="/api/config", tags=["config"])


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
