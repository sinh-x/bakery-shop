"""Common journal sync infrastructure (DG-308 Phase 4.4, FR-ARCH-2).

Shared helpers extracted from the original monolithic ``journal_sync.py``:
the non-blocking runner (``run_journal_sync``), the failure counter/log, the
generic journal-entry CRUD helpers (find / lock-check / delete / reverse /
update-in-place), and the delivered-timestamp resolver shared by the order and
waste/COGS modules. Domain-specific sync logic lives in the sibling modules
``expense.py``, ``payment.py``, ``order.py``, ``waste.py``.
"""

import logging
import traceback
from typing import Any, Callable, Optional

from baker.db.schema import (
    REVENUE_UPDATE_TOLERANCE,
    _insert_journal_entry,
)
from baker.models.cash_drawer import CashDrawer
from baker.models.journal_entry import JournalEntry, JournalLine

logger = logging.getLogger("baker.server")

STAFF_ADVANCE_PAYMENT_SOURCE = "Nhân viên ứng trước"

journal_sync_failures: int = 0


def _active_drawer_id(conn) -> int | None:
    """Return the active cash drawer ID, or None if no drawer is open.

    DG-347 Phase 2 (FR4): journal entries touching 1101 must be linked to the
    active drawer so expected_balance() can filter per-drawer.
    """
    drawer = CashDrawer.get_active(conn)
    return drawer.id if drawer else None

# Backwards-compatible alias kept so any external import of the legacy name
# continues to resolve to the centralized constant in ``baker.db.schema``.
_REVENUE_UPDATE_TOLERANCE = REVENUE_UPDATE_TOLERANCE

# Auto-truncation limit for journal_sync_failure_log (NFR4, DG-226).
_JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS = 10000


def run_journal_sync(
    sync_fn: Callable[..., None],
    *args: Any,
    log_label: str,
    source_type: Optional[str] = None,
    source_id: Optional[int] = None,
    **kwargs: Any,
) -> str:
    """Run a journal sync callable with non-blocking error handling + observability.

    Wraps the fire-and-forget pattern used by every API endpoint that triggers
    an accounting journal sync (NFR1: accounting failures must never block the
    primary business operation). On failure the exception is logged via
    ``logger.exception`` and the :data:`journal_sync_failures` counter is
    incremented, so the gap is observable through ``/api/health``.

    When ``source_type`` and ``source_id`` are both provided, the failure is
    also recorded in the ``journal_sync_failure_log`` audit table (DG-226) so
    the failure is traceable to a specific source.

    Returns ``"ok"`` when the sync succeeded, or ``"failed"`` when it raised.
    Callers may attach this to their API response (e.g. an
    ``accounting_sync`` field) so the Flutter client can surface a warning.
    """
    global journal_sync_failures
    try:
        sync_fn(*args, **kwargs)
    except Exception as exc:
        journal_sync_failures += 1
        logger.exception("%s failed", log_label)
        if source_type is not None and source_id is not None and args:
            conn = args[0]
            try:
                _log_journal_sync_failure(
                    conn,
                    source_type,
                    source_id,
                    str(exc),
                    traceback.format_exc(),
                )
            except Exception:
                pass  # NFR2: must never cascade into business operation failure
        return "failed"
    return "ok"

def sync_status_to_warning(status: str) -> str:
    return "ok" if status == "ok" else "journal_sync_failed"

def _log_journal_sync_failure(
    conn,
    source_type: str,
    source_id: int,
    error_message: str,
    stack_trace_str: str,
) -> None:
    """Record a journal sync failure in the audit log (NFR2: never throws)."""
    try:
        conn.execute(
            "INSERT INTO journal_sync_failure_log "
            "(source_type, source_id, error_message, stack_trace) "
            "VALUES (?, ?, ?, ?)",
            (source_type, source_id, error_message, stack_trace_str),
        )
        # NFR4: auto-truncate to last 10,000 rows, oldest-first.
        row_count = conn.execute(
            "SELECT COUNT(*) FROM journal_sync_failure_log"
        ).fetchone()[0]
        if row_count > _JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS:
            conn.execute(
                "DELETE FROM journal_sync_failure_log WHERE id NOT IN ("
                "SELECT id FROM journal_sync_failure_log ORDER BY id DESC "
                "LIMIT ?)",
                (_JOURNAL_SYNC_FAILURE_LOG_MAX_ROWS,),
            )
    except Exception:
        pass  # NFR2: log write failure must not cascade into business operation failure

def _find_journal_entry(conn, source_type: str, source_id: int) -> Optional[int]:
    """Return the journal_entries.id for the given source, or None."""
    row = conn.execute(
        "SELECT id, locked_at FROM journal_entries "
        "WHERE source_type = ? AND source_id = ? ORDER BY id DESC LIMIT 1",
        (source_type, source_id),
    ).fetchone()
    if row is None:
        return None
    return int(row["id"])

def _is_locked(conn, entry_id: int) -> bool:
    row = conn.execute(
        "SELECT locked_at FROM journal_entries WHERE id = ?", (entry_id,)
    ).fetchone()
    return bool(row and row["locked_at"])

def _delete_journal_entry_cascade(conn, entry_id: int) -> None:
    """Delete a journal entry and its lines (CASCADE handled by DB, but be explicit)."""
    conn.execute("DELETE FROM journal_lines WHERE journal_entry_id = ?", (entry_id,))
    conn.execute("DELETE FROM cash_drawer_journal_entries WHERE journal_entry_id = ?", (entry_id,))
    conn.execute("DELETE FROM journal_entries WHERE id = ?", (entry_id,))

def _reverse_journal_entry(conn, entry_id: int) -> Optional[int]:
    """Create a reversal entry that swaps debit/credit of the original entry.

    Returns the new reversal entry id, or None if the original has no lines.
    """
    orig = conn.execute(
        "SELECT description, source_type, source_id, transaction_date "
        "FROM journal_entries WHERE id = ?",
        (entry_id,),
    ).fetchone()
    if orig is None:
        return None
    lines = JournalLine.list_for_entry(conn, entry_id)
    if not lines:
        return None
    reversed_lines = [
        (line.account_id, float(line.credit), float(line.debit), line.description or "")
        for line in lines
    ]
    # FR12: the reversal preserves the original entry's transaction_date so
    # the correction relates to the same period as the entry being reversed.
    orig_transaction_date = orig["transaction_date"] if "transaction_date" in orig.keys() else None
    return _insert_journal_entry(
        conn,
        description=f"Reversal: {orig['description']}",
        source_type=orig["source_type"],
        source_id=orig["source_id"],
        lines=reversed_lines,
        transaction_date=orig_transaction_date,
    )

def _update_journal_entry_in_place(
    conn, entry_id: int, *, description: str, lines: list[tuple[int, float, float, str]]
) -> None:
    """Replace the lines of an unlocked journal entry with the given lines."""
    conn.execute("DELETE FROM journal_lines WHERE journal_entry_id = ?", (entry_id,))
    for account_id, debit, credit, line_desc in lines:
        conn.execute(
            "INSERT INTO journal_lines "
            "(journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, ?, ?, ?)",
            (entry_id, account_id, float(debit), float(credit), line_desc),
        )
    conn.execute(
        "UPDATE journal_entries SET description = ? WHERE id = ?",
        (description, entry_id),
    )

def _resolve_delivered_timestamp(conn, order_id: int, order_ref: str) -> str | None:
    """Return the first delivered/completed event timestamp for an order.

    Preference order (FR6):
      1. events.order_id when populated
      2. exact ``"order_ref": "<ref>"`` JSON match in data column
      3. Returns None when no event exists → caller falls back to ``now_utc()``
    """
    row = conn.execute(
        """
        SELECT MIN(timestamp) AS ts FROM events
        WHERE order_id = ?
          AND type = 'order'
          AND json_extract(data, '$.to_status') IN ('delivered', 'completed')
        """,
        (order_id,),
    ).fetchone()
    if row and row["ts"]:
        return row["ts"]
    row = conn.execute(
        """
        SELECT MIN(timestamp) AS ts FROM events
        WHERE json_extract(data, '$.order_ref') = ?
          AND type = 'order'
          AND json_extract(data, '$.to_status') IN ('delivered', 'completed')
        """,
        (order_ref,),
    ).fetchone()
    if row and row["ts"]:
        return row["ts"]
    return None
