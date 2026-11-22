"""DG-444 neutral receipt and destination reconciliation invariants."""

import pytest

from baker.db.connection import get_db
from baker.db.schema import ensure_schema
from baker.db.schema.migrations.v106 import _migrate_v106_unknown_payment_destination


def receipt(client, **overrides):
    order = client.post('/api/orders', json={
        'customerName': 'Khách đối soát', 'dueDate': '2026-11-23',
        'items': [{'productName': 'Bánh', 'quantity': 1, 'unitPrice': 300000}],
    }).json()
    response = client.post(f"/api/orders/{order['orderRef']}/transactions", json={
        'amount': 100000, 'method': 'unknown', 'type': 'payment', **overrides,
    })
    return order['orderRef'], response


def balances(conn):
    return dict(conn.execute(
        'SELECT a.code, SUM(jl.debit-jl.credit) FROM journal_lines jl '
        'JOIN accounts a ON a.id=jl.account_id GROUP BY a.code'
    ).fetchall())


def test_neutral_receipt_counts_once_without_drawer(api_client):
    ref, response = receipt(api_client)
    assert response.status_code == 201
    txn = response.json()
    assert txn['destinationStatus'] == 'unresolved'
    assert txn['accountingSync'] == 'ok'
    assert api_client.get(f'/api/orders/{ref}').json()['amountPaid'] == 100000
    with get_db() as conn:
        assert balances(conn)['1400'] == 100000
        assert balances(conn)['2100'] == -100000
        assert conn.execute('SELECT COUNT(*) FROM cash_drawer_journal_entries').fetchone()[0] == 0


@pytest.mark.parametrize('overrides', [
    {'type': 'refund'}, {'type': 'tien_rut'}, {'payment_source': 'TK Phượng VCB'},
])
def test_unknown_rejects_outflows_and_conflicting_source(api_client, overrides):
    _, response = receipt(api_client, **overrides)
    assert response.status_code == 422


def test_unknown_financial_edits_require_replacement(api_client):
    ref, response = receipt(api_client)
    url = f"/api/orders/{ref}/transactions/{response.json()['id']}"
    assert api_client.patch(url, json={'method': 'cash'}).status_code == 422
    assert api_client.patch(url, json={'note': 'Đã nhận tiền'}).status_code == 200


def test_migration_idempotent_and_account_neutral(api_client):
    with get_db() as conn:
        # Back up the disposable database before explicitly reapplying DDL.
        import sqlite3
        with sqlite3.connect(':memory:') as backup:
            conn.backup(backup)
            _migrate_v106_unknown_payment_destination(conn)
            _migrate_v106_unknown_payment_destination(conn)
            ensure_schema(conn)
        account = conn.execute(
            "SELECT a.type, p.code FROM accounts a JOIN accounts p ON p.id=a.parent_id WHERE a.code='1400'"
        ).fetchone()
        assert tuple(account) == ('asset', '1000')
        assert conn.execute("SELECT COUNT(*) FROM accounts WHERE code='1400'").fetchone()[0] == 1
