"""User settings API routes — staff-user binding for admin users."""

import sqlite3

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, StrictInt

from baker.api.auth import RequireRole, record_audit_log
from baker.db.connection import get_db

router = APIRouter(prefix="/api/users", tags=["users"])


class StaffBindingUpdate(BaseModel):
    staff_id: StrictInt | None = None


@router.get("/me/staff-binding")
def get_staff_binding(request: Request):
    """Return the current user's linked staff record."""
    username = getattr(request.state, "auth_username", None)
    if not username:
        raise HTTPException(status_code=401, detail="Not authenticated")

    with get_db() as conn:
        row = conn.execute(
            "SELECT u.staff_id, s.name AS staff_name "
            "FROM users u "
            "LEFT JOIN staff s ON s.id = u.staff_id "
            "WHERE u.username = ?",
            (username,),
        ).fetchone()

    return {
        "staff_id": row["staff_id"] if row else None,
        "staff_name": row["staff_name"] if row else None,
    }


@router.put("/me/staff-binding")
def update_staff_binding(
    request: Request,
    body: StaffBindingUpdate,
    _admin: str = Depends(RequireRole("admin")),
):
    """Link or unlink a staff record to the current user account."""
    staff_id = body.staff_id

    username = getattr(request.state, "auth_username", "")
    with get_db() as conn:
        row = conn.execute(
            "SELECT u.staff_id, s.name AS staff_name "
            "FROM users u "
            "LEFT JOIN staff s ON s.id = u.staff_id "
            "WHERE u.username = ?",
            (username,),
        ).fetchone()

        if not row:
            raise HTTPException(status_code=404, detail="User not found")

        old_value = {"staff_id": row["staff_id"], "staff_name": row["staff_name"]}

        if staff_id is not None:
            staff_row = conn.execute(
                "SELECT id, name FROM staff WHERE id = ? AND active = 1",
                (staff_id,),
            ).fetchone()
            if not staff_row:
                raise HTTPException(
                    status_code=404,
                    detail=f"Staff with id={staff_id} not found or inactive",
                )

            # Pre-check: if this staff member is already bound to another user, return 409
            conflict = conn.execute(
                "SELECT username FROM users "
                "WHERE staff_id = ? AND username != ?",
                (staff_id, username),
            ).fetchone()
            if conflict:
                raise HTTPException(
                    status_code=409,
                    detail=(
                        f"Nhân viên này đã được gắn với tài khoản "
                        f"'{conflict['username']}'"
                    ),
                )

            new_name = staff_row["name"]
        else:
            new_name = None

        try:
            conn.execute(
                "UPDATE users SET staff_id = ? WHERE username = ?",
                (staff_id, username),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(
                status_code=409,
                detail="Nhân viên này đã được gắn với tài khoản khác",
            )

        record_audit_log(
            conn,
            username=_admin,
            action="update",
            entity_type="users.staff_id",
            entity_id=username,
            old_value=old_value,
            new_value={"staff_id": staff_id, "staff_name": new_name},
        )

    return {
        "staff_id": staff_id,
        "staff_name": new_name,
    }
