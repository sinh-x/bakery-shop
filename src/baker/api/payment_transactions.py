"""Payment transaction API routes."""

import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.models.payment_transaction import PaymentMethod, PaymentTransaction, TransactionType

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
        try:
            from baker.services.journal_sync import _sync_payment_journal
            _sync_payment_journal(
                conn, txn.id, body.amount, body.type, body.method,
                order_id=order_id,
            )
        except Exception:
            logger.exception("payment journal sync failed for txn %d", txn.id)

        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn.id,)
        ).fetchone()
        return PaymentTransaction.from_row(row).to_api_dict()


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
        try:
            from baker.services.journal_sync import _sync_payment_journal
            _sync_payment_journal(
                conn, txn.id, txn.amount, txn.type, txn.method,
                order_id=order_id,
            )
        except Exception:
            logger.exception("payment journal re-sync failed for txn %d", txn.id)

        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn.id,)
        ).fetchone()
        return PaymentTransaction.from_row(row).to_api_dict()


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
        # subsequent re-syncs (DG-191 Phase 2).
        try:
            from baker.services.journal_sync import _sync_payment_journal
            _sync_payment_journal(
                conn, txn_id, float(row["amount"]), row["type"], row["method"],
                order_id=order_id, deleted=True,
            )
        except Exception:
            logger.exception("payment journal delete-sync failed for txn %d", txn_id)
