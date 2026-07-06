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

    anomalies = 0

    def flag(msg):
        nonlocal anomalies
        anomalies += 1
        click.echo(f"ANOMALY: {msg}", err=True)

    pre_sv = pre.get("schema_version", 0)
    post_sv = post.get("schema_version", 0)
    click.echo(f"Schema version: {pre_sv} -> {post_sv}")
    if post_sv < pre_sv:
        flag(f"Schema version decreased: {pre_sv} -> {post_sv}")

    pre_ic = pre.get("integrity_check", "ok")
    post_ic = post.get("integrity_check", "ok")
    click.echo(f"Integrity check: {pre_ic} -> {post_ic}")
    if post_ic != "ok":
        flag(f"Post-migration integrity check failed: {post_ic}")

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
            flag_str = " [ANOMALY: decrease]"
            flag(f"Row count decreased for {tbl}: {before} -> {after}")
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
            flag(f"Order count decreased: {oc_pre} -> {oc_post}")
        if ov_post < ov_pre - 0.01:
            flag(f"Order total value decreased: {ov_pre:,.0f} -> {ov_post:,.0f}")

    do_pre = fin_pre.get("delivered_orders", [{}])
    do_post = fin_post.get("delivered_orders", [{}])
    if do_pre and do_post:
        dc_pre = do_pre[0].get("delivered_count", 0) if isinstance(do_pre, list) else do_pre.get("delivered_count", 0)
        dc_post = do_post[0].get("delivered_count", 0) if isinstance(do_post, list) else do_post.get("delivered_count", 0)
        dv_pre = do_pre[0].get("delivered_value", 0) if isinstance(do_pre, list) else do_pre.get("delivered_value", 0)
        dv_post = do_post[0].get("delivered_value", 0) if isinstance(do_post, list) else do_post.get("delivered_value", 0)
        click.echo(f"  Delivered orders: {dc_pre} ({dv_pre:,.0f}) -> {dc_post} ({dv_post:,.0f})")
        if dc_post < dc_pre:
            flag(f"Delivered order count decreased: {dc_pre} -> {dc_post}")
        if dv_post < dv_pre - 0.01:
            flag(f"Delivered order value decreased: {dv_pre:,.0f} -> {dv_post:,.0f}")

    dep_pre = fin_pre.get("total_deposits", 0)
    dep_post = fin_post.get("total_deposits", 0)
    click.echo(f"  Total deposits: {dep_pre:,.0f} -> {dep_post:,.0f}")
    if dep_post < dep_pre - 0.01:
        flag(f"Total deposits decreased: {dep_pre:,.0f} -> {dep_post:,.0f}")

    exp_pre = fin_pre.get("total_expenses", 0)
    exp_post = fin_post.get("total_expenses", 0)
    click.echo(f"  Total expenses: {exp_pre:,.0f} -> {exp_post:,.0f}")
    if exp_post < exp_pre - 0.01:
        flag(f"Total expenses decreased: {exp_pre:,.0f} -> {exp_post:,.0f}")

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
        flag(f"Stock remaining qty decreased: {sq_pre} -> {sq_post}")
    if ai_post < ai_pre:
        flag(f"Available inventory items decreased: {ai_pre} -> {ai_post}")

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
        if drift > 0.01:
            flag_str = f" [ANOMALY: drift {drift:,.2f}]"
            flag(
                f"Account {code} balance drift: debit {pre_r['total_debit']:,.0f}->{post_r['total_debit']:,.0f}, "
                f"credit {pre_r['total_credit']:,.0f}->{post_r['total_credit']:,.0f}"
            )
        click.echo(
            f"  {code}: debit {pre_r['total_debit']:,.0f}->{post_r['total_debit']:,.0f} "
            f"credit {pre_r['total_credit']:,.0f}->{post_r['total_credit']:,.0f}{flag_str}"
        )

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
            flag_str = " [ANOMALY: decrease]"
            flag(f'Order status "{st}" count decreased: {before} -> {after}')
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
            flag_str = " [ANOMALY: decrease]"
            flag(f'Event type "{et}" count decreased: {before} -> {after}')
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
        if imbalance_post > 0.01:
            flag(f"Journal imbalance > 0.01 VND: {imbalance_post:,.2f}")

    # Counts
    click.echo("\n=== Counts ===")
    cc_pre = m_pre.get("customer_count", 0)
    cc_post = m_post.get("customer_count", 0)
    ap_pre = m_pre.get("active_product_count", 0)
    ap_post = m_post.get("active_product_count", 0)
    click.echo(f"  Customers: {cc_pre} -> {cc_post}")
    click.echo(f"  Active products: {ap_pre} -> {ap_post}")
    if cc_post < cc_pre:
        flag(f"Customer count decreased: {cc_pre} -> {cc_post}")
    if ap_post < ap_pre:
        flag(f"Active product count decreased: {ap_pre} -> {ap_post}")

    click.echo()
    if anomalies > 0:
        click.echo(f"RESULT: {anomalies} anomaly(s) detected", err=True)
        raise SystemExit(1)
    else:
        click.echo("RESULT: No anomalies detected")
