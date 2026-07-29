"""Staff API routes."""

from fastapi import APIRouter

from baker.db.connection import get_db
from baker.db.queries import fetch_staff
from baker.utils.db import row_to_dict as _row_to_dict


router = APIRouter(prefix="/api/staff", tags=["staff"])


@router.get("")
def list_staff():
    """Danh sách nhân viên đang hoạt động."""
    with get_db() as conn:
        rows = fetch_staff(conn, active_only=True)
        return [
            {
                "id": r["id"],
                "name": r["name"],
                "role": r["role"],
                "active": r["active"],
            }
            for r in rows
        ]
