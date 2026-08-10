"""MessageTemplate dataclass model (DG-375 Phase 4.1).

Represents a row in the ``message_templates`` table. Templates are either
system-wide (``is_system = True``, managed by admin) or personal
(``is_system = False``, owned by a specific staff member via
``created_by_staff_id``). Template bodies contain placeholder syntax
(e.g. ``{customer_name}``, ``{order_code}``) that is resolved client-side;
the backend stores the raw body verbatim (FR4).
"""

from dataclasses import dataclass
from typing import Optional


@dataclass
class MessageTemplate:
    id: Optional[int]
    scenario: str
    name: str
    body: str
    is_system: bool = False
    created_by_staff_id: Optional[int] = None
    sort_order: int = 0
    active: bool = True
    created_at: Optional[str] = None
    updated_at: Optional[str] = None

    @staticmethod
    def from_row(row) -> "MessageTemplate":
        return MessageTemplate(
            id=row["id"],
            scenario=row["scenario"],
            name=row["name"],
            body=row["body"],
            is_system=bool(row["is_system"]),
            created_by_staff_id=row["created_by_staff_id"],
            sort_order=row["sort_order"],
            active=bool(row["active"]),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )