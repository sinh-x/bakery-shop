"""User settings API routes — staff-user binding for admin users."""

from fastapi import APIRouter, Depends, HTTPException, Request

from baker.api.auth import RequireRole, record_audit_log
from baker.db.connection import get_db

router = APIRouter(prefix="/api/users", tags=["users"])


class StaffBindingResponse:
    def __init__(self, staff_id: int | None, staff_name: str | None):
        self.staff_id = staff_id
        self.staff_name = staff_name


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
    body: dict,
    _admin: str = Depends(RequireRole("admin")),
):
    """Link or unlink a staff record to the current user account."""
    staff_id = body.get("staff_id")

    if staff_id is not None and not isinstance(staff_id, int):
        raise HTTPException(status_code=400, detail="staff_id must be an integer or null")

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
            new_name = staff_row["name"]
        else:
            new_name = None

        conn.execute(
            "UPDATE users SET staff_id = ? WHERE username = ?",
            (staff_id, username),
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
