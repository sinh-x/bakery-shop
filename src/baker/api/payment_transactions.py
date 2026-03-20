"""Payment transaction API routes."""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from baker.db.connection import get_db
from baker.models.payment_transaction import PaymentMethod, PaymentTransaction, TransactionType

router = APIRouter(prefix="/api/orders", tags=["payment-transactions"])


class TransactionCreate(BaseModel):
    amount: float
    type: str = "deposit"
    method: str = "cash"
    note: str = ""


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
            "SELECT id FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")
        conn.execute("DELETE FROM payment_transactions WHERE id = ?", (txn_id,))
