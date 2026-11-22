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


@pytest.mark.parametrize('method,source,code', [
    ('cash', '', '1101'), ('transfer', 'TK Phượng VCB', '1210'),
    ('transfer', 'TK Ân VCB', '1220'),
])
def test_assign_once_and_lifecycle(api_client, method, source, code):
    ref, response = receipt(api_client)
    txn = response.json()
    url = f"/api/orders/{ref}/transactions/{txn['id']}"
    payload = {'method': method, 'payment_source': source}
    if method == 'cash':
        assert api_client.post(url + '/destination', json=payload).status_code == 409
        assert api_client.post('/api/cash-drawer/open', json={'openingBalance': 0}).status_code == 201
    assigned = api_client.post(url + '/destination', json=payload)
    assert assigned.status_code == 200
    assert assigned.json()['destinationStatus'] == 'resolved'
    assert assigned.json()['createdAt'] == txn['createdAt']
    assert api_client.post(url + '/destination', json=payload).json() == assigned.json()
    other = {'method': 'transfer', 'payment_source': 'TK Ân VCB' if code != '1220' else 'TK Phượng VCB'}
    assert api_client.post(url + '/destination', json=other).status_code == 409
    assert api_client.get('/api/payment-destinations').json()['total'] == 0
    assert api_client.get(f'/api/orders/{ref}').json()['amountPaid'] == 100000
    assert api_client.patch(f'/api/orders/{ref}/payment-method', json={'method': 'cash'}).status_code == 422
    assert api_client.delete(url).status_code == 422
    with get_db() as conn:
        assert balances(conn)['1400'] == 0
        assert balances(conn)[code] == 100000
        assert conn.execute('SELECT COUNT(*) FROM payment_transactions').fetchone()[0] == 1
        assert conn.execute("SELECT COUNT(*) FROM journal_entries WHERE source_type='payment_destination'").fetchone()[0] == 1
        assert conn.execute("SELECT COUNT(*) FROM order_history WHERE field_name='payment_destination'").fetchone()[0] == 1
    assert api_client.post(url + '/invalidate', json={}).status_code == 200
    with get_db() as conn:
        assert balances(conn)['1400'] == 0
        assert balances(conn)[code] == 0
    assert api_client.post(url + '/restore').status_code == 200
    with get_db() as conn:
        assert balances(conn)['1400'] == 0
        assert balances(conn)[code] == 100000


def test_unresolved_list_pagination_and_invalidated_filter(api_client):
    ref, first = receipt(api_client)
    receipt(api_client)
    result = api_client.get('/api/payment-destinations', params={'limit': 1}).json()
    assert result['total'] == 2
    assert result['unresolvedAmount'] == 200000
    assert result['has_more'] is True
    assert result['items'][0]['orderRef'] == ref
    assert len(api_client.get('/api/payment-destinations?limit=1&offset=1').json()['items']) == 1
    assert api_client.get('/api/payment-destinations?search=missing').json()['total'] == 0
    url = f"/api/orders/{ref}/transactions/{first.json()['id']}"
    assert api_client.post(url + '/invalidate', json={}).status_code == 200
    assert api_client.get('/api/payment-destinations').json()['total'] == 1
    assert api_client.post(url + '/destination', json={'method': 'cash'}).status_code == 422


@pytest.mark.parametrize('payload', [
    {'method': 'transfer'}, {'method': 'transfer', 'payment_source': 'other'},
    {'method': 'unknown'}, {'method': 'cash', 'payment_source': 'TK Ân VCB'},
])
def test_assignment_validates_destination(api_client, payload):
    ref, response = receipt(api_client)
    url = f"/api/orders/{ref}/transactions/{response.json()['id']}/destination"
    assert api_client.post(url, json=payload).status_code == 422


def test_assignment_rollback_on_posting_failure(api_client, monkeypatch):
    from fastapi import HTTPException
    import baker.api.payment_destinations as api
    ref, response = receipt(api_client)
    def fail(conn, txn):
        conn.execute("UPDATE payment_transactions SET note='must rollback'")
        raise HTTPException(status_code=409, detail='simulated posting failure')
    monkeypatch.setattr(api, 'post_destination_movement', fail)
    url = f"/api/orders/{ref}/transactions/{response.json()['id']}/destination"
    assert api_client.post(url, json={'method': 'transfer', 'payment_source': 'TK Ân VCB'}).status_code == 409
    with get_db() as conn:
        row = conn.execute('SELECT * FROM payment_transactions').fetchone()
        assert row['method'] == 'unknown' and row['note'] == ''
        assert row['destination_resolved_at'] is None
        assert balances(conn)['1400'] == 100000


def test_cash_resolution_leaves_closed_drawer_unchanged(api_client):
    from baker.models.cash_drawer import CashDrawer
    ref, response = receipt(api_client)
    first = api_client.post('/api/cash-drawer/open', json={'openingBalance': 0}).json()
    assert api_client.post('/api/cash-drawer/close', json={'countedAmount': 0}).status_code == 200
    second = api_client.post('/api/cash-drawer/open', json={'openingBalance': 0}).json()
    url = f"/api/orders/{ref}/transactions/{response.json()['id']}"
    assert api_client.post(url + '/destination', json={'method': 'cash'}).status_code == 200
    with get_db() as conn:
        assert CashDrawer.get_by_id(conn, int(first['id'])).expected_balance(conn) == 0
        assert CashDrawer.get_by_id(conn, int(second['id'])).expected_balance(conn) == 100000
    assert api_client.post('/api/cash-drawer/close', json={'countedAmount': 100000}).status_code == 200
    assert api_client.post(url + '/invalidate', json={}).status_code == 409


def test_locked_original_survives_assignment_and_restore(api_client):
    ref, response = receipt(api_client)
    txn_id = response.json()['id']
    with get_db() as conn:
        conn.execute("UPDATE journal_entries SET locked_at='2026-11-23T00:00:00Z' WHERE source_type='payment_transaction'")
        original = tuple(conn.execute('SELECT * FROM journal_entries').fetchone())
    url = f'/api/orders/{ref}/transactions/{txn_id}'
    assert api_client.post(url + '/destination', json={'method': 'transfer', 'payment_source': 'TK Ân VCB'}).status_code == 200
    assert api_client.patch(url, json={'note': 'Đối soát xong'}).status_code == 200
    with get_db() as conn:
        assert tuple(conn.execute('SELECT * FROM journal_entries ORDER BY id LIMIT 1').fetchone()) == original
    for _ in range(2):
        assert api_client.post(url + '/invalidate', json={}).status_code == 200
        with get_db() as conn:
            assert balances(conn)['1400'] == 0
            assert balances(conn)['1220'] == 0
        assert api_client.post(url + '/restore').status_code == 200
        with get_db() as conn:
            assert balances(conn)['1400'] == 0
            assert balances(conn)['1220'] == 100000
            assert balances(conn)['2100'] == -100000


def test_assignment_scoped_to_order_and_actor(api_client):
    import jwt
    from baker.config import JWT_SECRET
    ref, response = receipt(api_client)
    other, _ = receipt(api_client)
    txn_id = response.json()['id']
    payload = {'method': 'transfer', 'payment_source': 'TK Phượng VCB'}
    assert api_client.post(f'/api/orders/{other}/transactions/{txn_id}/destination', json=payload).status_code == 404
    token = jwt.encode({'sub': 'verified-staff', 'role': 'staff'}, JWT_SECRET, algorithm='HS256')
    result = api_client.post(f'/api/orders/{ref}/transactions/{txn_id}/destination', json=payload,
                             headers={'Authorization': f'Bearer {token}'})
    assert result.json()['destinationResolvedBy'] == 'verified-staff'


def test_unknown_creation_rolls_back_if_journal_fails(api_client, monkeypatch):
    import baker.services.journal_sync as sync
    monkeypatch.setattr(sync, 'run_journal_sync', lambda *args, **kwargs: 'failed')
    _, response = receipt(api_client)
    assert response.status_code == 409
    with get_db() as conn:
        assert conn.execute('SELECT COUNT(*) FROM payment_transactions').fetchone()[0] == 0


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
