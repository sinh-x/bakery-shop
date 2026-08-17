"""Message templates API routes (DG-375 Phase 4.1).

Provides CRUD endpoints for order message templates used by staff to
generate pre-written customer communication. Templates are grouped by
scenario and may be system-wide (``is_system = true``, admin-managed) or
personal (``is_system = false``, owned by a staff member).

Endpoints:
  - GET    /api/templates            — list templates (system + caller's personal)
  - POST   /api/templates            — create a template (admin→system, staff→personal)
  - PATCH  /api/templates/{id}       — update a template (scoped by ownership/role)
  - DELETE /api/templates/{id}       — delete a template (scoped by ownership/role)

Traceability: FR1 (list grouped by scenario), FR4 (raw body storage),
FR6 (admin CRUD for system templates), FR7 (staff CRUD for personal
templates), FR10 (management API accessible).
"""

from typing import Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from baker.api.auth import record_audit_log, resolve_staff_record
from baker.db.connection import get_db
from baker.utils.time import now_utc


router = APIRouter(prefix="/api/templates", tags=["templates"])


# Allowed scenario slugs (FR9). Template ``scenario`` must be one of these.
_ALLOWED_SCENARIOS = {
    "ask_info",
    "confirm_order",
    "final_message",
    "follow_up",
    "status_update",
    "payment_request",
}


# Allowlist of column names that may appear in the dynamic SET clause built
# by ``update_template`` (SEC-SetClause, review cycle 1). Any other key in
# the ``fields`` dict would be concatenated into raw SQL and must be rejected.
ALLOWED_UPDATE_FIELDS = {
    "scenario",
    "name",
    "body",
    "is_system",
    "sort_order",
    "active",
    "updated_at",
}


# ── Pydantic models ──────────────────────────────────────────────────────────


class TemplateCreate(BaseModel):
    scenario: str
    name: str
    body: str
    is_system: bool = False
    sort_order: int = 0
    active: bool = True


class TemplateUpdate(BaseModel):
    scenario: Optional[str] = None
    name: Optional[str] = None
    body: Optional[str] = None
    is_system: Optional[bool] = None
    sort_order: Optional[int] = None
    active: Optional[bool] = None


# ── Helpers ──────────────────────────────────────────────────────────────────


def _template_row(row) -> dict:
    return {
        "id": row["id"],
        "scenario": row["scenario"],
        "name": row["name"],
        "body": row["body"],
        "is_system": bool(row["is_system"]),
        "created_by_staff_id": row["created_by_staff_id"],
        "sort_order": row["sort_order"],
        "active": bool(row["active"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def _resolve_staff_id_or_403(request: Request) -> int:
    """Resolve the authenticated staff id, 403 if no staff link exists."""
    staff = resolve_staff_record(request)
    if staff is None:
        raise HTTPException(
            status_code=403,
            detail="Không xác định được nhân viên từ phiên đăng nhập.",
        )
    return int(staff["staff_id"])


# ── Endpoints ────────────────────────────────────────────────────────────────


@router.get("")
def list_templates(
    scenario: Optional[str] = None,
    request: Request = None,  # type: ignore[assignment]
):
    """Danh sách mẫu tin nhắn (FR1).

    Returns system templates plus the caller's personal templates. When
    ``scenario`` is provided, filters to that scenario. Templates are
    ordered by scenario, sort_order, id so the client can group them by
    scenario for the picker modal.

    NOTE (SEC-PublicEndpoint, review cycle 1): The unauthenticated fallback
    below is by design. When no auth token is present, the endpoint returns
    only the seeded system templates with placeholder metadata
    (``created_by_staff_id = NULL``); no personal templates are surfaced
    because ``staff_id`` is ``None`` and the SQL filters on
    ``created_by_staff_id = ?``. This keeps the public discovery path safe
    while letting the Flutter client bootstrap offline against the bundled
    defaults. Mutating endpoints (POST/PATCH/DELETE) require a real staff
    session and reject anonymous callers.
    """
    staff_id = None
    if request is not None:
        staff = resolve_staff_record(request)
        if staff is not None:
            staff_id = int(staff["staff_id"])

    with get_db() as conn:
        if scenario is not None:
            if scenario not in _ALLOWED_SCENARIOS:
                raise HTTPException(
                    status_code=400,
                    detail=f"scenario không hợp lệ. Giá trị hợp lệ: {sorted(_ALLOWED_SCENARIOS)}",
                )
            rows = conn.execute(
                "SELECT * FROM message_templates "
                "WHERE scenario = ? AND (is_system = 1 OR created_by_staff_id = ?) "
                "ORDER BY scenario, sort_order, id",
                (scenario, staff_id),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM message_templates "
                "WHERE is_system = 1 OR created_by_staff_id = ? "
                "ORDER BY scenario, sort_order, id",
                (staff_id,),
            ).fetchall()
        return [_template_row(r) for r in rows]


@router.post("", status_code=201)
def create_template(
    body: TemplateCreate,
    request: Request,
):
    """Tạo mẫu tin nhắn mới (FR6 / FR7).

    Admin callers may create system templates (``is_system = true``).
    Staff callers create personal templates owned by their staff id
    (``is_system = false``, ``created_by_staff_id`` = caller's staff id).
    A staff caller attempting to create a system template gets 403.
    """
    if body.scenario not in _ALLOWED_SCENARIOS:
        raise HTTPException(
            status_code=400,
            detail=f"scenario không hợp lệ. Giá trị hợp lệ: {sorted(_ALLOWED_SCENARIOS)}",
        )

    role = getattr(request.state, "auth_role", None)
    username = getattr(request.state, "auth_username", "") or ""

    # FR7: staff create personal templates scoped to their staff id.
    if body.is_system:
        # FR6: only admin may create system templates.
        # RequireRole("admin") is not used as a dependency here because the
        # same endpoint serves both admin and staff; instead the role is
        # checked inline. Under grace period (no token), reject system
        # template creation to avoid unowned system templates.
        if role != "admin":
            raise HTTPException(
                status_code=403,
                detail="Bạn không có quyền thực hiện thao tác này.",
            )
        created_by_staff_id = None
    else:
        # Personal template: resolve the caller's staff id.
        created_by_staff_id = _resolve_staff_id_or_403(request)

    with get_db() as conn:
        cursor = conn.execute(
            "INSERT INTO message_templates "
            "(scenario, name, body, is_system, created_by_staff_id, sort_order, active, created_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                body.scenario,
                body.name,
                body.body,
                1 if body.is_system else 0,
                created_by_staff_id,
                body.sort_order,
                1 if body.active else 0,
                now_utc(),
                now_utc(),
            ),
        )
        new_id = cursor.lastrowid
        record_audit_log(
            conn,
            username,
            "create",
            "message_template",
            new_id,
            old_value=None,
            new_value={
                "scenario": body.scenario,
                "name": body.name,
                "is_system": body.is_system,
                "sort_order": body.sort_order,
            },
        )
        row = conn.execute(
            "SELECT * FROM message_templates WHERE id = ?", (new_id,)
        ).fetchone()
        return _template_row(row)


@router.patch("/{template_id}")
def update_template(
    template_id: int,
    body: TemplateUpdate,
    request: Request,
):
    """Cập nhật mẫu tin nhắn (FR6 / FR7).

    Admin may update any template. Staff may update only their own
    personal templates (``is_system = 0 AND created_by_staff_id =
    <their staff id>``). System templates are admin-only.
    """
    if body.scenario is not None and body.scenario not in _ALLOWED_SCENARIOS:
        raise HTTPException(
            status_code=400,
            detail=f"scenario không hợp lệ. Giá trị hợp lệ: {sorted(_ALLOWED_SCENARIOS)}",
        )

    role = getattr(request.state, "auth_role", None)
    username = getattr(request.state, "auth_username", "") or ""

    with get_db() as conn:
        existing = conn.execute(
            "SELECT * FROM message_templates WHERE id = ?", (template_id,)
        ).fetchone()
        if not existing:
            raise HTTPException(
                status_code=404, detail="Không tìm thấy mẫu tin nhắn"
            )

        # Authorization: admin may edit any; staff may edit only own personal.
        if role != "admin":
            if bool(existing["is_system"]):
                raise HTTPException(
                    status_code=403,
                    detail="Bạn không có quyền thực hiện thao tác này.",
                )
            staff = resolve_staff_record(request)
            if staff is None or int(staff["staff_id"]) != int(existing["created_by_staff_id"]):
                raise HTTPException(
                    status_code=403,
                    detail="Bạn không có quyền thực hiện thao tác này.",
                )

        # FR6: staff cannot promote a personal template to system.
        if body.is_system and role != "admin":
            raise HTTPException(
                status_code=403,
                detail="Bạn không có quyền thực hiện thao tác này.",
            )

        old_snapshot = _template_row(existing)
        fields = {}
        if body.scenario is not None:
            fields["scenario"] = body.scenario
        if body.name is not None:
            fields["name"] = body.name
        if body.body is not None:
            fields["body"] = body.body
        if body.is_system is not None:
            fields["is_system"] = 1 if body.is_system else 0
        if body.sort_order is not None:
            fields["sort_order"] = body.sort_order
        if body.active is not None:
            fields["active"] = 1 if body.active else 0

        if fields:
            fields["updated_at"] = now_utc()
            # SEC-SetClause (review cycle 1): guard the dynamic SET clause.
            # Column names are concatenated into raw SQL, so reject any key
            # not in the allowlist before constructing the statement.
            unknown = set(fields) - ALLOWED_UPDATE_FIELDS
            if unknown:
                raise ValueError(
                    "Unknown update fields: "
                    f"{sorted(unknown)}. Allowed: {sorted(ALLOWED_UPDATE_FIELDS)}"
                )
            set_clause = ", ".join(f"{k} = ?" for k in fields)
            values = list(fields.values()) + [template_id]
            conn.execute(
                f"UPDATE message_templates SET {set_clause} WHERE id = ?",  # nosec B608
                values,
            )
            record_audit_log(
                conn,
                username,
                "update",
                "message_template",
                template_id,
                old_value=old_snapshot,
                new_value=fields,
            )

        row = conn.execute(
            "SELECT * FROM message_templates WHERE id = ?", (template_id,)
        ).fetchone()
        return _template_row(row)


@router.delete("/{template_id}", status_code=204)
def delete_template(
    template_id: int,
    request: Request,
):
    """Xóa mẫu tin nhắn (FR6 / FR7).

    Admin may delete any template. Staff may delete only their own
    personal templates. System templates are admin-only.
    """
    role = getattr(request.state, "auth_role", None)
    username = getattr(request.state, "auth_username", "") or ""

    with get_db() as conn:
        existing = conn.execute(
            "SELECT * FROM message_templates WHERE id = ?", (template_id,)
        ).fetchone()
        if not existing:
            raise HTTPException(
                status_code=404, detail="Không tìm thấy mẫu tin nhắn"
            )

        if role != "admin":
            if bool(existing["is_system"]):
                raise HTTPException(
                    status_code=403,
                    detail="Bạn không có quyền thực hiện thao tác này.",
                )
            staff = resolve_staff_record(request)
            if staff is None or int(staff["staff_id"]) != int(existing["created_by_staff_id"]):
                raise HTTPException(
                    status_code=403,
                    detail="Bạn không có quyền thực hiện thao tác này.",
                )

        conn.execute(
            "DELETE FROM message_templates WHERE id = ?", (template_id,)
        )
        record_audit_log(
            conn,
            username,
            "delete",
            "message_template",
            template_id,
            old_value=_template_row(existing),
            new_value=None,
        )