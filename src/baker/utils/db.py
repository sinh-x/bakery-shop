"""Shared SQLite helpers extracted from duplicated copies across the codebase.

Centralizes the identical ``_escape_like`` and ``_row_to_dict`` helpers that
were previously copy-pasted into 6 modules each. Specialized variants (e.g.
``api/knowledge.py`` and ``api/events.py`` ``_row_to_dict`` that post-process
columns) are intentionally left in place — only the trivial ``dict(row)``
copies were promoted here.

Traceability: FR-PY-4 (DG-308 Phase 1).
"""

from __future__ import annotations

_BS = "\\"


def escape_like(value: str) -> str:
    """Escape ``%`` and ``_`` for use in a SQLite ``LIKE`` literal.

    Replaces the duplicated ``_escape_like`` helpers in ``commands.product``,
    ``commands.server_log``, ``db.queries``, ``api.knowledge``,
    ``api.customers`` and ``api.products``.
    """
    return value.replace("%", _BS + "%").replace("_", _BS + "_")


def row_to_dict(row) -> dict:
    """Convert a ``sqlite3.Row`` (or any mapping supporting ``dict()``) to a dict.

    Replaces the trivial duplicated ``_row_to_dict`` helpers that simply
    ``return dict(row)`` (in ``api.staff``, ``api.catalog``, ``api.order_photos``,
    ``api.audit_log``, ``api.categories``, ``api.products``). Specialized
    variants that post-process columns are left in their owning modules.
    """
    return dict(row)