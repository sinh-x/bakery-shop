#!/usr/bin/env bash
# db-validate.sh — Pre/post-migration DB validation
# Captures snapshot of key DB metrics, diffs two snapshots, reports anomalies.
# Usage:
#   ./scripts/db-validate.sh snapshot --db-path ./data/baker.db [--output /tmp/snap.json]
#   ./scripts/db-validate.sh diff --pre snap1.json --post snap2.json
set -euo pipefail

DB_PATH="./data/baker.db"
OUTPUT=""
PRE_SNAP=""
POST_SNAP=""
COMMAND=""
ANOMALIES=0

usage() {
    cat <<EOF
Usage: db-validate.sh <command> [options]

Commands:
  snapshot  Capture DB metrics snapshot to JSON
  diff      Compare two snapshots and report anomalies

Snapshot options:
  --db-path PATH   Database file path (default: ./data/baker.db)
  --output PATH    Write snapshot JSON to file (default: stdout)

Diff options:
  --pre PATH    Pre-migration snapshot JSON file
  --post PATH   Post-migration snapshot JSON file
EOF
    exit 1
}

parse_args() {
    COMMAND="${1:-}"
    shift || true

    case "$COMMAND" in
        snapshot)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --db-path) DB_PATH="$2"; shift 2 ;;
                    --output) OUTPUT="$2"; shift 2 ;;
                    *) echo "Unknown option: $1"; usage ;;
                esac
            done
            ;;
        diff)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --pre) PRE_SNAP="$2"; shift 2 ;;
                    --post) POST_SNAP="$2"; shift 2 ;;
                    *) echo "Unknown option: $1"; usage ;;
                esac
            done
            ;;
        *) usage ;;
    esac
}

check_prereqs() {
    if ! command -v sqlite3 &>/dev/null; then
        echo "ERROR: sqlite3 CLI not found. Install sqlite3 to use this script." >&2
        exit 2
    fi
    if ! command -v python3 &>/dev/null; then
        echo "ERROR: python3 not found. Required for JSON diff." >&2
        exit 2
    fi
}

sql_json() {
    sqlite3 -readonly -json "$DB_PATH" "$1" 2>/dev/null
}

sql_value() {
    sqlite3 -readonly "$DB_PATH" "$1" 2>/dev/null
}

capture_snapshot() {
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" RETURN

    local ts
    ts=$(date -Iseconds)

    # Metric 1: Row counts per table
    sql_json "
        SELECT 'events' AS tbl, COUNT(*) AS cnt FROM events WHERE deleted_at IS NULL
        UNION ALL SELECT 'orders', COUNT(*) FROM orders
        UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
        UNION ALL SELECT 'products', COUNT(*) FROM products
        UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
        UNION ALL SELECT 'stock_lots', COUNT(*) FROM stock_lots
        UNION ALL SELECT 'inventory_items', COUNT(*) FROM inventory_items
        UNION ALL SELECT 'journal_entries', COUNT(*) FROM journal_entries
        UNION ALL SELECT 'journal_lines', COUNT(*) FROM journal_lines
        UNION ALL SELECT 'payment_transactions', COUNT(*) FROM payment_transactions WHERE invalidated_at IS NULL
        UNION ALL SELECT 'customers', COUNT(*) FROM customers
        UNION ALL SELECT 'reconciliation_sessions', COUNT(*) FROM reconciliation_sessions
        UNION ALL SELECT 'reconciliation_lines', COUNT(*) FROM reconciliation_lines
        UNION ALL SELECT 'staff', COUNT(*) FROM staff
        UNION ALL SELECT 'photos', COUNT(*) FROM photos
        UNION ALL SELECT 'knowledge_entries', COUNT(*) FROM knowledge_entries
        UNION ALL SELECT 'checklist_entries', COUNT(*) FROM checklist_entries
        UNION ALL SELECT 'cost_history', COUNT(*) FROM cost_history
    " > "$tmpdir/row_counts.json"

    # Metric 2: Financial lump sums
    sql_json "SELECT COUNT(*) AS order_count, COALESCE(SUM(total_price), 0) AS total_value FROM orders" > "$tmpdir/orders_total.json"
    sql_json "SELECT strftime('%Y', created_at) AS year, COUNT(*) AS order_count, COALESCE(SUM(total_price), 0) AS total_value FROM orders GROUP BY year ORDER BY year" > "$tmpdir/orders_by_year.json"
    sql_json "SELECT strftime('%Y-%m', created_at) AS month, COUNT(*) AS order_count, COALESCE(SUM(total_price), 0) AS total_value FROM orders GROUP BY month ORDER BY month" > "$tmpdir/orders_by_month.json"
    sql_json "SELECT COUNT(*) AS delivered_count, COALESCE(SUM(total_price), 0) AS delivered_value FROM orders WHERE status IN ('delivered', 'completed')" > "$tmpdir/delivered_orders.json"
    sql_value "SELECT COALESCE(SUM(amount), 0) FROM payment_transactions WHERE invalidated_at IS NULL" > "$tmpdir/total_deposits.txt"
    sql_value "SELECT COALESCE(SUM(json_extract(data, '\$.amount_vnd')), 0) FROM events WHERE type = 'expense' AND deleted_at IS NULL" > "$tmpdir/total_expenses.txt"

    # Metric 3: Stock position
    sql_value "SELECT COALESCE(SUM(remaining_qty), 0) FROM stock_lots" > "$tmpdir/stock_qty.txt"
    sql_value "SELECT COUNT(*) FROM inventory_items WHERE status = 'available'" > "$tmpdir/available_items.txt"

    # Metric 4: Journal trial balance
    sql_json "SELECT a.code, a.name, COALESCE(SUM(jl.debit), 0) AS total_debit, COALESCE(SUM(jl.credit), 0) AS total_credit FROM accounts a LEFT JOIN journal_lines jl ON jl.account_id = a.id GROUP BY a.id ORDER BY a.code" > "$tmpdir/trial_balance.json"

    # Metric 5: Order status distribution
    sql_json "SELECT status, COUNT(*) AS cnt FROM orders GROUP BY status" > "$tmpdir/order_status_dist.json"

    # Metric 6: Event type distribution
    sql_json "SELECT type, COUNT(*) AS cnt FROM events WHERE deleted_at IS NULL GROUP BY type" > "$tmpdir/event_type_dist.json"

    # Metric 7: Journal totals
    sql_json "SELECT COALESCE(SUM(debit), 0) AS total_debit, COALESCE(SUM(credit), 0) AS total_credit FROM journal_lines" > "$tmpdir/journal_totals.json"

    # Metric 8: Customer + active product counts
    sql_value "SELECT COUNT(*) FROM customers" > "$tmpdir/customer_count.txt"
    sql_value "SELECT COUNT(*) FROM products WHERE active = 1" > "$tmpdir/active_product_count.txt"

    # Metric 9: Customer-Order Linkage Health
    sql_value "SELECT COUNT(*) FROM customers c WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id)" > "$tmpdir/customers_without_orders.txt"
    sql_json "SELECT status, COUNT(*) AS cnt FROM orders WHERE customer_id IS NULL GROUP BY status" > "$tmpdir/orders_without_customer.json"
    sql_value "SELECT (SELECT COUNT(*) FROM customer_year_summary) - (SELECT COUNT(DISTINCT customer_id) FROM customer_year_summary) AS mismatch" > "$tmpdir/customer_year_mismatch.txt"

    # Metric 10: COGS Coverage
    sql_json "
        SELECT
            CASE WHEN oi.cost_at_sale > 0 THEN 'explicit' ELSE 'baseline' END AS cost_type,
            COUNT(*) AS item_count,
            ROUND(AVG(oi.unit_price * 0.3)) AS avg_baseline_estimate,
            ROUND(AVG(oi.cost_at_sale)) AS avg_actual_cost
        FROM order_items oi
        JOIN orders o ON o.id = oi.order_id
        WHERE o.status IN ('delivered', 'completed')
        GROUP BY 1
    " > "$tmpdir/cogs_coverage.json"
    sql_json "SELECT COUNT(*) AS cogs_line_count, COALESCE(SUM(jl.debit), 0) AS cogs_total_debit FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id WHERE a.code = '5900'" > "$tmpdir/cogs_journal.json"

    # Metric 11: Phone Coverage
    sql_value "SELECT COUNT(*) FROM customers c WHERE EXISTS (SELECT 1 FROM customer_phones cp WHERE cp.customer_id = c.id)" > "$tmpdir/customers_with_phones.txt"
    sql_value "SELECT COUNT(*) FROM customers c WHERE NOT EXISTS (SELECT 1 FROM customer_phones cp WHERE cp.customer_id = c.id)" > "$tmpdir/customers_without_phones.txt"
    sql_value "SELECT COUNT(*) FROM customers WHERE phone IS NOT NULL AND phone != ''" > "$tmpdir/customers_legacy_phone.txt"

    # Metric 12: Payment Reconciliation
    sql_value "SELECT COUNT(*) FROM payment_transactions WHERE invalidated_at IS NULL" > "$tmpdir/payment_tx_count.txt"
    sql_value "SELECT COUNT(*) FROM orders" > "$tmpdir/order_count_for_payment.txt"
    sql_json "SELECT a.code, a.name, COALESCE(SUM(jl.credit), 0) AS total_credit FROM accounts a LEFT JOIN journal_lines jl ON jl.account_id = a.id WHERE a.code IN ('1200', '1201') GROUP BY a.id ORDER BY a.code" > "$tmpdir/deposit_accounts.json"

    # Schema version
    sql_value "SELECT COALESCE(MAX(version), 0) FROM schema_version" > "$tmpdir/schema_version.txt"

    # Integrity check
    sql_value "PRAGMA integrity_check" > "$tmpdir/integrity.txt"

    # Assemble final JSON
    python3 -c "
import json, os

tmpdir = '$tmpdir'

def read_json(path):
    with open(path) as f:
        return json.load(f)

def read_value(path):
    with open(path) as f:
        return f.read().strip()

snapshot = {
    'timestamp': '$ts',
    'db_path': '$DB_PATH',
    'schema_version': int(read_value(os.path.join(tmpdir, 'schema_version.txt')) or 0),
    'integrity_check': read_value(os.path.join(tmpdir, 'integrity.txt')) or 'ok',
    'metrics': {
        'row_counts': read_json(os.path.join(tmpdir, 'row_counts.json')),
        'financial': {
            'orders_total': read_json(os.path.join(tmpdir, 'orders_total.json')),
            'orders_by_year': read_json(os.path.join(tmpdir, 'orders_by_year.json')),
            'orders_by_month': read_json(os.path.join(tmpdir, 'orders_by_month.json')),
            'delivered_orders': read_json(os.path.join(tmpdir, 'delivered_orders.json')),
            'total_deposits': float(read_value(os.path.join(tmpdir, 'total_deposits.txt')) or 0),
            'total_expenses': float(read_value(os.path.join(tmpdir, 'total_expenses.txt')) or 0)
        },
        'stock': {
            'total_remaining_qty': float(read_value(os.path.join(tmpdir, 'stock_qty.txt')) or 0),
            'available_inventory_items': int(read_value(os.path.join(tmpdir, 'available_items.txt')) or 0)
        },
        'trial_balance': read_json(os.path.join(tmpdir, 'trial_balance.json')),
        'order_status_distribution': read_json(os.path.join(tmpdir, 'order_status_dist.json')),
        'event_type_distribution': read_json(os.path.join(tmpdir, 'event_type_dist.json')),
        'journal_totals': read_json(os.path.join(tmpdir, 'journal_totals.json')),
        'customer_count': int(read_value(os.path.join(tmpdir, 'customer_count.txt')) or 0),
        'active_product_count': int(read_value(os.path.join(tmpdir, 'active_product_count.txt')) or 0),
        'customer_order_linkage': {
            'customers_without_orders': int(read_value(os.path.join(tmpdir, 'customers_without_orders.txt')) or 0),
            'orders_without_customer': read_json(os.path.join(tmpdir, 'orders_without_customer.json')),
            'customer_year_summary_mismatch': int(read_value(os.path.join(tmpdir, 'customer_year_mismatch.txt')) or 0)
        },
        'cogs_coverage': {
            'cost_type_breakdown': read_json(os.path.join(tmpdir, 'cogs_coverage.json')),
            'cogs_journal': read_json(os.path.join(tmpdir, 'cogs_journal.json'))
        },
        'phone_coverage': {
            'customers_with_phones': int(read_value(os.path.join(tmpdir, 'customers_with_phones.txt')) or 0),
            'customers_without_phones': int(read_value(os.path.join(tmpdir, 'customers_without_phones.txt')) or 0),
            'customers_legacy_phone': int(read_value(os.path.join(tmpdir, 'customers_legacy_phone.txt')) or 0)
        },
        'payment_reconciliation': {
            'payment_transactions_count': int(read_value(os.path.join(tmpdir, 'payment_tx_count.txt')) or 0),
            'orders_count': int(read_value(os.path.join(tmpdir, 'order_count_for_payment.txt')) or 0),
            'deposit_accounts': read_json(os.path.join(tmpdir, 'deposit_accounts.json'))
        }
    }
}
print(json.dumps(snapshot, indent=2, ensure_ascii=False))
"
}

diff_snapshots() {
    python3 -c "
import json, sys

with open('$PRE_SNAP') as f:
    pre = json.load(f)
with open('$POST_SNAP') as f:
    post = json.load(f)

findings = []

def flag(severity, msg):
    findings.append((severity, msg))
    print(f'{severity}: {msg}', file=sys.stderr)

# Schema version
pre_sv = pre.get('schema_version', 0)
post_sv = post.get('schema_version', 0)
print(f'Schema version: {pre_sv} -> {post_sv}')
if post_sv < pre_sv:
    flag('Critical', f'Schema version decreased: {pre_sv} -> {post_sv}')

# Integrity check
pre_ic = pre.get('integrity_check', 'ok')
post_ic = post.get('integrity_check', 'ok')
print(f'Integrity check: {pre_ic} -> {post_ic}')
if post_ic != 'ok':
    flag('Critical', f'Post-migration integrity check failed: {post_ic}')

m_pre = pre.get('metrics', {})
m_post = post.get('metrics', {})

# Row counts
pre_rc = {r['tbl']: r['cnt'] for r in m_pre.get('row_counts', [])}
post_rc = {r['tbl']: r['cnt'] for r in m_post.get('row_counts', [])}
print()
print('=== Row Counts ===')
all_tables = sorted(set(list(pre_rc.keys()) + list(post_rc.keys())))
for tbl in all_tables:
    before = pre_rc.get(tbl, 0)
    after = post_rc.get(tbl, 0)
    delta = after - before
    flag_str = ''
    if after < before:
        pct = (before - after) / before * 100 if before > 0 else 0
        if pct > 10:
            flag_str = ' [Critical: decrease >10%]'
            flag('Critical', f'Row count decreased >10% for {tbl}: {before} -> {after} ({pct:.1f}%)')
        else:
            flag_str = ' [Major: decrease]'
            flag('Major', f'Row count decreased for {tbl}: {before} -> {after}')
    print(f'  {tbl}: {before} -> {after} ({delta:+d}){flag_str}')

# Financial
print()
print('=== Financial ===')
fin_pre = m_pre.get('financial', {})
fin_post = m_post.get('financial', {})

# Orders total
ot_pre = fin_pre.get('orders_total', [{}])
ot_post = fin_post.get('orders_total', [{}])
if ot_pre and ot_post:
    oc_pre = ot_pre[0].get('order_count', 0) if isinstance(ot_pre, list) else ot_pre.get('order_count', 0)
    oc_post = ot_post[0].get('order_count', 0) if isinstance(ot_post, list) else ot_post.get('order_count', 0)
    ov_pre = ot_pre[0].get('total_value', 0) if isinstance(ot_pre, list) else ot_pre.get('total_value', 0)
    ov_post = ot_post[0].get('total_value', 0) if isinstance(ot_post, list) else ot_post.get('total_value', 0)
    print(f'  Orders total: {oc_pre} ({ov_pre:,.0f}) -> {oc_post} ({ov_post:,.0f})')
    if oc_post < oc_pre:
        flag('Major', f'Order count decreased: {oc_pre} -> {oc_post}')
    if ov_post < ov_pre - 0.01:
        flag('Major', f'Order total value decreased: {ov_pre:,.0f} -> {ov_post:,.0f}')

# Delivered orders
do_pre = fin_pre.get('delivered_orders', [{}])
do_post = fin_post.get('delivered_orders', [{}])
if do_pre and do_post:
    dc_pre = do_pre[0].get('delivered_count', 0) if isinstance(do_pre, list) else do_pre.get('delivered_count', 0)
    dc_post = do_post[0].get('delivered_count', 0) if isinstance(do_post, list) else do_post.get('delivered_count', 0)
    dv_pre = do_pre[0].get('delivered_value', 0) if isinstance(do_pre, list) else do_pre.get('delivered_value', 0)
    dv_post = do_post[0].get('delivered_value', 0) if isinstance(do_post, list) else do_post.get('delivered_value', 0)
    print(f'  Delivered orders: {dc_pre} ({dv_pre:,.0f}) -> {dc_post} ({dv_post:,.0f})')
    if dc_post < dc_pre:
        flag('Major', f'Delivered order count decreased: {dc_pre} -> {dc_post}')
    if dv_post < dv_pre - 0.01:
        flag('Major', f'Delivered order value decreased: {dv_pre:,.0f} -> {dv_post:,.0f}')

# Deposits
dep_pre = fin_pre.get('total_deposits', 0)
dep_post = fin_post.get('total_deposits', 0)
print(f'  Total deposits: {dep_pre:,.0f} -> {dep_post:,.0f}')
if dep_post < dep_pre - 0.01:
    flag('Major', f'Total deposits decreased: {dep_pre:,.0f} -> {dep_post:,.0f}')

# Expenses
exp_pre = fin_pre.get('total_expenses', 0)
exp_post = fin_post.get('total_expenses', 0)
print(f'  Total expenses: {exp_pre:,.0f} -> {exp_post:,.0f}')
if exp_post < exp_pre - 0.01:
    flag('Major', f'Total expenses decreased: {exp_pre:,.0f} -> {exp_post:,.0f}')

# Stock
print()
print('=== Stock Position ===')
stk_pre = m_pre.get('stock', {})
stk_post = m_post.get('stock', {})
sq_pre = stk_pre.get('total_remaining_qty', 0)
sq_post = stk_post.get('total_remaining_qty', 0)
ai_pre = stk_pre.get('available_inventory_items', 0)
ai_post = stk_post.get('available_inventory_items', 0)
print(f'  Stock remaining qty: {sq_pre} -> {sq_post}')
print(f'  Available inventory items: {ai_pre} -> {ai_post}')
if sq_post < sq_pre - 0.001:
    flag('Major', f'Stock remaining qty decreased: {sq_pre} -> {sq_post}')
if ai_post < ai_pre:
    flag('Major', f'Available inventory items decreased: {ai_pre} -> {ai_post}')

# Trial balance
print()
print('=== Trial Balance ===')
tb_pre = {r['code']: r for r in m_pre.get('trial_balance', [])}
tb_post = {r['code']: r for r in m_post.get('trial_balance', [])}
all_codes = sorted(set(list(tb_pre.keys()) + list(tb_post.keys())))
for code in all_codes:
    pre_r = tb_pre.get(code, {'total_debit': 0, 'total_credit': 0})
    post_r = tb_post.get(code, {'total_debit': 0, 'total_credit': 0})
    d_delta = post_r['total_debit'] - pre_r['total_debit']
    c_delta = post_r['total_credit'] - pre_r['total_credit']
    drift = abs(d_delta) + abs(c_delta)
    flag_str = ''
    if drift > 100:
        flag_str = f' [Critical: drift {drift:,.2f}]'
        flag('Critical', f'Account {code} balance drift >100 VND: debit {pre_r[\"total_debit\"]:,.0f}->{post_r[\"total_debit\"]:,.0f}, credit {pre_r[\"total_credit\"]:,.0f}->{post_r[\"total_credit\"]:,.0f}')
    elif drift > 0.01:
        flag_str = f' [Major: drift {drift:,.2f}]'
        flag('Major', f'Account {code} balance drift: debit {pre_r[\"total_debit\"]:,.0f}->{post_r[\"total_debit\"]:,.0f}, credit {pre_r[\"total_credit\"]:,.0f}->{post_r[\"total_credit\"]:,.0f}')
    print(f'  {code}: debit {pre_r[\"total_debit\"]:,.0f}->{post_r[\"total_debit\"]:,.0f} credit {pre_r[\"total_credit\"]:,.0f}->{post_r[\"total_credit\"]:,.0f}{flag_str}')

# Order status distribution
print()
print('=== Order Status Distribution ===')
os_pre = {r['status']: r['cnt'] for r in m_pre.get('order_status_distribution', [])}
os_post = {r['status']: r['cnt'] for r in m_post.get('order_status_distribution', [])}
all_statuses = sorted(set(list(os_pre.keys()) + list(os_post.keys())))
for st in all_statuses:
    before = os_pre.get(st, 0)
    after = os_post.get(st, 0)
    delta = after - before
    flag_str = ''
    if after < before:
        flag_str = ' [Major: decrease]'
        flag('Major', f'Order status \"{st}\" count decreased: {before} -> {after}')
    print(f'  {st}: {before} -> {after} ({delta:+d}){flag_str}')

# Event type distribution
print()
print('=== Event Type Distribution ===')
ev_pre = {r['type']: r['cnt'] for r in m_pre.get('event_type_distribution', [])}
ev_post = {r['type']: r['cnt'] for r in m_post.get('event_type_distribution', [])}
all_types = sorted(set(list(ev_pre.keys()) + list(ev_post.keys())))
for et in all_types:
    before = ev_pre.get(et, 0)
    after = ev_post.get(et, 0)
    delta = after - before
    flag_str = ''
    if after < before:
        flag_str = ' [Major: decrease]'
        flag('Major', f'Event type \"{et}\" count decreased: {before} -> {after}')
    print(f'  {et}: {before} -> {after} ({delta:+d}){flag_str}')

# Journal totals
print()
print('=== Journal Totals ===')
jt_pre = m_pre.get('journal_totals', [{}])
jt_post = m_post.get('journal_totals', [{}])
if jt_pre and jt_post:
    jd_pre = jt_pre[0].get('total_debit', 0) if isinstance(jt_pre, list) else jt_pre.get('total_debit', 0)
    jc_pre = jt_pre[0].get('total_credit', 0) if isinstance(jt_pre, list) else jt_pre.get('total_credit', 0)
    jd_post = jt_post[0].get('total_debit', 0) if isinstance(jt_post, list) else jt_post.get('total_debit', 0)
    jc_post = jt_post[0].get('total_credit', 0) if isinstance(jt_post, list) else jt_post.get('total_credit', 0)
    imbalance_pre = abs(jd_pre - jc_pre)
    imbalance_post = abs(jd_post - jc_post)
    print(f'  Debit: {jd_pre:,.0f} -> {jd_post:,.0f}')
    print(f'  Credit: {jc_pre:,.0f} -> {jc_post:,.0f}')
    print(f'  Imbalance: {imbalance_pre:,.2f} -> {imbalance_post:,.2f}')
    if imbalance_post > 100:
        flag('Critical', f'Journal imbalance >100 VND: {imbalance_post:,.2f}')
    elif imbalance_post > 0.01:
        flag('Major', f'Journal imbalance >0.01 VND: {imbalance_post:,.2f}')

# Customer + product counts
print()
print('=== Counts ===')
cc_pre = m_pre.get('customer_count', 0)
cc_post = m_post.get('customer_count', 0)
ap_pre = m_pre.get('active_product_count', 0)
ap_post = m_post.get('active_product_count', 0)
print(f'  Customers: {cc_pre} -> {cc_post}')
print(f'  Active products: {ap_pre} -> {ap_post}')
if cc_post < cc_pre:
    flag('Major', f'Customer count decreased: {cc_pre} -> {cc_post}')
if ap_post < ap_pre:
    flag('Major', f'Active product count decreased: {ap_pre} -> {ap_post}')

# Metric 9: Customer-Order Linkage Health
print()
print('=== Customer-Order Linkage Health ===')
col_pre = m_pre.get('customer_order_linkage', {})
col_post = m_post.get('customer_order_linkage', {})
cuwo_pre = col_pre.get('customers_without_orders', 0)
cuwo_post = col_post.get('customers_without_orders', 0)
print(f'  Customers without orders: {cuwo_pre} -> {cuwo_post}')
if cuwo_post > cuwo_pre:
    flag('Minor', f'Customers without orders increased: {cuwo_pre} -> {cuwo_post}')

owc_pre = {r['status']: r['cnt'] for r in col_pre.get('orders_without_customer', [])}
owc_post = {r['status']: r['cnt'] for r in col_post.get('orders_without_customer', [])}
all_owc_statuses = sorted(set(list(owc_pre.keys()) + list(owc_post.keys())))
for st in all_owc_statuses:
    before = owc_pre.get(st, 0)
    after = owc_post.get(st, 0)
    delta = after - before
    flag_str = ''
    if after > before:
        flag_str = ' [Minor: increase]'
        flag('Minor', f'Orders without customer_id ({st}) increased: {before} -> {after}')
    print(f'  Orders without customer ({st}): {before} -> {after} ({delta:+d}){flag_str}')

cys_pre = col_pre.get('customer_year_summary_mismatch', 0)
cys_post = col_post.get('customer_year_summary_mismatch', 0)
print(f'  Customer year summary mismatch: {cys_pre} -> {cys_post}')
if cys_post != 0:
    flag('Major', f'Customer year summary mismatch: {cys_post}')

# Metric 10: COGS Coverage
print()
print('=== COGS Coverage ===')
cogs_pre = m_pre.get('cogs_coverage', {})
cogs_post = m_post.get('cogs_coverage', {})
ctb_pre = {r['cost_type']: r for r in cogs_pre.get('cost_type_breakdown', [])}
ctb_post = {r['cost_type']: r for r in cogs_post.get('cost_type_breakdown', [])}
for ct in ['explicit', 'baseline']:
    pre_r = ctb_pre.get(ct, {'item_count': 0, 'avg_baseline_estimate': 0, 'avg_actual_cost': 0})
    post_r = ctb_post.get(ct, {'item_count': 0, 'avg_baseline_estimate': 0, 'avg_actual_cost': 0})
    print(f'  COGS {ct}: {pre_r[\"item_count\"]} items -> {post_r[\"item_count\"]} items')
    if post_r['item_count'] < pre_r['item_count']:
        flag('Major', f'COGS {ct} item count decreased: {pre_r[\"item_count\"]} -> {post_r[\"item_count\"]}')

cj_pre = cogs_pre.get('cogs_journal', [{}])
cj_post = cogs_post.get('cogs_journal', [{}])
if cj_pre and cj_post:
    clc_pre = cj_pre[0].get('cogs_line_count', 0) if isinstance(cj_pre, list) else cj_pre.get('cogs_line_count', 0)
    clc_post = cj_post[0].get('cogs_line_count', 0) if isinstance(cj_post, list) else cj_post.get('cogs_line_count', 0)
    ctd_pre = cj_pre[0].get('cogs_total_debit', 0) if isinstance(cj_pre, list) else cj_pre.get('cogs_total_debit', 0)
    ctd_post = cj_post[0].get('cogs_total_debit', 0) if isinstance(cj_post, list) else cj_post.get('cogs_total_debit', 0)
    print(f'  COGS journal lines: {clc_pre} -> {clc_post}')
    print(f'  COGS total debit: {ctd_pre:,.0f} -> {ctd_post:,.0f}')
    if clc_post == 0:
        flag('Info', 'COGS journal lines = 0 (journal backfill may not have been run)')
    if ctd_post < ctd_pre - 0.01:
        flag('Major', f'COGS total debit decreased: {ctd_pre:,.0f} -> {ctd_post:,.0f}')

# Metric 11: Phone Coverage
print()
print('=== Phone Coverage ===')
ph_pre = m_pre.get('phone_coverage', {})
ph_post = m_post.get('phone_coverage', {})
cwp_pre = ph_pre.get('customers_with_phones', 0)
cwp_post = ph_post.get('customers_with_phones', 0)
cwop_pre = ph_pre.get('customers_without_phones', 0)
cwop_post = ph_post.get('customers_without_phones', 0)
clp_pre = ph_pre.get('customers_legacy_phone', 0)
clp_post = ph_post.get('customers_legacy_phone', 0)
print(f'  Customers with phones: {cwp_pre} -> {cwp_post}')
print(f'  Customers without phones: {cwop_pre} -> {cwop_post}')
print(f'  Customers with legacy phone: {clp_pre} -> {clp_post}')
total_cust = cc_post if cc_post > 0 else 1
phone_pct = cwp_post / total_cust * 100
print(f'  Phone coverage rate: {phone_pct:.1f}%')
if cwop_post > cwop_pre:
    flag('Info', f'Customers without phones increased: {cwop_pre} -> {cwop_post}')

# Metric 12: Payment Reconciliation
print()
print('=== Payment Reconciliation ===')
pay_pre = m_pre.get('payment_reconciliation', {})
pay_post = m_post.get('payment_reconciliation', {})
ptx_pre = pay_pre.get('payment_transactions_count', 0)
ptx_post = pay_post.get('payment_transactions_count', 0)
ocp_pre = pay_pre.get('orders_count', 0)
ocp_post = pay_post.get('orders_count', 0)
print(f'  Payment transactions: {ptx_pre} -> {ptx_post}')
print(f'  Orders: {ocp_pre} -> {ocp_post}')
if ocp_post > 0:
    ratio_pre = ptx_pre / ocp_pre if ocp_pre > 0 else 0
    ratio_post = ptx_post / ocp_post
    print(f'  Payment-to-order ratio: {ratio_pre:.2f} -> {ratio_post:.2f}')
    if ratio_post < ratio_pre - 0.1:
        flag('Info', f'Payment-to-order ratio decreased: {ratio_pre:.2f} -> {ratio_post:.2f}')

da_pre = {r['code']: r for r in pay_pre.get('deposit_accounts', [])}
da_post = {r['code']: r for r in pay_post.get('deposit_accounts', [])}
all_da_codes = sorted(set(list(da_pre.keys()) + list(da_post.keys())))
for code in all_da_codes:
    pre_r = da_pre.get(code, {'total_credit': 0})
    post_r = da_post.get(code, {'total_credit': 0})
    delta = post_r['total_credit'] - pre_r['total_credit']
    flag_str = ''
    if abs(delta) > 0.01:
        flag_str = f' [Major: drift {delta:,.2f}]'
        flag('Major', f'Deposit account {code} credit drift: {pre_r[\"total_credit\"]:,.0f} -> {post_r[\"total_credit\"]:,.0f}')
    print(f'  {code}: credit {pre_r[\"total_credit\"]:,.0f} -> {post_r[\"total_credit\"]:,.0f}{flag_str}')

# Summary
print()
critical_count = sum(1 for s, _ in findings if s == 'Critical')
major_count = sum(1 for s, _ in findings if s == 'Major')
minor_count = sum(1 for s, _ in findings if s == 'Minor')
info_count = sum(1 for s, _ in findings if s == 'Info')
total = len(findings)

print(f'Findings: {total} total (Critical={critical_count}, Major={major_count}, Minor={minor_count}, Info={info_count})')

if critical_count > 0:
    print(f'RESULT: {critical_count} Critical, {major_count} Major, {minor_count} Minor, {info_count} Info', file=sys.stderr)
    sys.exit(3)
elif major_count > 0:
    print(f'RESULT: {major_count} Major, {minor_count} Minor, {info_count} Info', file=sys.stderr)
    sys.exit(2)
elif minor_count > 0 or info_count > 0:
    print(f'RESULT: {minor_count} Minor, {info_count} Info', file=sys.stderr)
    sys.exit(1)
else:
    print('RESULT: No anomalies detected')
    sys.exit(0)
"
}

# --- Main ---
parse_args "$@"
check_prereqs

if [[ ! -f "$DB_PATH" ]] && [[ "$COMMAND" == "snapshot" ]]; then
    echo "ERROR: Database not found at $DB_PATH" >&2
    exit 1
fi

case "$COMMAND" in
    snapshot)
        if [[ -n "$OUTPUT" ]]; then
            capture_snapshot > "$OUTPUT"
            echo "Snapshot saved to $OUTPUT"
        else
            capture_snapshot
        fi
        ;;
    diff)
        if [[ ! -f "$PRE_SNAP" ]]; then
            echo "ERROR: Pre-snapshot file not found: $PRE_SNAP" >&2
            exit 1
        fi
        if [[ ! -f "$POST_SNAP" ]]; then
            echo "ERROR: Post-snapshot file not found: $POST_SNAP" >&2
            exit 1
        fi
        diff_snapshots
        ;;
esac
