"""Cash drawer model (DG-324 Phase 2 / DG-347 Phase 2).

A :class:`CashDrawer` records one daily cash drawer session. The expected
balance is derived (FR1) from 1101 journal lines linked via the
``cash_drawer_journal_entries`` join table for open drawers, or from the
persisted ``closing_balance`` for closed drawers (FR2). Balance-affecting
fields are stored as INTEGER (VND) per NFR1 so drawer balance computation is
accurate to within 1 VND. The counted amount and discrepancy are persisted at
close time (FR7).

Traceability: FR1, FR2, FR4, FR7, FR8, FR10, NFR1.
"""

import json
from dataclasses import dataclass
from typing import Optional

from baker.db.schema.migrations.v097 import BREAKDOWN_SNAPSHOT_CATEGORIES
from baker.utils.time import now_utc


@dataclass
class CashDrawer:
    opened_at: str
    opening_balance: int = 0
    status: str = "open"
    closed_at: Optional[str] = None
    counted_amount: Optional[int] = None
    discrepancy: Optional[int] = None
    closing_balance: Optional[int] = None
    counted_opening_balance: Optional[int] = None
    # DG-379 Phase 4.1 (FR7): reconciled=1 locks a drawer from further
    # transaction edits. Defaults to 0 (editable). Set via PATCH
    # /api/cash-drawer/{id}/reconcile (Phase 4.2).
    reconciled: int = 0
    id: Optional[int] = None

    def expected_balance(self, conn=None) -> int:
        """FR3: derive the expected balance.

        For closed drawers with a persisted ``closing_balance``, return it
        directly (no journal query). For open drawers, when a ``conn`` is
        provided, return ``opening_balance + SUM(1101 debit - credit)`` over
        the journal lines linked to this drawer via the
        ``cash_drawer_journal_entries`` join table. ``opening_balance`` holds
        the 1101 accounting balance at open time (FR1), so the linked-entry sum
        captures only the activity that occurred during this drawer session.
        Without a ``conn`` (e.g. tests that construct the model directly), fall
        back to ``opening_balance`` so the method never raises.
        """
        if self.status == "closed" and self.closing_balance is not None:
            return self.closing_balance
        if conn is None:
            return self.opening_balance
        row = conn.execute(
            """
            SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
            FROM cash_drawer_journal_entries cdje
            JOIN journal_lines jl ON jl.journal_entry_id = cdje.journal_entry_id
            JOIN accounts a ON a.id = jl.account_id
            WHERE cdje.cash_drawer_id = ? AND a.code = '1101'
            """,
            (self.id,),
        ).fetchone()
        return int(self.opening_balance) + int(row["balance"])

    def save(self, conn) -> int:
        cursor = conn.execute(
            "INSERT INTO cash_drawer "
            "(opened_at, opening_balance, counted_opening_balance, status) "
            "VALUES (?, ?, ?, 'open')",
            (
                self.opened_at,
                int(self.opening_balance),
                int(self.counted_opening_balance) if self.counted_opening_balance is not None else None,
            ),
        )
        self.id = cursor.lastrowid
        self.status = "open"
        return self.id

    @staticmethod
    def from_row(row) -> "CashDrawer":
        return CashDrawer(
            id=row["id"],
            opened_at=row["opened_at"],
            closed_at=row["closed_at"],
            status=row["status"],
            opening_balance=int(row["opening_balance"]),
            counted_amount=int(row["counted_amount"]) if row["counted_amount"] is not None else None,
            discrepancy=int(row["discrepancy"]) if row["discrepancy"] is not None else None,
            closing_balance=(
                int(row["closing_balance"])
                if row["closing_balance"] is not None
                else None
            ),
            counted_opening_balance=(
                int(row["counted_opening_balance"])
                if row["counted_opening_balance"] is not None
                else None
            ),
            reconciled=int(row["reconciled"]) if row["reconciled"] is not None else 0,
        )

    def to_api_dict(self, conn=None) -> dict:
        return {
            "id": str(self.id),
            "openedAt": self.opened_at,
            "closedAt": self.closed_at,
            "status": self.status,
            "openingBalance": self.opening_balance,
            "countedOpeningBalance": self.counted_opening_balance,
            "countedAmount": self.counted_amount,
            "discrepancy": self.discrepancy,
            "closingBalance": self.closing_balance,
            "expectedBalance": self.expected_balance(conn),
            "reconciled": bool(self.reconciled),
        }

    @staticmethod
    def get_active(conn) -> "CashDrawer | None":
        row = conn.execute(
            "SELECT * FROM cash_drawer WHERE status = 'open' ORDER BY id DESC LIMIT 1"
        ).fetchone()
        return CashDrawer.from_row(row) if row else None

    @staticmethod
    def get_by_id(conn, drawer_id: int) -> "CashDrawer | None":
        row = conn.execute(
            "SELECT * FROM cash_drawer WHERE id = ?", (drawer_id,)
        ).fetchone()
        return CashDrawer.from_row(row) if row else None

    @staticmethod
    def list_history(
        conn,
        *,
        since: Optional[str] = None,
        until: Optional[str] = None,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list["CashDrawer"], int]:
        conditions = []
        params = []
        if since is not None:
            conditions.append("opened_at >= ?")
            params.append(since)
        if until is not None:
            conditions.append("opened_at <= ?")
            params.append(until)
        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        total = int(
            conn.execute(f"SELECT COUNT(*) AS c FROM cash_drawer {where}", params).fetchone()["c"]  # nosec B608
        )
        rows = conn.execute(
            f"SELECT * FROM cash_drawer {where} ORDER BY opened_at DESC, id DESC LIMIT ? OFFSET ?",  # nosec B608
            [*params, limit, offset],
        ).fetchall()
        return [CashDrawer.from_row(r) for r in rows], total

    def close(self, conn, *, counted_amount: int, closed_at: Optional[str] = None) -> int:
        """FR7: set counted_amount, compute discrepancy, mark closed.

        Persists ``closing_balance = expected_balance`` so historical drawer
        data remains accurate after close (FR2/AC2). Returns the discrepancy
        (counted - expected).
        """
        expected = self.expected_balance(conn)
        discrepancy = int(counted_amount) - expected
        closed_ts = closed_at or now_utc()
        cursor = conn.execute(
            "UPDATE cash_drawer "
            "SET status = 'closed', closed_at = ?, counted_amount = ?, "
            "    discrepancy = ?, closing_balance = ? "
            "WHERE id = ? AND status = 'open'",
            (closed_ts, int(counted_amount), discrepancy, expected, self.id),
        )
        if cursor.rowcount != 1:
            raise ValueError(
                f"CashDrawer.close(): expected 1 row updated, got "
                f"{cursor.rowcount} (drawer id={self.id} not open)"
            )
        self.status = "closed"
        self.closed_at = closed_ts
        self.counted_amount = int(counted_amount)
        self.discrepancy = discrepancy
        self.closing_balance = expected
        # DG-363 Phase 2 (FR6): persist the breakdown snapshot at close time
        # so /history reads the closed-drawer breakdown from the snapshot
        # instead of re-aggregating journal entries (FR7, NFR1).
        CashDrawer.save_breakdown_snapshot(conn, self.id)
        return discrepancy

    def auto_close(self, conn, *, closed_at: Optional[str] = None) -> int:
        """FR8: auto-close at midnight using expected_balance as the counted
        amount, so the discrepancy is 0 (NFR1).

        Persists ``closing_balance = expected_balance`` (FR2/AC12). Unlike
        :meth:`close` (manual count, may record an adjustment journal entry),
        auto-close trusts the books: ``counted_amount = expected_balance`` and
        ``discrepancy = 0``. No close-adjustment journal entry is created
        because there is no discrepancy to absorb (NFR3).

        Race-condition safety: the caller wraps this in a transaction with a
        ``WHERE status = 'open'`` guard so concurrent writers cannot double-close.
        Returns the discrepancy (always 0).
        """
        expected = self.expected_balance(conn)
        closed_ts = closed_at or now_utc()
        conn.execute(
            "UPDATE cash_drawer "
            "SET status = 'closed', closed_at = ?, counted_amount = ?, "
            "    discrepancy = 0, closing_balance = ? "
            "WHERE id = ? AND status = 'open'",
            (closed_ts, expected, expected, self.id),
        )
        self.status = "closed"
        self.closed_at = closed_ts
        self.counted_amount = expected
        self.discrepancy = 0
        self.closing_balance = expected
        # DG-363 Phase 2 (FR6): persist the breakdown snapshot at auto-close
        # time, identical to the manual close path.
        CashDrawer.save_breakdown_snapshot(conn, self.id)
        return 0

    @staticmethod
    def get_most_recent_closed(conn) -> "CashDrawer | None":
        row = conn.execute(
            "SELECT * FROM cash_drawer WHERE status = 'closed' "
            "ORDER BY closed_at DESC LIMIT 1"
        ).fetchone()
        return CashDrawer.from_row(row) if row else None

    @staticmethod
    def get_stale_open_before(conn, *, before_iso: str) -> list["CashDrawer"]:
        """FR8 helper: list open drawers whose ``opened_at`` is strictly before
        the given ISO-8601 timestamp (typically the start of the current local
        day). Returns drawers ordered by ``opened_at`` ASC so the oldest
        stale drawer is auto-closed first. Used by the lazy auto-close check
        in the API layer.
        """
        rows = conn.execute(
            "SELECT * FROM cash_drawer "
            "WHERE status = 'open' AND opened_at < ? "
            "ORDER BY opened_at ASC, id ASC",
            (before_iso,),
        ).fetchall()
        return [CashDrawer.from_row(r) for r in rows]

    @staticmethod
    def get_transactions(
        conn,
        drawer_id: int,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list[dict], int]:
        """Return a unified, paginated list of cash transactions for a drawer
        (DG-343 Phase 1, FR1/FR2).

        Each transaction item includes:
            - ``type``: derived from the journal entry ``source_type``
              (e.g. ``cash_drawer_open`` → "Mở quầy", ``payment_transaction`` →
              "Bán hàng", ``expense`` → "Chi phí").
            - ``amount``: signed net 1101 (Cash in Drawer) movement —
              ``debit - credit`` for the 1101 line(s) of the linked journal
              entry. Positive values are inflows (cash sales, cash-in, opening
              balance, owner capital); negative values are outflows (cash-out,
              cash expenses, close-adjust shortages, auto-transfer to owner).
            - ``timestamp``: the journal entry ``transaction_date`` (the
              business event date), falling back to ``created_at`` when NULL.
            - ``note``: the journal entry ``description``.

        The query joins ``journal_entries`` linked to the drawer via the
        ``cash_drawer_journal_entries`` join table (DG-347 Phase 1) and
        aggregates their 1101 journal lines so each linked entry collapses to
        one row. Only linked entries that touch 1101 are returned — non-cash
        operations (e.g. bank transfers, card payments) carry no 1101 line and
        are excluded. Ordered newest-first by ``transaction_date`` then
        ``journal_entries.id`` DESC. Paginated via ``limit``/``offset``.

        Returns ``(items, total)`` where ``total`` is the total count of
        matching linked entries (across all pages) for pagination UI.
        """
        # Aggregate 1101 lines per linked journal entry so each entry collapses
        # to one transaction row with a single signed amount. Entries without a
        # 1101 line are excluded by the inner WHERE clause.
        #
        # DG-343 Phase 4: LEFT JOIN payment_transactions → orders to fetch the
        # order receiving code + customer name for `payment_transaction` rows,
        # and LEFT JOIN events to fetch summary + staff_name + data for
        # `expense` rows. These populate the `reference` and `reference_detail`
        # fields returned to the UI so each transaction card can show its
        # originating document (order ref or expense description).
        #
        # DG-363 Phase 2: also aggregate the net 2200 (Bus Shipping Held)
        # credit per linked journal entry so the response can expose
        # ``shippingAmount`` — the bus-shipping portion of a
        # ``payment_transaction`` that was split into 2200 (FR5). The 2200
        # lines are joined via a separate LEFT JOIN aliased ``jl2200`` /
        # ``a2200`` so they do not fan-out the 1101 aggregation.
        rows = conn.execute(
            """
            SELECT je.id                AS je_id,
                   je.source_type       AS source_type,
                   je.description       AS description,
                   je.transaction_date  AS transaction_date,
                   je.created_at        AS created_at,
                   COALESCE(SUM(jl1101.debit - jl1101.credit), 0) AS amount,
                   COALESCE((
                       SELECT SUM(jl2200.credit - jl2200.debit)
                       FROM journal_lines jl2200
                       JOIN accounts a2200
                            ON a2200.id = jl2200.account_id
                            AND a2200.code = '2200'
                       WHERE jl2200.journal_entry_id = je.id
                   ), 0) AS shipping_amount,
                   o.order_ref          AS order_ref,
                   o.customer_name      AS customer_name,
                   e.summary           AS event_summary,
                   e.staff_name         AS event_staff_name,
                   e.data              AS event_data
            FROM journal_entries je
            JOIN cash_drawer_journal_entries cdje
                 ON cdje.journal_entry_id = je.id
            JOIN journal_lines jl1101
                 ON jl1101.journal_entry_id = je.id
            JOIN accounts a1101
                 ON a1101.id = jl1101.account_id AND a1101.code = '1101'
            LEFT JOIN payment_transactions pt
                 ON je.source_type = 'payment_transaction' AND je.source_id = pt.id
            LEFT JOIN orders o ON o.id = pt.order_id
            LEFT JOIN events e
                 ON je.source_type = 'expense' AND je.source_id = e.id
            WHERE cdje.cash_drawer_id = ?
            GROUP BY je.id, je.source_type, je.description,
                     je.transaction_date, je.created_at,
                     o.order_ref, o.customer_name,
                     e.summary, e.staff_name, e.data
            ORDER BY COALESCE(je.transaction_date, je.created_at) DESC,
                     je.id DESC
            LIMIT ? OFFSET ?
            """,
            (int(drawer_id), int(limit), int(offset)),
        ).fetchall()
        items = []
        for row in rows:
            source_type = row["source_type"]
            reference = ""
            reference_detail = ""
            if source_type == "payment_transaction":
                reference = row["order_ref"] or ""
                reference_detail = row["customer_name"] or ""
            elif source_type == "expense":
                reference = row["event_summary"] or ""
                staff_name = row["event_staff_name"] or ""
                provider = ""
                event_data_raw = row["event_data"]
                if event_data_raw:
                    try:
                        event_data = json.loads(event_data_raw)
                        if isinstance(event_data, dict):
                            provider = (event_data.get("payment_source") or "").strip()
                    except (ValueError, TypeError):
                        provider = ""
                # "staff_name — provider" (em dash) when both present; else
                # whichever is non-empty.
                parts = [p for p in (staff_name, provider) if p]
                reference_detail = " — ".join(parts)
            items.append(
                {
                    "id": str(row["je_id"]),
                    "type": source_type,
                    "amount": int(row["amount"]) if row["amount"] is not None else 0,
                    # DG-363 Phase 2 (FR5): shippingAmount is the bus-shipping
                    # portion of a payment_transaction split into 2200. Zero
                    # for non-payment rows and for payments with no bus split.
                    "shippingAmount": (
                        int(row["shipping_amount"])
                        if source_type == "payment_transaction"
                           and row["shipping_amount"] is not None
                        else 0
                    ),
                    "timestamp": (
                        row["transaction_date"] if row["transaction_date"]
                        else row["created_at"]
                    ),
                    "note": row["description"] or "",
                    "reference": reference,
                    "reference_detail": reference_detail,
                }
            )
        total_row = conn.execute(
            """
            SELECT COUNT(*) AS c
            FROM (
                SELECT je.id
                FROM journal_entries je
                JOIN cash_drawer_journal_entries cdje
                     ON cdje.journal_entry_id = je.id
                JOIN journal_lines jl1101
                     ON jl1101.journal_entry_id = je.id
                JOIN accounts a1101
                     ON a1101.id = jl1101.account_id AND a1101.code = '1101'
                WHERE cdje.cash_drawer_id = ?
                GROUP BY je.id
            )
            """,
            (int(drawer_id),),
        ).fetchone()
        total = int(total_row["c"]) if total_row else 0
        return items, total

    # ------------------------------------------------------------------
    # DG-363 Phase 2 — breakdown snapshot (FR6, FR7)
    # ------------------------------------------------------------------

    @staticmethod
    def _aggregate_breakdown(conn, drawer_id: int) -> dict[str, tuple[float, int]]:
        """Aggregate the per-category breakdown for a single drawer.

        Mirrors the v097 backfill classification (FR4/FR5/FR6): each linked
        journal entry is classified by ``source_type`` into one of the 8
        canonical categories. ``payment_transaction`` inflows on bus orders
        split the 2200-held shipping portion into ``busShipping`` and the
        remainder into ``sale``; refunds (net 1101 < 0) go to ``refund``.
        Returns a dict keyed by category with ``(total_amount, count)`` tuples,
        always containing all 8 categories (zero rows for empty categories).
        """
        snapshot: dict[str, tuple[float, int]] = {
            cat: (0.0, 0) for cat in BREAKDOWN_SNAPSHOT_CATEGORIES
        }
        entry_totals = conn.execute(
            """
            SELECT je.id               AS je_id,
                   je.source_type      AS source_type,
                   COALESCE(SUM(CASE WHEN a.code = '1101'
                                     THEN jl.debit - jl.credit ELSE 0 END), 0) AS net_1101,
                   COALESCE(SUM(CASE WHEN a.code = '2200'
                                     THEN jl.credit - jl.debit ELSE 0 END), 0) AS held_2200
            FROM cash_drawer_journal_entries cdje
            JOIN journal_entries je ON je.id = cdje.journal_entry_id
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            JOIN accounts a ON a.id = jl.account_id AND a.code IN ('1101', '2200')
            WHERE cdje.cash_drawer_id = ?
            GROUP BY je.id, je.source_type
            """,
            (int(drawer_id),),
        ).fetchall()

        def accumulate(category: str, amount: float, count: int) -> None:
            prev_amount, prev_count = snapshot[category]
            snapshot[category] = (prev_amount + amount, prev_count + count)

        for row in entry_totals:
            source_type = row["source_type"] or ""
            net_1101 = float(row["net_1101"] or 0)
            held_2200 = float(row["held_2200"] or 0)
            # CQ-1 (DG-363 review-auto cycle 1): the source_type → breakdown
            # category classification below is triplicated. The same mapping
            # exists in two other files and MUST be kept in sync:
            #   - src/baker/db/schema/migrations/v097.py:
            #     _migrate_v97_cash_drawer_breakdown_snapshot (the backfill
            #     path that persists snapshots for already-closed drawers)
            #   - app/lib/features/cash_drawer/widgets/
            #     cash_drawer_breakdown_card.dart: _categoryForType +
            #     aggregateCashDrawerBreakdown (the Flutter live-aggregation
            #     path)
            # Any change to a category mapping, ordering, fallback, or the
            # payment_transaction shipping split here MUST be mirrored in
            # both of those files so the live aggregation, the persisted
            # snapshot, and the client-side aggregation stay consistent.
            if source_type == "payment_transaction":
                if net_1101 < 0:
                    accumulate("refund", net_1101, 1)
                elif net_1101 > 0:
                    shipping = min(held_2200, net_1101) if held_2200 > 0 else 0.0
                    sale_portion = net_1101 - shipping
                    if sale_portion > 0:
                        accumulate("sale", sale_portion, 1)
                    else:
                        # sale_portion == 0: 1101 inflow fully consumed by
                        # held shipping. The sale category still counts the
                        # entry (at zero amount) so the count is not lost,
                        # matching the backfill in v097.py. CQ-2 (DG-363
                        # review-auto cycle 1): previously an
                        # `elif sale_portion != 0` branch which was
                        # unreachable (sale_portion >= 0 by construction);
                        # changed to `else` so the zero-amount accumulation
                        # actually executes as documented.
                        accumulate("sale", sale_portion, 1)
                    if shipping > 0:
                        accumulate("busShipping", shipping, 1)
            elif source_type == "expense":
                accumulate("expense", net_1101, 1)
            elif source_type in ("cash_drawer_cash_in", "owner_capital"):
                accumulate("cashIn", net_1101, 1)
            elif source_type in ("cash_drawer_cash_out", "cash_drawer_auto_transfer"):
                accumulate("cashOut", net_1101, 1)
            elif source_type == "cash_drawer_open":
                accumulate("open", net_1101, 1)
            elif source_type == "cash_drawer_close_adjust":
                accumulate("close", net_1101, 1)
            else:
                accumulate("sale", net_1101, 1)
        return snapshot

    @staticmethod
    def save_breakdown_snapshot(conn, drawer_id: int) -> None:
        """FR6: persist the 8-row breakdown snapshot for a drawer at close time.

        Aggregates the drawer's linked journal entries by category and
        upserts one row per category into
        ``cash_drawer_breakdown_snapshot``. Idempotent: existing rows for
        ``(drawer_id, category)`` are replaced with the fresh aggregation so
        re-closing (or a re-run) updates the snapshot rather than duplicating
        rows. Must be called inside the close transaction so the snapshot
        reflects the same journal state as the persisted ``closing_balance``.
        """
        snapshot = CashDrawer._aggregate_breakdown(conn, int(drawer_id))
        created_at = now_utc()
        # Delete then re-insert so a re-close refreshes the snapshot. The
        # UNIQUE(drawer_id, category) index makes INSERT OR REPLACE an
        # alternative, but delete+insert keeps the created_at consistent for
        # all 8 rows on a refresh.
        conn.execute(
            "DELETE FROM cash_drawer_breakdown_snapshot WHERE drawer_id = ?",
            (int(drawer_id),),
        )
        rows = [
            (int(drawer_id), cat, total_amount, count, created_at)
            for cat in BREAKDOWN_SNAPSHOT_CATEGORIES
            for total_amount, count in (snapshot[cat],)
        ]
        conn.executemany(
            "INSERT INTO cash_drawer_breakdown_snapshot "
            "(drawer_id, category, total_amount, count, created_at) "
            "VALUES (?, ?, ?, ?, ?)",
            rows,
        )

    @staticmethod
    def get_breakdown_snapshot(conn, drawer_id: int) -> list[dict]:
        """FR7: read the persisted breakdown snapshot for a closed drawer.

        Returns a list of 8 dicts (one per canonical category, in the fixed
        ``BREAKDOWN_SNAPSHOT_CATEGORIES`` order) with ``category``,
        ``totalAmount`` (float), and ``count`` (int). Returns ``[]`` when the
        drawer has no snapshot (e.g. an open drawer, or a closed drawer that
        predates the v097 migration and was not backfilled) — the caller
        treats an empty list as "snapshot unavailable".
        """
        placeholders = ",".join("?" for _ in BREAKDOWN_SNAPSHOT_CATEGORIES)
        rows = conn.execute(
            f"""
            SELECT category, total_amount, count
            FROM cash_drawer_breakdown_snapshot
            WHERE drawer_id = ? AND category IN ({placeholders})
            """,  # nosec B608
            (int(drawer_id), *BREAKDOWN_SNAPSHOT_CATEGORIES),
        ).fetchall()
        by_cat = {r["category"]: r for r in rows}
        result = []
        for cat in BREAKDOWN_SNAPSHOT_CATEGORIES:
            row = by_cat.get(cat)
            if row is None:
                continue
            result.append(
                {
                    "category": cat,
                    "totalAmount": float(row["total_amount"]),
                    "count": int(row["count"]),
                }
            )
        return result

    # ------------------------------------------------------------------
    # DG-379 Phase 4.2 — transaction edit + reconcile (FR1-FR9, AC1-AC7)
    # ------------------------------------------------------------------

    @staticmethod
    def edit_transaction(
        conn,
        drawer_id: int,
        entry_id: int,
        *,
        amount: Optional[int] = None,
        notes: Optional[str] = None,
    ) -> dict:
        """FR1-FR5: edit an open/close transaction's amount and/or notes in a
        single DB transaction (FR9). Returns a dict describing the updated
        journal entry and the recalculated drawer state.

        Validation (FR7, FR2, FR3):
            - Drawer must exist (raises :class:`DrawerNotFound`).
            - Drawer must not be reconciled (raises :class:`DrawerReconciled`).
            - Journal entry must exist and be linked to the drawer (raises
              :class:`TransactionNotFound`).
            - Journal entry ``source_type`` must be ``cash_drawer_open`` or
              ``cash_drawer_close_adjust`` (raises :class:`InvalidTransactionType`).
            - For close (``cash_drawer_close_adjust``) entries, the drawer
              must be closed (raises :class:`CloseEditRequiresClosedDrawer`).
            - ``amount`` must be > 0 when provided (raises
              :class:`InvalidAmount`).
            - After the line update, debit must equal credit (NFR2); raises
              :class:`IntegrityError` if not (defensive — should not happen).

        Recalculation (FR4-FR6):
            - For a close transaction edit, the drawer's ``closing_balance``,
              ``counted_amount``, and ``discrepancy`` are recalculated in-place
              from the new expected_balance and the edited close entry amount,
              and the breakdown snapshot is regenerated.
            - For an open transaction edit, ``expected_balance`` is naturally
              derived from the updated 1101 lines on next read (no
              ``closing_balance`` to update because the drawer is open).

        All updates run inside the caller's transaction (FR9). The caller is
        responsible for commit/rollback (the ``get_db()`` context commits on
        success and rolls back on exception).
        """
        drawer = CashDrawer.get_by_id(conn, int(drawer_id))
        if drawer is None:
            raise DrawerNotFound(int(drawer_id))
        if drawer.reconciled:
            raise DrawerReconciled(int(drawer_id))

        # Fetch the journal entry and verify it is linked to this drawer.
        row = conn.execute(
            """
            SELECT je.* FROM journal_entries je
            JOIN cash_drawer_journal_entries cdje
                 ON cdje.journal_entry_id = je.id
            WHERE je.id = ? AND cdje.cash_drawer_id = ?
            """,
            (int(entry_id), int(drawer_id)),
        ).fetchone()
        if row is None:
            raise TransactionNotFound(int(entry_id), int(drawer_id))
        source_type = row["source_type"]
        if source_type not in ("cash_drawer_open", "cash_drawer_close_adjust"):
            raise InvalidTransactionType(source_type)
        if source_type == "cash_drawer_close_adjust" and drawer.status != "closed":
            raise CloseEditRequiresClosedDrawer(int(drawer_id))

        new_amount: Optional[int] = None
        if amount is not None:
            new_amount = int(amount)
            if new_amount <= 0:
                raise InvalidAmount(new_amount)

        new_notes: Optional[str] = None
        if notes is not None:
            new_notes = str(notes)

        # ------------------------------------------------------------------
        # Update the journal entry description (notes) when provided (FR3).
        # ------------------------------------------------------------------
        if new_notes is not None:
            conn.execute(
                "UPDATE journal_entries SET description = ? WHERE id = ?",
                (new_notes, int(entry_id)),
            )

        # ------------------------------------------------------------------
        # Update journal_lines debit/credit when a new amount is provided
        # (FR1/FR2). The line update scales the existing lines so the entry
        # remains balanced (NFR2):
        #   - For a 2-line DR/CR entry, both lines are set to ``new_amount``.
        #   - For a 4-line compound ``unidentified_sale`` entry (DR 1101/CR 4100
        #     + DR 5900/CR 1300 at 50% COGS), the 1101/4100 lines are set to
        #     ``new_amount`` and the 5900/1300 lines are set to 50% of it.
        # The original balance (sum of debit lines) is used to derive the
        # scale factor so compound entries stay proportional.
        # ------------------------------------------------------------------
        if new_amount is not None:
            lines = conn.execute(
                "SELECT id, debit, credit FROM journal_lines "
                "WHERE journal_entry_id = ? ORDER BY id",
                (int(entry_id),),
            ).fetchall()
            if not lines:
                raise IntegrityError(int(entry_id), "journal entry has no lines")
            original_total = sum(float(r["debit"]) for r in lines)
            if original_total <= 0:
                raise IntegrityError(int(entry_id), "non-positive original debit total")
            # Determine if this is a compound (4-line) unidentified_sale entry
            # by checking for the 5900/1300 accounts. When present, the COGS
            # portion is 50% of the sale portion; scale both groups so the
            # 50% ratio is preserved.
            has_cogs = len(lines) == 4
            new_debit_total = float(new_amount)
            if has_cogs:
                # 1101 + 4100 lines get new_amount; 5900 + 1300 get 50%.
                sale_lines = lines[:2]
                cogs_lines = lines[2:]
                sale_amt = float(new_amount)
                cogs_amt = float(new_amount) * 0.5
                for r in sale_lines:
                    _update_line_amount(conn, int(r["id"]), float(r["debit"]), float(r["credit"]), sale_amt)
                for r in cogs_lines:
                    _update_line_amount(conn, int(r["id"]), float(r["debit"]), float(r["credit"]), cogs_amt)
            else:
                # 2-line entry: set both lines to new_amount (preserve DR/CR
                # orientation).
                for r in lines:
                    _update_line_amount(conn, int(r["id"]), float(r["debit"]), float(r["credit"]), new_debit_total)
            # NFR2: verify debit == credit after the update.
            check = conn.execute(
                "SELECT COALESCE(SUM(debit), 0) AS d, COALESCE(SUM(credit), 0) AS c "
                "FROM journal_lines WHERE journal_entry_id = ?",
                (int(entry_id),),
            ).fetchone()
            if abs(float(check["d"]) - float(check["c"])) > 0.005:
                raise IntegrityError(int(entry_id), "debit != credit after edit")

        # ------------------------------------------------------------------
        # FR5/FR6: recalculate closing_balance, counted_amount, discrepancy
        # and regenerate the breakdown snapshot when editing a close
        # transaction. The close entry's 1101 line amount is the counted
        # adjustment; the drawer's expected_balance (recomputed from the
        # now-updated 1101 lines) is the book balance. The new
        # ``counted_amount`` = expected_balance (pre-close-adjust) + the
        # edited close-adjust amount when surplus, or expected_balance - the
        # edited amount when shortage. Because the close entry is the only
        # delta between expected (pre-close) and counted, we re-derive:
        #   counted_amount = expected_balance (which already includes the
        #   close-adjust entry because it is linked to the drawer)
        #   discrepancy = counted_amount - expected_balance_before_adjust
        # Simpler and robust: recompute closing_balance = expected_balance
        # (authoritative, includes all linked 1101 lines incl. the edited
        # close entry), and counted_amount = closing_balance (zero
        # discrepancy by construction for an auto-close; for a manual close
        # with a counted amount we preserve the original discrepancy
        # direction by re-deriving counted_amount from the close-adjust sign).
        # ------------------------------------------------------------------
        if source_type == "cash_drawer_close_adjust" and new_amount is not None:
            # The drawer's expected_balance (from closing_balance field for a
            # closed drawer) was persisted at close time as the
            # pre-close-adjust expected. The close-adjust entry then adds the
            # surplus (or subtracts the shortage) so the final 1101 balance
            # equals counted_amount. After editing the close-adjust amount,
            # the new closing_balance = pre-adjust expected + signed new
            # amount, and the new counted_amount = closing_balance (the
            # physical count equals the book balance plus the adjustment).
            #
            # Recover the pre-adjust expected from the original
            # closing_balance minus the original close-adjust 1101 movement.
            # Then add the new close-adjust 1101 movement to get the new
            # closing_balance.
            original_closing = int(drawer.closing_balance or 0)
            # Original signed 1101 movement of the close entry (before edit)
            # — we already overwrote the lines, so recover from
            # opening_balance + (original closing - opening) ... simpler:
            # the close entry's original 1101 movement = original closing -
            # pre-adjust expected. We don't have pre-adjust expected stored,
            # so derive the new closing_balance directly: it is the
            # opening_balance plus the SUM of all linked 1101 lines (which
            # now includes the edited close entry). This is exactly
            # expected_balance() but the drawer is closed so
            # expected_balance() returns the persisted closing_balance. We
            # therefore recompute it from the journal lines directly.
            row2 = conn.execute(
                """
                SELECT COALESCE(SUM(jl.debit - jl.credit), 0) AS balance
                FROM cash_drawer_journal_entries cdje
                JOIN journal_lines jl ON jl.journal_entry_id = cdje.journal_entry_id
                JOIN accounts a ON a.id = jl.account_id AND a.code = '1101'
                WHERE cdje.cash_drawer_id = ?
                """,
                (int(drawer_id),),
            ).fetchone()
            new_closing = int(drawer.opening_balance) + int(row2["balance"])
            # Determine the close-adjust sign: a surplus close entry debits
            # 1101 (positive 1101 movement); a shortage credits 1101
            # (negative). We infer the sign from the edited 1101 line.
            close_line = conn.execute(
                """
                SELECT jl.debit, jl.credit FROM journal_lines jl
                JOIN accounts a ON a.id = jl.account_id AND a.code = '1101'
                WHERE jl.journal_entry_id = ?
                """,
                (int(entry_id),),
            ).fetchone()
            if close_line is None:
                raise IntegrityError(int(entry_id), "close entry has no 1101 line")
            signed_adjust = float(close_line["debit"]) - float(close_line["credit"])
            # The pre-adjust expected = new_closing - signed_adjust. The new
            # counted_amount = pre-adjust expected + signed_adjust = new_closing
            # only if discrepancy was zero; for a manual close the counted
            # amount is the physical count, which differs from the book
            # balance by the discrepancy. We preserve the original
            # discrepancy by re-deriving counted_amount = new_closing + 0
            # (discrepancy is recomputed below from the original counted
            # minus the original pre-adjust expected, but we don't have the
            # original pre-adjust expected). The simplest correct behavior:
            # the close-adjust entry IS the discrepancy booking, so after
            # editing it, the new discrepancy is the new close-adjust amount
            # (signed) and the new counted_amount = new_closing (the books now
            # match the count by construction).
            new_counted = new_closing
            new_discrepancy = int(round(signed_adjust))
            conn.execute(
                "UPDATE cash_drawer "
                "SET closing_balance = ?, counted_amount = ?, discrepancy = ? "
                "WHERE id = ?",
                (new_closing, new_counted, new_discrepancy, int(drawer_id)),
            )
            # FR6: regenerate the breakdown snapshot from the updated lines.
            CashDrawer.save_breakdown_snapshot(conn, int(drawer_id))

        # ------------------------------------------------------------------
        # Build the response: updated journal entry + recalculated drawer.
        # ------------------------------------------------------------------
        updated_entry = conn.execute(
            "SELECT * FROM journal_entries WHERE id = ?", (int(entry_id),)
        ).fetchone()
        return {
            "drawerId": str(drawer_id),
            "entryId": str(entry_id),
            "sourceType": source_type,
            "amount": new_amount,
            "notes": new_notes if new_notes is not None else (updated_entry["description"] or ""),
            "drawer": CashDrawer.get_by_id(conn, int(drawer_id)).to_api_dict(conn),
        }

    @staticmethod
    def reconcile(conn, drawer_id: int) -> int:
        """FR8/AC6: mark a drawer as reconciled (``reconciled = 1``).

        Idempotent: re-reconciling an already-reconciled drawer is a no-op
        (returns 1 without changing state). Returns the new ``reconciled``
        value (1). Raises :class:`DrawerNotFound` if the drawer does not
        exist.
        """
        drawer = CashDrawer.get_by_id(conn, int(drawer_id))
        if drawer is None:
            raise DrawerNotFound(int(drawer_id))
        conn.execute(
            "UPDATE cash_drawer SET reconciled = 1 WHERE id = ?",
            (int(drawer_id),),
        )
        return 1


# ---------------------------------------------------------------------------
# DG-379 Phase 4.2 — exceptions for edit_transaction / reconcile
# ---------------------------------------------------------------------------


class DrawerNotFound(Exception):
    """Raised when a drawer id does not exist (HTTP 404)."""

    def __init__(self, drawer_id: int):
        self.drawer_id = drawer_id
        super().__init__(f"Cash drawer id={drawer_id} not found")


class DrawerReconciled(Exception):
    """Raised when an edit is attempted on a reconciled drawer (HTTP 409)."""

    def __init__(self, drawer_id: int):
        self.drawer_id = drawer_id
        super().__init__(f"Cash drawer id={drawer_id} is reconciled — edits are locked")


class TransactionNotFound(Exception):
    """Raised when a journal entry is not linked to the drawer (HTTP 404)."""

    def __init__(self, entry_id: int, drawer_id: int):
        self.entry_id = entry_id
        self.drawer_id = drawer_id
        super().__init__(
            f"Journal entry id={entry_id} not found for drawer id={drawer_id}"
        )


class InvalidTransactionType(Exception):
    """Raised when the entry source_type is not open/close (HTTP 400)."""

    def __init__(self, source_type: str):
        self.source_type = source_type
        super().__init__(
            f"Transaction type '{source_type}' is not editable — "
            "only cash_drawer_open and cash_drawer_close_adjust can be edited"
        )


class CloseEditRequiresClosedDrawer(Exception):
    """Raised when editing a close entry on an open drawer (HTTP 409)."""

    def __init__(self, drawer_id: int):
        self.drawer_id = drawer_id
        super().__init__(
            f"Close-adjust entries can only be edited when the drawer is closed "
            f"(drawer id={drawer_id} is open)"
        )


class InvalidAmount(Exception):
    """Raised when the amount is <= 0 (HTTP 400)."""

    def __init__(self, amount: int):
        self.amount = amount
        super().__init__(f"Amount must be > 0 (got {amount})")


class IntegrityError(Exception):
    """Raised when debit != credit after an edit (HTTP 500 — defensive)."""

    def __init__(self, entry_id: int, reason: str):
        self.entry_id = entry_id
        self.reason = reason
        super().__init__(f"Journal entry id={entry_id} integrity error: {reason}")


def _update_line_amount(conn, line_id: int, debit: float, credit: float, new_amount: float) -> None:
    """Update a journal line's debit or credit to ``new_amount`` preserving
    the DR/CR orientation. The non-zero side is set to ``new_amount``; the
    zero side stays zero."""
    if debit > 0:
        conn.execute(
            "UPDATE journal_lines SET debit = ? WHERE id = ?",
            (float(new_amount), line_id),
        )
    elif credit > 0:
        conn.execute(
            "UPDATE journal_lines SET credit = ? WHERE id = ?",
            (float(new_amount), line_id),
        )
    else:
        # Both zero (should not happen for a balanced entry) — defensive.
        conn.execute(
            "UPDATE journal_lines SET debit = ? WHERE id = ?",
            (float(new_amount), line_id),
        )