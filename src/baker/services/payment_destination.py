"""Atomic destination movements for confirmed receipts (DG-444).

Original payment journals stay in 1400. Movements are append-only, dated when
verified/corrected, and never re-date cash into a closed drawer.
"""

from fastapi import HTTPException

from baker.db.schema import _account_id_by_code, _insert_journal_entry
from baker.services.journal_sync._common import _active_drawer_id
from baker.utils.time import now_utc

BANK_DESTINATIONS = {'TK Phượng VCB': '1210', 'TK Ân VCB': '1220'}


def post_destination_movement(conn, txn, *, reverse=False):
    if not txn.destination_resolved_at:
        return
    drawer_id = None
    if txn.method == 'cash':
        drawer_id = _active_drawer_id(conn)
        if drawer_id is None:
            raise HTTPException(status_code=409, detail='Cần mở ngăn kéo tiền trước khi đối soát tiền mặt')
        code = '1101'
    else:
        code = BANK_DESTINATIONS[txn.payment_source]
    neutral = _account_id_by_code(conn, '1400')
    destination = _account_id_by_code(conn, code)
    debit, credit = (neutral, destination) if reverse else (destination, neutral)
    _insert_journal_entry(
        conn, description=f"{'Hủy' if reverse else 'Đối soát'} nơi nhận giao dịch {txn.id}",
        source_type='payment_destination', source_id=txn.id,
        transaction_date=now_utc(), drawer_id=drawer_id,
        lines=[(debit, txn.amount, 0, 'Đối soát nơi nhận'),
               (credit, 0, txn.amount, 'Đối soát nơi nhận')],
    )
