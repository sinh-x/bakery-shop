"""Staff API routes."""

from typing import Optional

from fastapi import APIRouter, Query

from baker.db.connection import get_db
from baker.db.queries import fetch_staff
from baker.utils.db import row_to_dict as _row_to_dict


router = APIRouter(prefix="/api/staff", tags=["staff"])


@router.get("")
def list_staff(role: Optional[str] = Query(None, description="Lọc theo vai trò (ví dụ: giao-hang)")):
    """Danh sách nhân viên đang hoạt động.

    Truyền ``?role=giao-hang`` để chỉ trả về nhân viên có vai trò tương ứng
    (DG-304 Phase 1 / FR1).
    """
    with get_db() as conn:
        rows = fetch_staff(conn, active_only=True, role=role)
        return [
            {
                "id": r["id"],
                "name": r["name"],
                "role": r["role"],
                "active": r["active"],
            }
            for r in rows
        ]
