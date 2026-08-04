"""Expense categories API routes — exposes the parent/child category tree
stored in the ``expense_categories`` table (DG-302 Phase 2, FR5).

The single endpoint ``GET /api/expense-categories`` returns the full tree:
parents with their ``children`` list populated. Used by the Flutter client
to populate the category/subcategory dropdowns in the expense form
(Phase 3-4).
"""

from fastapi import APIRouter

from baker.db.connection import get_db

router = APIRouter(prefix="/api/expense-categories", tags=["expense-categories"])


@router.get("")
def list_expense_categories():
    """Trả về category tree (parent + children) để populate dropdown (FR5).

    Response shape::

        [
          {
            "id": 1,
            "name": "Nguyên liệu",
            "account_code": "5100",
            "parent_id": null,
            "children": [
              {"id": 9, "name": "Trứng", "account_code": "5110", "parent_id": 1},
              ...
            ]
          },
          ...
        ]

    Parents are returned in seed order (id ascending). Children are nested
    under their parent and also sorted by id ascending.
    """
    with get_db() as conn:
        rows = conn.execute(
            "SELECT id, name, account_code, parent_id "
            "FROM expense_categories ORDER BY id"
        ).fetchall()

    children_by_parent: dict[int, list[dict]] = {}
    parents: list[dict] = []
    for r in rows:
        entry = {
            "id": int(r["id"]),
            "name": r["name"],
            "account_code": r["account_code"],
            "parent_id": int(r["parent_id"]) if r["parent_id"] is not None else None,
        }
        if entry["parent_id"] is None:
            entry["children"] = []
            parents.append(entry)
        else:
            children_by_parent.setdefault(entry["parent_id"], []).append(entry)

    for parent in parents:
        parent["children"] = children_by_parent.get(parent["id"], [])
    return parents