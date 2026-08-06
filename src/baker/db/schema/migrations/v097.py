"""Migration v097: _migrate_v97_cash_drawer_breakdown_snapshot (DG-363 Phase 1).

Adds the ``cash_drawer_breakdown_snapshot`` table that stores the per-category
breakdown (8 categories) of a cash drawer at close time, and backfills
snapshots for all already-closed drawers from their linked 1101/2200 journal
lines (FR6, FR8).

Two changes, both idempotent (NFR2):

1. Create ``cash_drawer_breakdown_snapshot`` with columns ``id``,
   ``drawer_id`` (FK → cash_drawer), ``category`` TEXT, ``total_amount`` REAL,
   ``count`` INTEGER, ``created_at`` TEXT. A UNIQUE index on
   ``(drawer_id, category)`` makes the backfill idempotent — re-running on an
   already-migrated DB is a no-op (NFR2).

2. Backfill snapshots for all currently closed drawers. For each closed
   drawer, the backfill aggregates the signed 1101 movement of every linked
   journal entry by ``source_type`` into one of 8 canonical categories and
   inserts one row per category (FR8). Payment-transaction inflows on bus
   orders are split so the 2200-held shipping portion lands in the
   ``busShipping`` category and the remainder lands in ``sale`` (FR5). Drawers
   with no activity on a category still receive a zero row so the snapshot
   always has 8 rows per drawer (FR1). Bulk insert keeps the backfill under
   5 seconds for ≤ 10,000 drawers (NFR2).

This phase is schema + backfill only — no model, API, or Flutter code is
modified. Phase 2 wires ``save_breakdown_snapshot()`` into
``CashDrawer.close()`` / ``auto_close()`` and ``get_breakdown_snapshot()```
into ``/status`` / ``/history``.
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


CASH_DRAWER_BREAKDOWN_SNAPSHOT_SCHEMA = """
CREATE TABLE IF NOT EXISTS cash_drawer_breakdown_snapshot (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    drawer_id    INTEGER NOT NULL REFERENCES cash_drawer(id),
    category     TEXT NOT NULL,
    total_amount REAL NOT NULL DEFAULT 0,
    count        INTEGER NOT NULL DEFAULT 0,
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
);

CREATE INDEX IF NOT EXISTS idx_breakdown_snapshot_drawer
    ON cash_drawer_breakdown_snapshot(drawer_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_breakdown_snapshot_drawer_category
    ON cash_drawer_breakdown_snapshot(drawer_id, category);
"""

# Canonical 8 categories for the breakdown snapshot (FR1). Order is fixed so
# the UI can rely on a stable row order; ``busShipping`` and ``refund`` are
# the two new categories added by DG-363 (Phase 1 table only — Flutter UI
# lands in Phase 3).
BREAKDOWN_SNAPSHOT_CATEGORIES = (
    "sale",
    "refund",
    "expense",
    "cashIn",
    "cashOut",
    "open",
    "close",
    "busShipping",
)


def _migrate_v97_cash_drawer_breakdown_snapshot(conn):
    """Create the snapshot table and backfill closed drawers (DG-363 Phase 1).

    Idempotent (NFR2): ``CREATE TABLE IF NOT EXISTS`` makes the schema step a
    no-op on re-run, and the backfill uses ``INSERT OR IGNORE`` against the
    UNIQUE(drawer_id, category) index so drawers that already have snapshot
    rows are skipped. Re-running v097 on an already-migrated DB is a no-op.
    """
    # 1. Create the snapshot table (FR6).
    conn.executescript(CASH_DRAWER_BREAKDOWN_SNAPSHOT_SCHEMA)

    # 2. Backfill snapshots for already-closed drawers (FR8). Only closed
    #    drawers that do not yet have any snapshot row are considered; the
    #    UNIQUE(drawer_id, category) index plus INSERT OR IGNORE keeps this
    #    idempotent on re-run (NFR2).
    closed_drawer_rows = conn.execute(
        "SELECT id FROM cash_drawer WHERE status = 'closed' "
        "AND id NOT IN (SELECT DISTINCT drawer_id FROM cash_drawer_breakdown_snapshot)"
    ).fetchall()
    if not closed_drawer_rows:
        return

    closed_drawer_ids = [int(r["id"]) for r in closed_drawer_rows]
    placeholders = ",".join("?" for _ in closed_drawer_ids)

    # Aggregate per linked journal entry: the signed 1101 movement (debit -
    # credit) is the cash impact on the drawer; the net 2200 credit (credit -
    # debit) is the bus-shipping portion held for the order. Grouping by
    # (drawer, je.id, source_type) collapses multi-line entries to one row
    # with separate 1101 and 2200 totals so the bus-shipping split can be
    # applied per entry (FR5).
    entry_totals = conn.execute(
        f"""
        SELECT
            cdje.cash_drawer_id AS drawer_id,
            je.id               AS je_id,
            je.source_type      AS source_type,
            COALESCE(SUM(CASE WHEN a.code = '1101' THEN jl.debit - jl.credit ELSE 0 END), 0) AS net_1101,
            COALESCE(SUM(CASE WHEN a.code = '2200' THEN jl.credit - jl.debit ELSE 0 END), 0) AS held_2200
        FROM cash_drawer_journal_entries cdje
        JOIN journal_entries je ON je.id = cdje.journal_entry_id
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        JOIN accounts a ON a.id = jl.account_id AND a.code IN ('1101', '2200')
        WHERE cdje.cash_drawer_id IN ({placeholders})
        GROUP BY cdje.cash_drawer_id, je.id, je.source_type
        """,
        closed_drawer_ids,
    ).fetchall()

    # Build per-(drawer, category) totals. Every closed drawer gets all 8
    # categories even when there is no activity so the snapshot always has
    # 8 rows (FR1/FR6).
    snapshot: dict[int, dict[str, tuple[float, int]]] = {
        did: {cat: (0.0, 0) for cat in BREAKDOWN_SNAPSHOT_CATEGORIES}
        for did in closed_drawer_ids
    }

    for row in entry_totals:
        did = int(row["drawer_id"])
        source_type = row["source_type"] or ""
        net_1101 = float(row["net_1101"] or 0)
        held_2200 = float(row["held_2200"] or 0)
        if did not in snapshot:
            continue

        # CQ-1 (DG-363 review-auto cycle 1): the source_type → breakdown
        # category classification below is triplicated. The same mapping
        # exists in two other files and MUST be kept in sync:
        #   - src/baker/models/cash_drawer.py: CashDrawer._aggregate_breakdown
        #     (the live-aggregation path used at close time and by /status)
        #   - app/lib/features/cash_drawer/widgets/
        #     cash_drawer_breakdown_card.dart: _categoryForType +
        #     aggregateCashDrawerBreakdown (the Flutter live-aggregation path)
        # Any change to a category mapping, ordering, fallback, or the
        # payment_transaction shipping split here MUST be mirrored in both
        # of those files so the backfilled snapshot, the live model
        # aggregation, and the client-side aggregation stay consistent.
        if source_type == "payment_transaction":
            if net_1101 < 0:
                _accumulate(snapshot[did], "refund", net_1101, 1)
            elif net_1101 > 0:
                # Split the bus-shipping portion (held in 2200) from the sale
                # portion so ``busShipping`` gets the held shipping and
                # ``sale`` gets the remainder (FR5). When the held amount
                # exceeds the 1101 inflow (defensive: should not happen but
                # guard against malformed data), clamp to the inflow so the
                # sale portion never goes negative.
                shipping = min(held_2200, net_1101) if held_2200 > 0 else 0.0
                sale_portion = net_1101 - shipping
                if sale_portion > 0:
                    _accumulate(snapshot[did], "sale", sale_portion, 1)
                else:
                    # sale_portion == 0: 1101 inflow fully consumed by held
                    # shipping. The sale category still counts the entry (at
                    # zero amount) so the count is not lost, matching the
                    # live aggregation in cash_drawer.py
                    # (CashDrawer._aggregate_breakdown). CQ-2 (DG-363
                    # review-auto cycle 1): previously an `elif sale_portion
                    # != 0` branch which was unreachable (sale_portion >= 0
                    # by construction); changed to `else` so the zero-amount
                    # accumulation actually executes as documented.
                    _accumulate(snapshot[did], "sale", sale_portion, 1)
                if shipping > 0:
                    _accumulate(snapshot[did], "busShipping", shipping, 1)
            # net_1101 == 0: no cash impact, skip (no 1101 line existed).
        elif source_type == "expense":
            _accumulate(snapshot[did], "expense", net_1101, 1)
        elif source_type in ("cash_drawer_cash_in", "owner_capital"):
            _accumulate(snapshot[did], "cashIn", net_1101, 1)
        elif source_type in ("cash_drawer_cash_out", "cash_drawer_auto_transfer"):
            _accumulate(snapshot[did], "cashOut", net_1101, 1)
        elif source_type == "cash_drawer_open":
            _accumulate(snapshot[did], "open", net_1101, 1)
        elif source_type == "cash_drawer_close_adjust":
            _accumulate(snapshot[did], "close", net_1101, 1)
        else:
            # Unknown source types fold into ``sale`` so the row stays visible
            # (matches the Flutter ``_categoryForType`` fallback, FR7).
            _accumulate(snapshot[did], "sale", net_1101, 1)

    # 3. Bulk insert 8 rows per closed drawer (NFR2). INSERT OR IGNORE against
    #    the UNIQUE(drawer_id, category) index keeps this idempotent.
    from baker.utils.time import now_utc

    created_at = now_utc()
    rows_to_insert = []
    for did in closed_drawer_ids:
        for cat in BREAKDOWN_SNAPSHOT_CATEGORIES:
            total_amount, count = snapshot[did][cat]
            rows_to_insert.append((did, cat, total_amount, count, created_at))

    conn.executemany(
        "INSERT OR IGNORE INTO cash_drawer_breakdown_snapshot "
        "(drawer_id, category, total_amount, count, created_at) "
        "VALUES (?, ?, ?, ?, ?)",
        rows_to_insert,
    )


def _accumulate(bucket: dict, category: str, amount: float, count: int) -> None:
    """Add ``amount`` and ``count`` to the running total for ``category``."""
    prev_amount, prev_count = bucket[category]
    bucket[category] = (prev_amount + amount, prev_count + count)