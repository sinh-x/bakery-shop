import json
from datetime import datetime, timezone
from pathlib import Path

import click
from baker.db.connection import get_db
from baker.db.schema import MIGRATIONS


@click.group("db")
def db_cmd():
    """Database management commands."""
    pass


@db_cmd.command("status")
def db_status():
    """Show current schema version and pending migrations."""
    with get_db() as conn:
        # Check if schema_version table exists
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
        ).fetchone()
        if not row:
            current = 0
        else:
            row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
            current = row[0] if row[0] else 0

        latest = max(MIGRATIONS.keys())
        pending = [v for v in sorted(MIGRATIONS.keys()) if v > current]

        click.echo(f"Current schema version : {current}")
        click.echo(f"Latest available       : {latest}")
        if pending:
            click.echo(f"Pending migrations     : {len(pending)}")
            for v in pending:
                click.echo(f"  v{v}: {MIGRATIONS[v]['description']}")
        else:
            click.echo("Status                 : up to date")

        # Show applied migrations
        if current > 0:
            rows = conn.execute(
                "SELECT version, applied_at, description FROM schema_version ORDER BY version"
            ).fetchall()
            click.echo("\nApplied migrations:")
            for r in rows:
                click.echo(f"  v{r['version']} ({r['applied_at'][:16]}): {r['description']}")


@db_cmd.command("migrate")
@click.option("--backup/--no-backup", default=True, help="Backup before migrating (default: yes)")
@click.option("--dry-run", is_flag=True, help="Show pending migrations without applying them")
def db_migrate(backup, dry_run):
    """Apply pending schema migrations.

    Automatically backs up the database before running migrations (use --no-backup to skip).
    Safe to run multiple times — already-applied migrations are skipped.
    """
    import baker.config
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
        ).fetchone()
        current = 0
        if row:
            r = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
            current = r[0] if r[0] else 0

        pending = [v for v in sorted(MIGRATIONS.keys()) if v > current]

        if not pending:
            click.echo(f"Already up to date (schema version {current}).")
            return

        click.echo(f"Current version: v{current}")
        click.echo(f"Pending ({len(pending)}):")
        for v in pending:
            click.echo(f"  v{v}: {MIGRATIONS[v]['description']}")

        if dry_run:
            click.echo("\nDry run — no changes made.")
            return

        if backup:
            import shutil
            from datetime import datetime
            src = baker.config.DB_PATH
            if src.exists():
                ts = datetime.now().strftime("%Y%m%d-%H%M%S")
                bak = src.parent / f"baker-backup-pre-migrate-{ts}.db"
                shutil.copy2(src, bak)
                click.echo(f"\nBackup: {bak}")

        ensure_schema(conn)
        click.echo(f"\nMigrations applied. Schema is now at v{max(MIGRATIONS.keys())}.")


@db_cmd.command("backup")
@click.option("--dest", default=None, help="Destination file path (default: same dir as DB, timestamped)")
def db_backup(dest):
    """Backup the database to a timestamped file."""
    import shutil
    import baker.config
    from datetime import datetime

    src = baker.config.DB_PATH
    if not src.exists():
        click.echo(f"Error: database not found at {src}", err=True)
        raise SystemExit(1)

    if dest is None:
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        dest = src.parent / f"baker-backup-{ts}.db"
    else:
        from pathlib import Path
        dest = Path(dest)

    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    size_kb = dest.stat().st_size // 1024
    click.echo(f"Backup created: {dest} ({size_kb} KB)")


@db_cmd.command("validate")
@click.option("--db-path", default=None, help="Database file path (default: configured DB_PATH)")
@click.option("--pre", default=None, help="Pre-migration snapshot file (for diff mode)")
@click.option("--post", default=None, help="Post-migration snapshot file (for diff mode)")
@click.option("--output", default=None, help="Write snapshot JSON to file (snapshot mode)")
def db_validate(db_path, pre, post, output):
    """Validate database state before/after migration.

    Snapshot mode (default): capture DB metrics to JSON.
    Diff mode (--pre + --post): compare two snapshots and report anomalies.
    """
    if pre and post:
        _validate_diff(pre, post)
    else:
        _validate_snapshot(db_path, output)


def _validate_snapshot(db_path, output):
    import baker.config

    target = db_path or str(baker.config.DB_PATH)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    with get_db(target) as conn:
        def _json_query(sql):
            cur = conn.execute(sql)
            rows = cur.fetchall()
            cols = [d[0] for d in cur.description]
            return [dict(zip(cols, r)) for r in rows]

        def _scalar(sql):
            row = conn.execute(sql).fetchone()
            return row[0] if row else None

        row_counts = _json_query(
            "SELECT 'events' AS tbl, COUNT(*) AS cnt FROM events WHERE deleted_at IS NULL "
            "UNION ALL SELECT 'orders', COUNT(*) FROM orders "
            "UNION ALL SELECT 'order_items', COUNT(*) FROM order_items "
            "UNION ALL SELECT 'products', COUNT(*) FROM products "
            "UNION ALL SELECT 'inventory', COUNT(*) FROM inventory "
            "UNION ALL SELECT 'stock_lots', COUNT(*) FROM stock_lots "
            "UNION ALL SELECT 'inventory_items', COUNT(*) FROM inventory_items "
            "UNION ALL SELECT 'journal_entries', COUNT(*) FROM journal_entries "
            "UNION ALL SELECT 'journal_lines', COUNT(*) FROM journal_lines "
            "UNION ALL SELECT 'payment_transactions', COUNT(*) FROM payment_transactions WHERE invalidated_at IS NULL "
            "UNION ALL SELECT 'customers', COUNT(*) FROM customers "
            "UNION ALL SELECT 'reconciliation_sessions', COUNT(*) FROM reconciliation_sessions "
            "UNION ALL SELECT 'reconciliation_lines', COUNT(*) FROM reconciliation_lines "
            "UNION ALL SELECT 'staff', COUNT(*) FROM staff "
            "UNION ALL SELECT 'photos', COUNT(*) FROM photos "
            "UNION ALL SELECT 'knowledge_entries', COUNT(*) FROM knowledge_entries "
            "UNION ALL SELECT 'checklist_entries', COUNT(*) FROM checklist_entries "
            "UNION ALL SELECT 'cost_history', COUNT(*) FROM cost_history"
        )

        orders_total = _json_query(
            "SELECT COUNT(*) AS order_count, COALESCE(SUM(total_price), 0) AS total_value FROM orders"
        )
        orders_by_year = _json_query(
            "SELECT strftime('%Y', created_at) AS year, COUNT(*) AS order_count, COALESCE(SUM(total_price), 0) AS total_value FROM orders GROUP BY year ORDER BY year"
        )
        orders_by_month = _json_query(
            "SELECT strftime('%Y-%m', created_at) AS month, COUNT(*) AS order_count, COALESCE(SUM(total_price), 0) AS total_value FROM orders GROUP BY month ORDER BY month"
        )
        delivered_orders = _json_query(
            "SELECT COUNT(*) AS delivered_count, COALESCE(SUM(total_price), 0) AS delivered_value FROM orders WHERE status IN ('delivered', 'completed')"
        )
        total_deposits = _scalar(
            "SELECT COALESCE(SUM(amount), 0) FROM payment_transactions WHERE invalidated_at IS NULL"
        ) or 0
        total_expenses = _scalar(
            "SELECT COALESCE(SUM(json_extract(data, '$.amount_vnd')), 0) FROM events WHERE type = 'expense' AND deleted_at IS NULL"
        ) or 0

        stock_qty = _scalar("SELECT COALESCE(SUM(remaining_qty), 0) FROM stock_lots") or 0
        available_items = _scalar("SELECT COUNT(*) FROM inventory_items WHERE status = 'available'") or 0

        trial_balance = _json_query(
            "SELECT a.code, a.name, COALESCE(SUM(jl.debit), 0) AS total_debit, COALESCE(SUM(jl.credit), 0) AS total_credit "
            "FROM accounts a LEFT JOIN journal_lines jl ON jl.account_id = a.id GROUP BY a.id ORDER BY a.code"
        )
        order_status_dist = _json_query("SELECT status, COUNT(*) AS cnt FROM orders GROUP BY status")
        event_type_dist = _json_query("SELECT type, COUNT(*) AS cnt FROM events WHERE deleted_at IS NULL GROUP BY type")
        journal_totals = _json_query(
            "SELECT COALESCE(SUM(debit), 0) AS total_debit, COALESCE(SUM(credit), 0) AS total_credit FROM journal_lines"
        )
        customer_count = _scalar("SELECT COUNT(*) FROM customers") or 0
        active_product_count = _scalar("SELECT COUNT(*) FROM products WHERE active = 1") or 0

        # Metric 9: Customer-Order Linkage Health
        customers_without_orders = _scalar(
            "SELECT COUNT(*) FROM customers c WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id)"
        ) or 0
        orders_without_customer = _json_query(
            "SELECT status, COUNT(*) AS cnt FROM orders WHERE customer_id IS NULL GROUP BY status"
        )
        customer_year_mismatch = _scalar(
            "SELECT (SELECT COUNT(*) FROM customer_year_summary) - (SELECT COUNT(DISTINCT customer_id) FROM customer_year_summary) AS mismatch"
        ) or 0

        # Metric 10: COGS Coverage
        cogs_coverage = _json_query(
            "SELECT CASE WHEN oi.cost_at_sale > 0 THEN 'explicit' ELSE 'baseline' END AS cost_type, "
            "COUNT(*) AS item_count, ROUND(AVG(oi.unit_price * 0.3)) AS avg_baseline_estimate, "
            "ROUND(AVG(oi.cost_at_sale)) AS avg_actual_cost "
            "FROM order_items oi JOIN orders o ON o.id = oi.order_id "
            "WHERE o.status IN ('delivered', 'completed') GROUP BY 1"
        )
        cogs_journal = _json_query(
            "SELECT COUNT(*) AS cogs_line_count, COALESCE(SUM(jl.debit), 0) AS cogs_total_debit "
            "FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id WHERE a.code = '5900'"
        )

        # Metric 11: Phone Coverage
        customers_with_phones = _scalar(
            "SELECT COUNT(*) FROM customers c WHERE EXISTS (SELECT 1 FROM customer_phones cp WHERE cp.customer_id = c.id)"
        ) or 0
        customers_without_phones = _scalar(
            "SELECT COUNT(*) FROM customers c WHERE NOT EXISTS (SELECT 1 FROM customer_phones cp WHERE cp.customer_id = c.id)"
        ) or 0
        customers_legacy_phone = _scalar(
            "SELECT COUNT(*) FROM customers WHERE phone IS NOT NULL AND phone != ''"
        ) or 0

        # Metric 12: Payment Reconciliation
        payment_tx_count = _scalar(
            "SELECT COUNT(*) FROM payment_transactions WHERE invalidated_at IS NULL"
        ) or 0
        order_count_for_payment = _scalar("SELECT COUNT(*) FROM orders") or 0
        deposit_accounts = _json_query(
            "SELECT a.code, a.name, COALESCE(SUM(jl.credit), 0) AS total_credit "
            "FROM accounts a LEFT JOIN journal_lines jl ON jl.account_id = a.id "
            "WHERE a.code IN ('1200', '1201') GROUP BY a.id ORDER BY a.code"
        )

        schema_version = _scalar("SELECT COALESCE(MAX(version), 0) FROM schema_version") or 0
        integrity = _scalar("PRAGMA integrity_check") or "ok"

    snapshot = {
        "timestamp": ts,
        "db_path": target,
        "schema_version": schema_version,
        "integrity_check": integrity,
        "metrics": {
            "row_counts": row_counts,
            "financial": {
                "orders_total": orders_total,
                "orders_by_year": orders_by_year,
                "orders_by_month": orders_by_month,
                "delivered_orders": delivered_orders,
                "total_deposits": float(total_deposits),
                "total_expenses": float(total_expenses),
            },
            "stock": {
                "total_remaining_qty": float(stock_qty),
                "available_inventory_items": int(available_items),
            },
            "trial_balance": trial_balance,
            "order_status_distribution": order_status_dist,
            "event_type_distribution": event_type_dist,
            "journal_totals": journal_totals,
            "customer_count": int(customer_count),
            "active_product_count": int(active_product_count),
            "customer_order_linkage": {
                "customers_without_orders": int(customers_without_orders),
                "orders_without_customer": orders_without_customer,
                "customer_year_summary_mismatch": int(customer_year_mismatch),
            },
            "cogs_coverage": {
                "cost_type_breakdown": cogs_coverage,
                "cogs_journal": cogs_journal,
            },
            "phone_coverage": {
                "customers_with_phones": int(customers_with_phones),
                "customers_without_phones": int(customers_without_phones),
                "customers_legacy_phone": int(customers_legacy_phone),
            },
            "payment_reconciliation": {
                "payment_transactions_count": int(payment_tx_count),
                "orders_count": int(order_count_for_payment),
                "deposit_accounts": deposit_accounts,
            },
        },
    }

    result = json.dumps(snapshot, indent=2, ensure_ascii=False)
    if output:
        Path(output).write_text(result, encoding="utf-8")
        click.echo(f"Snapshot saved to {output}")
    else:
        click.echo(result)


def _validate_diff(pre_path, post_path):
    pre = json.loads(Path(pre_path).read_text(encoding="utf-8"))
    post = json.loads(Path(post_path).read_text(encoding="utf-8"))

    findings = []

    def flag(severity, msg):
        findings.append((severity, msg))
        click.echo(f"{severity}: {msg}", err=True)

    pre_sv = pre.get("schema_version", 0)
    post_sv = post.get("schema_version", 0)
    click.echo(f"Schema version: {pre_sv} -> {post_sv}")
    if post_sv < pre_sv:
        flag("Critical", f"Schema version decreased: {pre_sv} -> {post_sv}")

    pre_ic = pre.get("integrity_check", "ok")
    post_ic = post.get("integrity_check", "ok")
    click.echo(f"Integrity check: {pre_ic} -> {post_ic}")
    if post_ic != "ok":
        flag("Critical", f"Post-migration integrity check failed: {post_ic}")

    m_pre = pre.get("metrics", {})
    m_post = post.get("metrics", {})

    # Row counts
    pre_rc = {r["tbl"]: r["cnt"] for r in m_pre.get("row_counts", [])}
    post_rc = {r["tbl"]: r["cnt"] for r in m_post.get("row_counts", [])}
    click.echo("\n=== Row Counts ===")
    all_tables = sorted(set(list(pre_rc.keys()) + list(post_rc.keys())))
    for tbl in all_tables:
        before = pre_rc.get(tbl, 0)
        after = post_rc.get(tbl, 0)
        delta = after - before
        flag_str = ""
        if after < before:
            pct = (before - after) / before * 100 if before > 0 else 0
            if pct > 10:
                flag_str = f" [Critical: decrease >10%]"
                flag("Critical", f"Row count decreased >10% for {tbl}: {before} -> {after} ({pct:.1f}%)")
            else:
                flag_str = " [Major: decrease]"
                flag("Major", f"Row count decreased for {tbl}: {before} -> {after}")
        click.echo(f"  {tbl}: {before} -> {after} ({delta:+d}){flag_str}")

    # Financial
    click.echo("\n=== Financial ===")
    fin_pre = m_pre.get("financial", {})
    fin_post = m_post.get("financial", {})

    ot_pre = fin_pre.get("orders_total", [{}])
    ot_post = fin_post.get("orders_total", [{}])
    if ot_pre and ot_post:
        oc_pre = ot_pre[0].get("order_count", 0) if isinstance(ot_pre, list) else ot_pre.get("order_count", 0)
        oc_post = ot_post[0].get("order_count", 0) if isinstance(ot_post, list) else ot_post.get("order_count", 0)
        ov_pre = ot_pre[0].get("total_value", 0) if isinstance(ot_pre, list) else ot_pre.get("total_value", 0)
        ov_post = ot_post[0].get("total_value", 0) if isinstance(ot_post, list) else ot_post.get("total_value", 0)
        click.echo(f"  Orders total: {oc_pre} ({ov_pre:,.0f}) -> {oc_post} ({ov_post:,.0f})")
        if oc_post < oc_pre:
            flag("Major", f"Order count decreased: {oc_pre} -> {oc_post}")
        if ov_post < ov_pre - 0.01:
            flag("Major", f"Order total value decreased: {ov_pre:,.0f} -> {ov_post:,.0f}")

    do_pre = fin_pre.get("delivered_orders", [{}])
    do_post = fin_post.get("delivered_orders", [{}])
    if do_pre and do_post:
        dc_pre = do_pre[0].get("delivered_count", 0) if isinstance(do_pre, list) else do_pre.get("delivered_count", 0)
        dc_post = do_post[0].get("delivered_count", 0) if isinstance(do_post, list) else do_post.get("delivered_count", 0)
        dv_pre = do_pre[0].get("delivered_value", 0) if isinstance(do_pre, list) else do_pre.get("delivered_value", 0)
        dv_post = do_post[0].get("delivered_value", 0) if isinstance(do_post, list) else do_post.get("delivered_value", 0)
        click.echo(f"  Delivered orders: {dc_pre} ({dv_pre:,.0f}) -> {dc_post} ({dv_post:,.0f})")
        if dc_post < dc_pre:
            flag("Major", f"Delivered order count decreased: {dc_pre} -> {dc_post}")
        if dv_post < dv_pre - 0.01:
            flag("Major", f"Delivered order value decreased: {dv_pre:,.0f} -> {dv_post:,.0f}")

    dep_pre = fin_pre.get("total_deposits", 0)
    dep_post = fin_post.get("total_deposits", 0)
    click.echo(f"  Total deposits: {dep_pre:,.0f} -> {dep_post:,.0f}")
    if dep_post < dep_pre - 0.01:
        flag("Major", f"Total deposits decreased: {dep_pre:,.0f} -> {dep_post:,.0f}")

    exp_pre = fin_pre.get("total_expenses", 0)
    exp_post = fin_post.get("total_expenses", 0)
    click.echo(f"  Total expenses: {exp_pre:,.0f} -> {exp_post:,.0f}")
    if exp_post < exp_pre - 0.01:
        flag("Major", f"Total expenses decreased: {exp_pre:,.0f} -> {exp_post:,.0f}")

    # Stock
    click.echo("\n=== Stock Position ===")
    stk_pre = m_pre.get("stock", {})
    stk_post = m_post.get("stock", {})
    sq_pre = stk_pre.get("total_remaining_qty", 0)
    sq_post = stk_post.get("total_remaining_qty", 0)
    ai_pre = stk_pre.get("available_inventory_items", 0)
    ai_post = stk_post.get("available_inventory_items", 0)
    click.echo(f"  Stock remaining qty: {sq_pre} -> {sq_post}")
    click.echo(f"  Available inventory items: {ai_pre} -> {ai_post}")
    if sq_post < sq_pre - 0.001:
        flag("Major", f"Stock remaining qty decreased: {sq_pre} -> {sq_post}")
    if ai_post < ai_pre:
        flag("Major", f"Available inventory items decreased: {ai_pre} -> {ai_post}")

    # Trial balance
    click.echo("\n=== Trial Balance ===")
    tb_pre = {r["code"]: r for r in m_pre.get("trial_balance", [])}
    tb_post = {r["code"]: r for r in m_post.get("trial_balance", [])}
    all_codes = sorted(set(list(tb_pre.keys()) + list(tb_post.keys())))
    for code in all_codes:
        pre_r = tb_pre.get(code, {"total_debit": 0, "total_credit": 0})
        post_r = tb_post.get(code, {"total_debit": 0, "total_credit": 0})
        d_delta = post_r["total_debit"] - pre_r["total_debit"]
        c_delta = post_r["total_credit"] - pre_r["total_credit"]
        drift = abs(d_delta) + abs(c_delta)
        flag_str = ""
        if drift > 100:
            flag_str = f" [Critical: drift {drift:,.2f}]"
            flag("Critical", f"Account {code} balance drift >100 VND: debit {pre_r['total_debit']:,.0f}->{post_r['total_debit']:,.0f}, credit {pre_r['total_credit']:,.0f}->{post_r['total_credit']:,.0f}")
        elif drift > 0.01:
            flag_str = f" [Major: drift {drift:,.2f}]"
            flag("Major", f"Account {code} balance drift: debit {pre_r['total_debit']:,.0f}->{post_r['total_debit']:,.0f}, credit {pre_r['total_credit']:,.0f}->{post_r['total_credit']:,.0f}")
        click.echo(f"  {code}: debit {pre_r['total_debit']:,.0f}->{post_r['total_debit']:,.0f} credit {pre_r['total_credit']:,.0f}->{post_r['total_credit']:,.0f}{flag_str}")

    # Order status distribution
    click.echo("\n=== Order Status Distribution ===")
    os_pre = {r["status"]: r["cnt"] for r in m_pre.get("order_status_distribution", [])}
    os_post = {r["status"]: r["cnt"] for r in m_post.get("order_status_distribution", [])}
    all_statuses = sorted(set(list(os_pre.keys()) + list(os_post.keys())))
    for st in all_statuses:
        before = os_pre.get(st, 0)
        after = os_post.get(st, 0)
        delta = after - before
        flag_str = ""
        if after < before:
            flag_str = " [Major: decrease]"
            flag("Major", f'Order status "{st}" count decreased: {before} -> {after}')
        click.echo(f"  {st}: {before} -> {after} ({delta:+d}){flag_str}")

    # Event type distribution
    click.echo("\n=== Event Type Distribution ===")
    ev_pre = {r["type"]: r["cnt"] for r in m_pre.get("event_type_distribution", [])}
    ev_post = {r["type"]: r["cnt"] for r in m_post.get("event_type_distribution", [])}
    all_types = sorted(set(list(ev_pre.keys()) + list(ev_post.keys())))
    for et in all_types:
        before = ev_pre.get(et, 0)
        after = ev_post.get(et, 0)
        delta = after - before
        flag_str = ""
        if after < before:
            flag_str = " [Major: decrease]"
            flag("Major", f'Event type "{et}" count decreased: {before} -> {after}')
        click.echo(f"  {et}: {before} -> {after} ({delta:+d}){flag_str}")

    # Journal totals
    click.echo("\n=== Journal Totals ===")
    jt_pre = m_pre.get("journal_totals", [{}])
    jt_post = m_post.get("journal_totals", [{}])
    if jt_pre and jt_post:
        jd_pre = jt_pre[0].get("total_debit", 0) if isinstance(jt_pre, list) else jt_pre.get("total_debit", 0)
        jc_pre = jt_pre[0].get("total_credit", 0) if isinstance(jt_pre, list) else jt_pre.get("total_credit", 0)
        jd_post = jt_post[0].get("total_debit", 0) if isinstance(jt_post, list) else jt_post.get("total_debit", 0)
        jc_post = jt_post[0].get("total_credit", 0) if isinstance(jt_post, list) else jt_post.get("total_credit", 0)
        imbalance_pre = abs(jd_pre - jc_pre)
        imbalance_post = abs(jd_post - jc_post)
        click.echo(f"  Debit: {jd_pre:,.0f} -> {jd_post:,.0f}")
        click.echo(f"  Credit: {jc_pre:,.0f} -> {jc_post:,.0f}")
        click.echo(f"  Imbalance: {imbalance_pre:,.2f} -> {imbalance_post:,.2f}")
        if imbalance_post > 100:
            flag("Critical", f"Journal imbalance >100 VND: {imbalance_post:,.2f}")
        elif imbalance_post > 0.01:
            flag("Major", f"Journal imbalance >0.01 VND: {imbalance_post:,.2f}")

    # Counts
    click.echo("\n=== Counts ===")
    cc_pre = m_pre.get("customer_count", 0)
    cc_post = m_post.get("customer_count", 0)
    ap_pre = m_pre.get("active_product_count", 0)
    ap_post = m_post.get("active_product_count", 0)
    click.echo(f"  Customers: {cc_pre} -> {cc_post}")
    click.echo(f"  Active products: {ap_pre} -> {ap_post}")
    if cc_post < cc_pre:
        flag("Major", f"Customer count decreased: {cc_pre} -> {cc_post}")
    if ap_post < ap_pre:
        flag("Major", f"Active product count decreased: {ap_pre} -> {ap_post}")

    # Metric 9: Customer-Order Linkage Health
    click.echo("\n=== Customer-Order Linkage Health ===")
    col_pre = m_pre.get("customer_order_linkage", {})
    col_post = m_post.get("customer_order_linkage", {})
    cuwo_pre = col_pre.get("customers_without_orders", 0)
    cuwo_post = col_post.get("customers_without_orders", 0)
    click.echo(f"  Customers without orders: {cuwo_pre} -> {cuwo_post}")
    if cuwo_post > cuwo_pre:
        flag("Minor", f"Customers without orders increased: {cuwo_pre} -> {cuwo_post}")

    owc_pre = {r["status"]: r["cnt"] for r in col_pre.get("orders_without_customer", [])}
    owc_post = {r["status"]: r["cnt"] for r in col_post.get("orders_without_customer", [])}
    all_owc_statuses = sorted(set(list(owc_pre.keys()) + list(owc_post.keys())))
    for st in all_owc_statuses:
        before = owc_pre.get(st, 0)
        after = owc_post.get(st, 0)
        delta = after - before
        flag_str = ""
        if after > before:
            flag_str = " [Minor: increase]"
            flag("Minor", f"Orders without customer_id ({st}) increased: {before} -> {after}")
        click.echo(f"  Orders without customer ({st}): {before} -> {after} ({delta:+d}){flag_str}")

    cys_pre = col_pre.get("customer_year_summary_mismatch", 0)
    cys_post = col_post.get("customer_year_summary_mismatch", 0)
    click.echo(f"  Customer year summary mismatch: {cys_pre} -> {cys_post}")
    if cys_post != 0:
        flag("Major", f"Customer year summary mismatch: {cys_post}")

    # Metric 10: COGS Coverage
    click.echo("\n=== COGS Coverage ===")
    cogs_pre = m_pre.get("cogs_coverage", {})
    cogs_post = m_post.get("cogs_coverage", {})
    ctb_pre = {r["cost_type"]: r for r in cogs_pre.get("cost_type_breakdown", [])}
    ctb_post = {r["cost_type"]: r for r in cogs_post.get("cost_type_breakdown", [])}
    for ct in ["explicit", "baseline"]:
        pre_r = ctb_pre.get(ct, {"item_count": 0, "avg_baseline_estimate": 0, "avg_actual_cost": 0})
        post_r = ctb_post.get(ct, {"item_count": 0, "avg_baseline_estimate": 0, "avg_actual_cost": 0})
        click.echo(f"  COGS {ct}: {pre_r['item_count']} items -> {post_r['item_count']} items")
        if post_r["item_count"] < pre_r["item_count"]:
            flag("Major", f"COGS {ct} item count decreased: {pre_r['item_count']} -> {post_r['item_count']}")

    cj_pre = cogs_pre.get("cogs_journal", [{}])
    cj_post = cogs_post.get("cogs_journal", [{}])
    if cj_pre and cj_post:
        clc_pre = cj_pre[0].get("cogs_line_count", 0) if isinstance(cj_pre, list) else cj_pre.get("cogs_line_count", 0)
        clc_post = cj_post[0].get("cogs_line_count", 0) if isinstance(cj_post, list) else cj_post.get("cogs_line_count", 0)
        ctd_pre = cj_pre[0].get("cogs_total_debit", 0) if isinstance(cj_pre, list) else cj_pre.get("cogs_total_debit", 0)
        ctd_post = cj_post[0].get("cogs_total_debit", 0) if isinstance(cj_post, list) else cj_post.get("cogs_total_debit", 0)
        click.echo(f"  COGS journal lines: {clc_pre} -> {clc_post}")
        click.echo(f"  COGS total debit: {ctd_pre:,.0f} -> {ctd_post:,.0f}")
        if clc_post == 0:
            flag("Info", "COGS journal lines = 0 (journal backfill may not have been run)")
        if ctd_post < ctd_pre - 0.01:
            flag("Major", f"COGS total debit decreased: {ctd_pre:,.0f} -> {ctd_post:,.0f}")

    # Metric 11: Phone Coverage
    click.echo("\n=== Phone Coverage ===")
    ph_pre = m_pre.get("phone_coverage", {})
    ph_post = m_post.get("phone_coverage", {})
    cwp_pre = ph_pre.get("customers_with_phones", 0)
    cwp_post = ph_post.get("customers_with_phones", 0)
    cwop_pre = ph_pre.get("customers_without_phones", 0)
    cwop_post = ph_post.get("customers_without_phones", 0)
    clp_pre = ph_pre.get("customers_legacy_phone", 0)
    clp_post = ph_post.get("customers_legacy_phone", 0)
    click.echo(f"  Customers with phones: {cwp_pre} -> {cwp_post}")
    click.echo(f"  Customers without phones: {cwop_pre} -> {cwop_post}")
    click.echo(f"  Customers with legacy phone: {clp_pre} -> {clp_post}")
    total_cust = cc_post if cc_post > 0 else 1
    phone_pct = cwp_post / total_cust * 100
    click.echo(f"  Phone coverage rate: {phone_pct:.1f}%")
    if cwop_post > cwop_pre:
        flag("Info", f"Customers without phones increased: {cwop_pre} -> {cwop_post}")

    # Metric 12: Payment Reconciliation
    click.echo("\n=== Payment Reconciliation ===")
    pay_pre = m_pre.get("payment_reconciliation", {})
    pay_post = m_post.get("payment_reconciliation", {})
    ptx_pre = pay_pre.get("payment_transactions_count", 0)
    ptx_post = pay_post.get("payment_transactions_count", 0)
    ocp_pre = pay_pre.get("orders_count", 0)
    ocp_post = pay_post.get("orders_count", 0)
    click.echo(f"  Payment transactions: {ptx_pre} -> {ptx_post}")
    click.echo(f"  Orders: {ocp_pre} -> {ocp_post}")
    if ocp_post > 0:
        ratio_pre = ptx_pre / ocp_pre if ocp_pre > 0 else 0
        ratio_post = ptx_post / ocp_post
        click.echo(f"  Payment-to-order ratio: {ratio_pre:.2f} -> {ratio_post:.2f}")
        if ratio_post < ratio_pre - 0.1:
            flag("Info", f"Payment-to-order ratio decreased: {ratio_pre:.2f} -> {ratio_post:.2f}")

    da_pre = {r["code"]: r for r in pay_pre.get("deposit_accounts", [])}
    da_post = {r["code"]: r for r in pay_post.get("deposit_accounts", [])}
    all_da_codes = sorted(set(list(da_pre.keys()) + list(da_post.keys())))
    for code in all_da_codes:
        pre_r = da_pre.get(code, {"total_credit": 0})
        post_r = da_post.get(code, {"total_credit": 0})
        delta = post_r["total_credit"] - pre_r["total_credit"]
        flag_str = ""
        if abs(delta) > 0.01:
            flag_str = f" [Major: drift {delta:,.2f}]"
            flag("Major", f"Deposit account {code} credit drift: {pre_r['total_credit']:,.0f} -> {post_r['total_credit']:,.0f}")
        click.echo(f"  {code}: credit {pre_r['total_credit']:,.0f} -> {post_r['total_credit']:,.0f}{flag_str}")

    # Summary
    click.echo()
    critical_count = sum(1 for s, _ in findings if s == "Critical")
    major_count = sum(1 for s, _ in findings if s == "Major")
    minor_count = sum(1 for s, _ in findings if s == "Minor")
    info_count = sum(1 for s, _ in findings if s == "Info")
    total = len(findings)

    click.echo(f"Findings: {total} total (Critical={critical_count}, Major={major_count}, Minor={minor_count}, Info={info_count})")

    if critical_count > 0:
        click.echo(f"RESULT: {critical_count} Critical, {major_count} Major, {minor_count} Minor, {info_count} Info", err=True)
        raise SystemExit(3)
    elif major_count > 0:
        click.echo(f"RESULT: {major_count} Major, {minor_count} Minor, {info_count} Info", err=True)
        raise SystemExit(2)
    elif minor_count > 0 or info_count > 0:
        click.echo(f"RESULT: {minor_count} Minor, {info_count} Info", err=True)
        raise SystemExit(1)
    else:
        click.echo("RESULT: No anomalies detected")
