"""Payment transaction API routes."""

import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.models.payment_transaction import PaymentMethod, PaymentTransaction, TransactionType
from baker.utils.time import now_utc

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/orders", tags=["payment-transactions"])


class TransactionCreate(BaseModel):
    amount: float
    type: str = "deposit"
    method: str = "cash"
    note: str = ""


class TransactionUpdate(BaseModel):
    amount: float | None = None
    type: str | None = None
    method: str | None = None
    note: str | None = None


class InvalidationRequest(BaseModel):
    invalidatedBy: str = ""
    reason: str = ""


def _resolve_order_id(conn, ref: str) -> int:
    row = conn.execute(
        "SELECT id FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
        (ref, ref),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
    return row["id"]


@router.get("/{ref}/transactions")
def list_transactions(ref: str):
    """Danh sách giao dịch thanh toán của đơn hàng."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        rows = conn.execute(
            "SELECT * FROM payment_transactions WHERE order_id = ? ORDER BY id",
            (order_id,),
        ).fetchall()
        return [PaymentTransaction.from_row(r).to_api_dict() for r in rows]


@router.post("/{ref}/transactions", status_code=201)
def create_transaction(ref: str, body: TransactionCreate):
    """Tạo giao dịch thanh toán mới."""
    if body.amount <= 0:
        raise HTTPException(status_code=422, detail="Số tiền phải lớn hơn 0")

    valid_types = [t.value for t in TransactionType]
    if body.type not in valid_types:
        raise HTTPException(
            status_code=422,
            detail=f"Loại giao dịch không hợp lệ. Cho phép: {valid_types}",
        )

    valid_methods = [m.value for m in PaymentMethod]
    if body.method not in valid_methods:
        raise HTTPException(
            status_code=422,
            detail=f"Phương thức thanh toán không hợp lệ. Cho phép: {valid_methods}",
        )

    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)

        txn = PaymentTransaction(
            order_id=order_id,
            amount=body.amount,
            type=body.type,
            method=body.method,
            note=body.note,
        )
        txn.save(conn)

        # Auto-generate double-entry journal entry (DG-175).
        # Bus orders split the credit between Customer Deposits (2100) and
        # Bus Shipping Held (2200) — pass order_id so the journal sync reads
        # delivery_type/shipping_fee from the orders table (DG-191 Phase 2).
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn.id, body.amount, body.type, body.method,
            order_id=order_id,
            log_label=f"payment journal sync for txn {txn.id}",
            source_type="payment_transaction",
            source_id=txn.id,
        )

        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn.id,)
        ).fetchone()
        result = PaymentTransaction.from_row(row).to_api_dict()
        result["accountingSync"] = sync_status
        result["accountingSyncWarning"] = sync_status_to_warning(sync_status)
        return result


@router.patch("/{ref}/transactions/{txn_id}")
def update_transaction(ref: str, txn_id: int, body: TransactionUpdate):
    """Cập nhật giao dịch thanh toán."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")

        txn = PaymentTransaction.from_row(row)

        if body.amount is not None:
            if body.amount <= 0:
                raise HTTPException(status_code=422, detail="Số tiền phải lớn hơn 0")
            txn.amount = body.amount
        if body.type is not None:
            valid_types = [t.value for t in TransactionType]
            if body.type not in valid_types:
                raise HTTPException(
                    status_code=422,
                    detail=f"Loại giao dịch không hợp lệ. Cho phép: {valid_types}",
                )
            txn.type = body.type
        if body.method is not None:
            valid_methods = [m.value for m in PaymentMethod]
            if body.method not in valid_methods:
                raise HTTPException(
                    status_code=422,
                    detail=f"Phương thức thanh toán không hợp lệ. Cho phép: {valid_methods}",
                )
            txn.method = body.method
        if body.note is not None:
            txn.note = body.note

        conn.execute(
            "UPDATE payment_transactions SET amount = ?, type = ?, method = ?, note = ? WHERE id = ?",
            (txn.amount, txn.type, txn.method, txn.note, txn.id),
        )

        # Re-sync double-entry journal entry (DG-175). Pass order_id so the
        # bus-shipping split is recomputed from the current delivery_type /
        # shipping_fee (DG-191 Phase 2).
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn.id, txn.amount, txn.type, txn.method,
            order_id=order_id,
            log_label=f"payment journal re-sync for txn {txn.id}",
            source_type="payment_transaction",
            source_id=txn.id,
        )

        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn.id,)
        ).fetchone()
        result = PaymentTransaction.from_row(row).to_api_dict()
        result["accountingSync"] = sync_status
        result["accountingSyncWarning"] = sync_status_to_warning(sync_status)
        return result


@router.delete("/{ref}/transactions/{txn_id}", status_code=204)
def delete_transaction(ref: str, txn_id: int):
    """Xóa giao dịch thanh toán."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT id, amount, type, method FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")
        conn.execute("DELETE FROM payment_transactions WHERE id = ?", (txn_id,))

        # Reverse/delete the journal entry for the deleted transaction (DG-175).
        # Pass order_id so any bus-shipping held balance is consistent on
        # subsequent re-syncs (DG-191 Phase 2). No response body (204) — the
        # failure counter is surfaced via /api/health (OPS-1).
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync
        run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id, deleted=True,
            log_label=f"payment journal delete-sync for txn {txn_id}",
        )


def _now_iso() -> str:
    """Return the current UTC timestamp as an ISO-8601 string with Z suffix.

    All timestamps are UTC ``Z``-suffixed (DG-202 FR1) via
    :func:`baker.utils.time.now_utc`.
    """
    return now_utc()


@router.post("/{ref}/transactions/{txn_id}/invalidate")
def invalidate_transaction(ref: str, txn_id: int, body: InvalidationRequest):
    """Đánh dấu giao dịch là không hợp lệ (soft-delete) + đảo bút toán journal.

    FR1/FR3: Sets ``invalidated_at``/``invalidated_by`` and reverses (locked)
    or deletes (unlocked) the matching journal entry via
    ``_sync_payment_journal(deleted=True)``. The locked-reversal path preserves
    the original ``transaction_date`` (same-timestamp reversal); the unlocked
    path deletes the entry outright. FR10: logs ``action_type='invalidate'`` to
    ``order_history``.
    """
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")

        if row["invalidated_at"]:
            raise HTTPException(
                status_code=422,
                detail="Giao dịch đã được hủy trước đó",
            )

        invalidated_at = _now_iso()
        invalidated_by = body.invalidatedBy or ""
        conn.execute(
            "UPDATE payment_transactions "
            "SET invalidated_at = ?, invalidated_by = ? WHERE id = ?",
            (invalidated_at, invalidated_by, txn_id),
        )

        # FR3/NFR2: journal sync is fire-and-forget. _sync_payment_journal
        # (deleted=True) reverses locked entries (preserving the original
        # transaction_date) and deletes unlocked ones.
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id, deleted=True,
            log_label=f"payment journal invalidate-sync for txn {txn_id}",
            source_type="payment_transaction",
            source_id=txn_id,
        )

        # FR10: audit trail.
        try:
            from baker.api.orders import _log_order_history
            _log_order_history(
                conn, order_id, "invalidate", "payment_transaction",
                str(txn_id), invalidated_by, invalidated_by,
            )
        except Exception:
            logger.exception("order_history log failed for invalidate txn %d", txn_id)

        updated = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn_id,)
        ).fetchone()
        result = PaymentTransaction.from_row(updated).to_api_dict()
        result["accountingSync"] = sync_status
        result["accountingSyncWarning"] = sync_status_to_warning(sync_status)
        return result


@router.post("/{ref}/transactions/{txn_id}/restore")
def restore_transaction(ref: str, txn_id: int):
    """Khôi phục giao dịch đã hủy + tạo lại bút toán journal.

    FR2/FR4: Clears ``invalidated_at``/``invalidated_by`` and re-creates the
    journal entry via ``_sync_payment_journal`` (create path), which uses the
    transaction's ``created_at`` as ``transaction_date`` (FR4). FR10: logs
    ``action_type='restore'`` to ``order_history``.
    """
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")

        if not row["invalidated_at"]:
            raise HTTPException(
                status_code=422,
                detail="Giao dịch chưa bị hủy, không cần khôi phục",
            )

        conn.execute(
            "UPDATE payment_transactions "
            "SET invalidated_at = NULL, invalidated_by = '' WHERE id = ?",
            (txn_id,),
        )

        # FR4/NFR2: journal sync is fire-and-forget. The create path reads the
        # transaction's created_at for transaction_date. If a prior reversal
        # entry exists (locked case), a new entry is created alongside it; the
        # reversal is left intact so the locked period's books are preserved.
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id,
            log_label=f"payment journal restore-sync for txn {txn_id}",
            source_type="payment_transaction",
            source_id=txn_id,
        )

        # FR10: audit trail.
        try:
            from baker.api.orders import _log_order_history
            _log_order_history(
                conn, order_id, "restore", "payment_transaction",
                str(txn_id), "", "",
            )
        except Exception:
            logger.exception("order_history log failed for restore txn %d", txn_id)

        updated = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn_id,)
        ).fetchone()
        result = PaymentTransaction.from_row(updated).to_api_dict()
        result["accountingSync"] = sync_status
        result["accountingSyncWarning"] = sync_status_to_warning(sync_status)
        return result
