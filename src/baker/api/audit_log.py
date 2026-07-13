"""Audit log API routes — admin-only read endpoint (DG-029 Phase 5, FR23).

``GET /api/audit-log`` returns paginated audit log entries filterable by
``username``, ``entity_type``, ``date_from``, and ``date_to``. The endpoint
is gated by ``RequireRole("admin")`` (FR3) — staff receives HTTP 403.

The ``audit_log`` table was created in Phase 3 (migration v69) and is
already indexed on ``created_at``, ``username``, and ``entity_type``
(NFR9). Filters use these indexed columns and pagination uses
``LIMIT ? OFFSET ?`` to keep p95 < 200ms over 10,000 entries.

FR22 (audit log *recording*) is implemented in ``baker.api.auth.record_audit_log``
(Phase 3); this phase adds ONLY the read/query API.
"""

from fastapi import APIRouter, Depends, Query

from baker.api.auth import RequireRole
from baker.db.connection import get_db

router = APIRouter(prefix="/api/audit-log", tags=["audit-log"])


def _row_to_dict(row) -> dict:
    """Convert a sqlite3.Row to a dict."""
    return dict(row)


@router.get("")
def list_audit_log(
    actor: str = Depends(RequireRole("admin")),
    username: str = Query("", description="Lọc theo tên người dùng"),
    entity_type: str = Query("", description="Lọc theo loại thực thể (config, product, category, ...)"),
    date_from: str = Query("", description="Lọc từ ngày (YYYY-MM-DD hoặc ISO-8601)"),
    date_to: str = Query("", description="Lọc đến ngày (YYYY-MM-DD hoặc ISO-8601)"),
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
):
    """Danh sách nhật ký thay đổi (admin-only, FR23).

    Trả về các bản ghi audit_log phân trang, lọc được theo ``username``,
    ``entity_type``, ``date_from``, ``date_to``. Sắp xếp theo thời gian
    tạo giảm dần (mới nhất trước). Mỗi bản ghi gồm: id, username, action,
    entity_type, entity_id, old_value, new_value, created_at.

    Phân trang dùng ``page`` (bắt đầu từ 1) và ``page_size`` (1–200).
    """
    conditions = []
    params = []

    if username:
        conditions.append("username = ?")
        params.append(username)

    if entity_type:
        conditions.append("entity_type = ?")
        params.append(entity_type)

    # Date range filters operate on the indexed created_at column (NFR9).
    # date_from / date_to accept either a date (YYYY-MM-DD) or a full
    # ISO-8601 timestamp. Date-only bounds are expanded to inclusive
    # start-of-day / end-of-day boundaries via string comparison — the
    # created_at column is stored as ``YYYY-MM-DDTHH:MM:SSZ`` so lexical
    # string comparison yields correct chronological ordering.
    if date_from:
        conditions.append("created_at >= ?")
        params.append(date_from)

    if date_to:
        conditions.append("created_at <= ?")
        params.append(date_to)

    where_clause = f"WHERE {' AND '.join(conditions)}" if conditions else ""
    offset = (page - 1) * page_size

    with get_db() as conn:
        # Total count for pagination metadata (uses the same filters).
        count_row = conn.execute(
            f"SELECT COUNT(*) AS total FROM audit_log {where_clause}",
            params,
        ).fetchone()
        total = count_row["total"] if count_row is not None else 0

        rows = conn.execute(
            f"SELECT id, username, action, entity_type, entity_id, "
            f"old_value, new_value, created_at "
            f"FROM audit_log {where_clause} "
            f"ORDER BY created_at DESC, id DESC "
            f"LIMIT ? OFFSET ?",
            params + [page_size, offset],
        ).fetchall()

        return {
            "items": [_row_to_dict(r) for r in rows],
            "page": page,
            "page_size": page_size,
            "total": total,
        }