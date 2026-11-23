"""Find and resolve confirmed receipts without a second payment (DG-444)."""

import json

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel

from baker.api.auth import resolve_actor
from baker.api.payment_transactions import _resolve_order_id, _resolve_txn_or_404
from baker.db.connection import get_db
from baker.db.queries import paginated_envelope
from baker.models.payment_transaction import PaymentTransaction
from baker.services.payment_destination import BANK_DESTINATIONS, post_destination_movement
from baker.utils.time import now_utc

router = APIRouter(prefix='/api', tags=['payment-destinations'])


class DestinationAssignment(BaseModel):
    method: str
    payment_source: str = ''


@router.get('/payment-destinations')
def unresolved_destinations(
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    search: str = '',
):
    with get_db() as conn:
        where = "pt.method = 'unknown' AND pt.invalidated_at IS NULL"
        params = []
        if search:
            where += ' AND (instr(o.order_ref, ?) > 0 OR instr(o.customer_name, ?) > 0)'
            params = [search, search]
        query = ' FROM payment_transactions pt JOIN orders o ON o.id=pt.order_id WHERE ' + where
        summary = conn.execute(
            'SELECT COUNT(*) AS total, COALESCE(SUM(pt.amount),0) AS amount' + query, params,
        ).fetchone()
        rows = conn.execute(
            'SELECT pt.*, o.order_ref, o.customer_name' + query + ' ORDER BY pt.id LIMIT ? OFFSET ?',
            [*params, limit, offset],
        ).fetchall()
        items = [dict(PaymentTransaction.from_row(row).to_api_dict(),
                      orderRef=row['order_ref'], customerName=row['customer_name']) for row in rows]
        return dict(paginated_envelope(items, summary['total'], limit, offset),
                    unresolvedAmount=summary['amount'])


@router.post('/orders/{ref}/transactions/{txn_id}/destination')
def assign_destination(ref: str, txn_id: int, body: DestinationAssignment, request: Request):
    if (body.method == 'cash' and body.payment_source) or (
        body.method == 'transfer' and body.payment_source not in BANK_DESTINATIONS
    ) or body.method not in ('cash', 'transfer'):
        raise HTTPException(status_code=422, detail='Chọn tiền mặt hoặc một tài khoản ngân hàng cụ thể')
    with get_db() as conn:
        # Serialize verification and mutation so competing assignments cannot
        # both post. Exact retries return the first result without new entries.
        conn.execute('BEGIN IMMEDIATE')
        order_id = _resolve_order_id(conn, ref)
        row = _resolve_txn_or_404(conn, order_id, txn_id)
        txn = PaymentTransaction.from_row(row)
        if txn.invalidated_at:
            raise HTTPException(status_code=422, detail='Không thể đối soát giao dịch đã hủy')
        if txn.destination_resolved_at:
            if (txn.method, txn.payment_source) == (body.method, body.payment_source):
                return txn.to_api_dict()
            raise HTTPException(status_code=409, detail='Giao dịch đã được đối soát sang nơi nhận khác')
        if txn.method != 'unknown':
            raise HTTPException(status_code=422, detail='Giao dịch không có nơi nhận chưa rõ')
        posted = conn.execute(
            "SELECT COALESCE(SUM(jl.debit-jl.credit),0) FROM journal_entries je "
            "JOIN journal_lines jl ON jl.journal_entry_id=je.id JOIN accounts a ON a.id=jl.account_id "
            "WHERE je.source_type='payment_transaction' AND je.source_id=? AND a.code='1400'",
            (txn_id,),
        ).fetchone()[0]
        if abs(posted - txn.amount) > 0.005:
            raise HTTPException(status_code=409, detail='Cần sửa bút toán tiền chưa rõ nơi nhận trước khi đối soát')
        txn.method = body.method
        txn.payment_source = body.payment_source
        txn.destination_resolved_at = now_utc()
        txn.destination_resolved_by = resolve_actor(request, '')
        post_destination_movement(conn, txn)
        conn.execute(
            'UPDATE payment_transactions SET method=?, payment_source=?, '
            'destination_resolved_at=?, destination_resolved_by=? WHERE id=?',
            (txn.method, txn.payment_source, txn.destination_resolved_at, txn.destination_resolved_by, txn.id),
        )
        from baker.api.orders import _log_order_history
        _log_order_history(
            conn, order_id, 'field_edit', 'payment_destination',
            json.dumps({'transactionId': str(txn.id), 'method': 'unknown'}),
            json.dumps({'transactionId': str(txn.id), 'method': txn.method, 'paymentSource': txn.payment_source}),
            txn.destination_resolved_by,
        )
        return txn.to_api_dict()
