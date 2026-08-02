"""Payment transaction API routes."""

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from baker.api.auth import resolve_actor
from baker.db.connection import get_db
from baker.models.cash_drawer import CashDrawer
from baker.models.payment_transaction import PaymentMethod, PaymentTransaction, TransactionType
from baker.utils.time import now_utc

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/orders", tags=["payment-transactions"])


# NFR3: ``payment_source`` accepts absent, null, or empty string. Using
# ``Optional[str]`` (default ``""``) lets the API tolerate ``null`` payloads
# from clients that distinguish "unset" from "empty"; both normalize to "".
class TransactionCreate(BaseModel):
    amount: float
    type: str = "deposit"
    method: str = "cash"
    note: str = ""
    payment_source: Optional[str] = ""


class TransactionUpdate(BaseModel):
    amount: float | None = None
    type: str | None = None
    method: str | None = None
    note: str | None = None
    payment_source: Optional[str] = None


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
            payment_source=body.payment_source or "",
        )
        # FR5 (DG-324 Phase 3): cash payments auto-link to the active day's
        # drawer via cash_drawer_id and accumulate into the drawer's cash_sales
        # total. Only cash payments link — bank transfers and card payments do
        # not touch the physical drawer. When no active drawer exists, the
        # link is skipped (NULL cash_drawer_id — journal sync unchanged).
        drawer_id = None
        if body.method == PaymentMethod.CASH.value:
            active = CashDrawer.get_active(conn)
            if active is not None:
                drawer_id = active.id
        txn.save(conn)
        if drawer_id is not None:
            conn.execute(
                "UPDATE payment_transactions SET cash_drawer_id = ? WHERE id = ?",
                (drawer_id, txn.id),
            )
            # Outflow types (refund) return cash to the customer, reducing the
            # drawer's cash; inflows (deposit/payment/full_payment/tien_rut)
            # add cash. tien_rut is a deposit held in 2400, not revenue, but it
            # is still physical cash handed to the shop and counts in the drawer.
            from baker.db.schema import PAYMENT_OUTFLOW_TYPES
            delta = -abs(body.amount) if body.type in PAYMENT_OUTFLOW_TYPES else abs(body.amount)
            active = CashDrawer.get_by_id(conn, drawer_id)
            if active is not None:
                active.add_cash_sale(conn, delta)

        # Auto-generate double-entry journal entry (DG-175).
        # Bus orders split the credit between Customer Deposits (2100) and
        # Bus Shipping Held (2200) — pass order_id so the journal sync reads
        # delivery_type/shipping_fee from the orders table (DG-191 Phase 2).
        # DG-244 Phase 4: payment_source routes the asset side to a distinct
        # bank sub-account (1210/1220) or the un-allocated fallback (1290).
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn.id, body.amount, body.type, body.method,
            order_id=order_id,
            payment_source=body.payment_source or "",
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
        old_method = str(row["method"])
        old_amount = float(row["amount"])
        old_type = str(row["type"])
        old_drawer_id = row["cash_drawer_id"] if "cash_drawer_id" in row.keys() else None

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
        if body.payment_source is not None:
            txn.payment_source = body.payment_source or ""

        conn.execute(
            "UPDATE payment_transactions SET amount = ?, type = ?, method = ?, note = ?, payment_source = ? WHERE id = ?",
            (txn.amount, txn.type, txn.method, txn.note, txn.payment_source, txn.id),
        )

        # FR5 (DG-324 Phase 3): reconcile the cash_drawer link + cash_sales
        # aggregate when method/amount/type changes. First reverse the prior
        # contribution from the previously-linked drawer (if any), then
        # re-link to the active drawer when the new method is cash.
        from baker.db.schema import PAYMENT_OUTFLOW_TYPES
        if old_drawer_id is not None:
            old_delta = -abs(old_amount) if old_type in PAYMENT_OUTFLOW_TYPES else abs(old_amount)
            prev_drawer = CashDrawer.get_by_id(conn, int(old_drawer_id))
            if prev_drawer is not None:
                prev_drawer.add_cash_sale(conn, -old_delta)
            conn.execute(
                "UPDATE payment_transactions SET cash_drawer_id = NULL WHERE id = ?",
                (txn.id,),
            )
        new_drawer_id = None
        if txn.method == PaymentMethod.CASH.value:
            active = CashDrawer.get_active(conn)
            if active is not None:
                new_drawer_id = active.id
        if new_drawer_id is not None:
            conn.execute(
                "UPDATE payment_transactions SET cash_drawer_id = ? WHERE id = ?",
                (new_drawer_id, txn.id),
            )
            new_delta = -abs(txn.amount) if txn.type in PAYMENT_OUTFLOW_TYPES else abs(txn.amount)
            active = CashDrawer.get_by_id(conn, new_drawer_id)
            if active is not None:
                active.add_cash_sale(conn, new_delta)

        # Re-sync double-entry journal entry (DG-175). Pass order_id so the
        # bus-shipping split is recomputed from the current delivery_type /
        # shipping_fee (DG-191 Phase 2). DG-244 Phase 4: payment_source
        # re-routes the asset side; an update on payment_source re-syncs the
        # journal entry to the correct bank sub-account.
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn.id, txn.amount, txn.type, txn.method,
            order_id=order_id,
            payment_source=txn.payment_source or "",
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
            "SELECT id, amount, type, method, payment_source, cash_drawer_id FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")
        payment_source = row["payment_source"] if "payment_source" in row.keys() else ""

        # FR5 (DG-324 Phase 3): reverse the cash_sales contribution from the
        # linked drawer before deleting the transaction row.
        old_drawer_id = row["cash_drawer_id"] if "cash_drawer_id" in row.keys() else None
        if old_drawer_id is not None:
            from baker.db.schema import PAYMENT_OUTFLOW_TYPES
            old_delta = -abs(float(row["amount"])) if row["type"] in PAYMENT_OUTFLOW_TYPES else abs(float(row["amount"]))
            prev_drawer = CashDrawer.get_by_id(conn, int(old_drawer_id))
            if prev_drawer is not None:
                prev_drawer.add_cash_sale(conn, -old_delta)

        conn.execute("DELETE FROM payment_transactions WHERE id = ?", (txn_id,))

        # Reverse/delete the journal entry for the deleted transaction (DG-175).
        # Pass order_id so any bus-shipping held balance is consistent on
        # subsequent re-syncs (DG-191 Phase 2). No response body (204) — the
        # failure counter is surfaced via /api/health (OPS-1).
        # DG-244 Phase 4: payment_source is passed for API symmetry; the
        # deleted=True path reverses/deletes the existing entry directly
        # without re-resolving asset codes, so it is informational here.
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync
        run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id, deleted=True,
            payment_source=payment_source or "",
            log_label=f"payment journal delete-sync for txn {txn_id}",
            source_type="payment_transaction",
            source_id=txn_id,
        )


def _now_iso() -> str:
    """Return the current UTC timestamp as an ISO-8601 string with Z suffix.

    All timestamps are UTC ``Z``-suffixed (DG-202 FR1) via
    :func:`baker.utils.time.now_utc`.
    """
    return now_utc()


@router.post("/{ref}/transactions/{txn_id}/invalidate")
def invalidate_transaction(ref: str, txn_id: int, body: InvalidationRequest, request: Request):
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
        invalidated_by = resolve_actor(request, body.invalidatedBy)
        conn.execute(
            "UPDATE payment_transactions "
            "SET invalidated_at = ?, invalidated_by = ? WHERE id = ?",
            (invalidated_at, invalidated_by, txn_id),
        )

        # FR5 (DG-324 Phase 3): an invalidated transaction must no longer
        # contribute to the drawer's cash_sales. Reverse the contribution
        # from the linked drawer (the cash_drawer_id link is preserved for
        # audit traceability).
        drawer_id = row["cash_drawer_id"] if "cash_drawer_id" in row.keys() else None
        if drawer_id is not None:
            from baker.db.schema import PAYMENT_OUTFLOW_TYPES
            delta = -abs(float(row["amount"])) if row["type"] in PAYMENT_OUTFLOW_TYPES else abs(float(row["amount"]))
            linked = CashDrawer.get_by_id(conn, int(drawer_id))
            if linked is not None:
                linked.add_cash_sale(conn, -delta)

        # FR3/NFR2: journal sync is fire-and-forget. _sync_payment_journal
        # (deleted=True) reverses locked entries (preserving the original
        # transaction_date) and deletes unlocked ones.
        # DG-244 Phase 4: payment_source passed for symmetry (informational
        # on the deleted=True path which reverses/deletes the existing entry).
        payment_source = row["payment_source"] if "payment_source" in row.keys() else ""
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id, deleted=True,
            payment_source=payment_source or "",
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

        # FR5 (DG-324 Phase 3): restoring a transaction re-applies its
        # contribution to the linked drawer's cash_sales (only if the drawer
        # is still open — a closed drawer's totals are frozen at close time).
        drawer_id = row["cash_drawer_id"] if "cash_drawer_id" in row.keys() else None
        if drawer_id is not None:
            from baker.db.schema import PAYMENT_OUTFLOW_TYPES
            delta = -abs(float(row["amount"])) if row["type"] in PAYMENT_OUTFLOW_TYPES else abs(float(row["amount"]))
            linked = CashDrawer.get_by_id(conn, int(drawer_id))
            if linked is not None and linked.status == "open":
                linked.add_cash_sale(conn, delta)

        # FR4/NFR2: journal sync is fire-and-forget. The create path reads the
        # transaction's created_at for transaction_date. If a prior reversal
        # entry exists (locked case), a new entry is created alongside it; the
        # reversal is left intact so the locked period's books are preserved.
        # DG-244 Phase 4: payment_source routes the asset side on restore.
        payment_source = row["payment_source"] if "payment_source" in row.keys() else ""
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id,
            payment_source=payment_source or "",
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
