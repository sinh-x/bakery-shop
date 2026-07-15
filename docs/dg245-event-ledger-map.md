# DG-245 Phase 1 — Event → Ledger Map

> Investigation deliverable for DG-245 (source-to-ledger reconciliation).
> Scope: document every business event class, the journal `source_type`(s) it
> produces, the `_sync_*` function that writes each one, and the amount
> identity (SUM) each class must satisfy so the Phase 5 `source_ledger_totals`
> validator can use it as a spec. **No code changes** — documentation only.

## 1. Method

Sources cross-referenced to build this map:

1. `src/baker/services/journal_sync.py` — every `_sync_*` function and the
   `source_type` string literals they pass to `_insert_journal_entry` /
   `_find_journal_entry`. Read in full (1–1509).
2. `src/baker/services/accounting_validation.py` — `source_completeness`
   check (which source types it covers) and the rest of `CHECKS` to see
   which classes already have any validation. Read in full (1–1137).
3. `src/baker/commands/repair.py` — every `repair-*` command and which
   `_sync_*` / source types it targets. Read in full (1–1843).
4. `src/baker/db/schema.py` — account code constants
   (`ACCOUNTS_PAYABLE_CODE`, `EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE`,
   `EXPENSE_CATEGORY_TO_ACCOUNT_CODE`, `INVENTORY_PURCHASE_CATEGORIES`,
   `PAYMENT_OUTFLOW_TYPES`, `PAYMENT_TIEN_RUT_TYPES`, …) and the
   `order_shipping_hold` migration backfill at line 2285. Read 1555–1629 and
   2200–2305.
5. `src/baker/api/events.py` — caller of `_sync_debt_settlement_journal`,
   showing that debt settlements are nested inside the expense event's
   `data.settlements` array (not a separate table). Read 400–460, 680–719.
6. Live dev db `data/baker.db` — `journal_entries.source_type` distribution
   and table schemas (`events`, `payment_transactions`, `orders`,
   `order_items`, `stock_movements`, `journal_entries`, `journal_lines`).

## 2. Live `journal_entries.source_type` distribution

Queried from `data/baker.db`:

| source_type                | count | Sync function that writes it |
|----------------------------|-------|------------------------------|
| `expense`                  |    27 | `_sync_expense_journal` |
| `expense_settlement`       |     0 | `_sync_debt_settlement_journal` |
| `order`                    |  1365 | `_reconcile_order_revenue_entry` / `_reconcile_tien_rut_return_entry` (both keyed `source_type='order'`) |
| `order_cogs`               |  1348 | `_sync_order_cogs_entry` |
| `order_shipping_hold`      |    93 | `_migrate_v49_backfill_order_shipping` (schema.py:2285) — backfill only; live path uses payment-time split |
| `order_shipping_release`   |   106 | `_sync_bus_shipping_release_entry` |
| `payment_transaction`      |  1459 | `_sync_payment_journal` |
| `waste_cogs`               |     1 | `_sync_waste_cogs_journal` |
| `negative_sale_cogs`       |     0 | `_sync_negative_sale_cogs_journal` |
| `restock_inflow`           |     0 | `_sync_restock_inflow_journal` |
| **total**                  |  4399 | — |

Notable: `expense_settlement`, `negative_sale_cogs`, and `restock_inflow`
have **zero rows** on the live dev db. They are nonetheless emitted by
real `_sync_*` functions and are part of the source-ledger contract, so
they are included in the map below.

## 3. Event-class → journal source_type → amount identity

Legend for the "Amount identity" column:

- `source_amount` = the SUM expression over the **source-side** rows.
- `journal_amount` = the SUM expression over the matching
  `journal_lines` rows.
- The class passes `source_ledger_totals` when `|source_amount −
  journal_amount| ≤ DEBIT_CREDIT_TOLERANCE` (0.005 VND) per class.

Tolerances for revenue-class identities use
`REVENUE_UPDATE_TOLERANCE` (0.005) to match the reconciler; for COGS /
inventory flows the same 0.005 tolerance applies.

### 3.1 `expense` — expense events

| Field | Value |
|-------|-------|
| Event class | `expense` |
| Source table | `events` (rows with `type='expense'`, `deleted_at IS NULL`) |
| Journal `source_type` | `expense` |
| `source_id` | `events.id` |
| Sync function | `_sync_expense_journal` (`journal_sync.py:275`), builder `_build_expense_journal_lines` (`:217`) |
| Source-side amount column | `events.data.amount_vnd` (JSON, numeric) |
| Journal-side amount | `SUM(jl.debit)` on the debit line of the expense JE (equivalently `SUM(jl.credit)` on the credit line) |
| Amount identity | `SUM(data.amount_vnd) = SUM(jl.debit)` over all non-reversed `expense` entries, **per event**. Aggregated: `Σ events.amount_vnd = Σ debit lines of expense JEs`. |
| Special cases | Inventory-purchase categories (`Nguyên liệu`, `Bao bì`) debit Inventory (1300) not an expense account; debt (`payment_method='Nợ'`) credits 2500 not an asset. The **amount identity is unaffected** — debit total still equals `amount_vnd`. |
| Zero-amount skip | `_build_expense_journal_lines` returns `None` when `amount_vnd <= 0` or `category`/`payment_source` missing — these events have **no JE by design** and must be excluded from the source SUM (or the identity will report a false delta). |
| Existing validation | `source_completeness` (existence only); `expense_category_mismatch` (debit-side account only). **No amount identity check exists.** |

### 3.2 `expense_settlement` — debt settlements

| Field | Value |
|-------|-------|
| Event class | debt settlement (nested in expense event) |
| Source "table" | `events.data.settlements[]` array on a debt (`payment_method='Nợ'`) expense event |
| Journal `source_type` | `expense_settlement` |
| `source_id` | `settlements[].id` (synthetic, per-event counter assigned in `api/events.py:680`) |
| Sync function | `_sync_debt_settlement_journal` (`journal_sync.py:366`), builder `_build_debt_settlement_journal_lines` (`:339`) |
| Source-side amount column | `events.data.settlements[].amount` |
| Journal-side amount | `SUM(jl.debit)` on the AP (2500) line — equals `SUM(jl.credit)` on the asset line |
| Amount identity | `Σ settlements.amount = Σ debit_2500` over all `expense_settlement` entries. **Per expense event**, the settled total must also satisfy `Σ settlements.amount ≤ events.data.amount_vnd` (cannot over-settle), but that is a business rule, not the ledger identity. |
| Existing validation | **None.** `source_completeness` does not cover `expense_settlement`. No check inspects settlement JE amounts. **Coverage gap.** |

### 3.3 `order` — order revenue / AR / tien-rut return

| Field | Value |
|-------|-------|
| Event class | delivered/completed order (revenue recognition) |
| Source table | `orders` (rows with `status IN ('delivered','completed')`) |
| Journal `source_type` | `order` |
| `source_id` | `orders.id` |
| Sync functions | `_reconcile_order_revenue_entry` (`:721`) → `_reconcile_revenue_entry_lines` (`:900`) for the revenue/AR entry, and `_reconcile_tien_rut_return_entry` (`:1043`) for the tien-rut return entry. Both write `source_type='order'`; they are distinguished by description prefix (`Order revenue:` / `Order revenue (AR):` / `Tien rut return:`). |
| Source-side amount | **Two sub-identities**, because `order` holds up to two entries per order: |
|  • Revenue entry (paid orders) | `source_amount = max(0, deposits_in − tien_rut_total − refunds_out − shipping_held)` where `deposits_in = SUM(payment_transactions.amount WHERE type IN inflows)`, `tien_rut_total = SUM(amount WHERE type='tien_rut')`, `refunds_out = SUM(amount WHERE type='refund')`, `shipping_held = orders.shipping_fee WHEN delivery_type='bus'`. `journal_amount = debit_2100` (must equal `credit_4100`). |
|  • AR entry (truly unpaid) | `source_amount = orders.total_price` (used only when `deposits_in − tien_rut_total ≤ 0`). `journal_amount = debit_1500` (must equal `credit_4100`). |
|  • Tien-rut return entry | `source_amount = tien_rut_total` (the held 2400 balance). `journal_amount = debit_2400` (must equal credit-asset). |
| Aggregated identity | Σ per-order `source_amount` (per sub-identity) = Σ matching `journal_amount` over the matching description-prefix slice of `order` entries. The validator MUST split `order` entries by description prefix; summing all `order` debits together would mix the three sub-identities and produce a meaningless total. |
| Existing validation | `source_completeness` (existence); `deposit_revenue_integrity` (`debit_2100 = credit_4100` per entry); `deposit_balance_integrity` (per-order 2100 net = 0 for terminal orders). **No lump-sum source-vs-ledger total check exists.** |

### 3.4 `order_cogs` — order COGS

| Field | Value |
|-------|-------|
| Event class | delivered/completed order (cost of goods sold) |
| Source table | `order_items` (rows with `is_extra=0`, `is_gift=0`) joined to `orders` (`status IN ('delivered','completed')`) |
| Journal `source_type` | `order_cogs` |
| `source_id` | `orders.id` |
| Sync function | `_sync_order_cogs_entry` (`:1302`), via `_compute_order_cogs_total` (`:1208`) |
| Source-side amount | `SUM(order_items.cost_at_sale * quantity)` for non-extra/non-gift items on the order |
| Journal-side amount | `debit_5900` on the `order_cogs` JE (equals `credit_1300`) |
| Amount identity | `SUM(cost_at_sale * quantity) = debit_5900`, **per order**. Aggregated: `Σ order_items.cost_at_sale*qty = Σ debit_5900 of order_cogs entries`. |
| Zero-cost skip | `_sync_order_cogs_entry` skips when the resolved total ≤ 0; orders with all-zero-cost items have **no `order_cogs` JE by design** and must be excluded from the source SUM (or the identity will report a false delta). |
| Existing validation | `cogs_completeness` (missing `cost_at_sale`); `cogs_amount_accuracy` (per-entry `debit_5900 = Σ resolved_cost×qty`). `cogs_amount_accuracy` is a **per-entry** check; `source_ledger_totals` will be the **aggregated** lump-sum version. |

### 3.5 `order_shipping_hold` — bus shipping held (backfill only)

| Field | Value |
|-------|-------|
| Event class | delivered/completed bus order with `shipping_fee > 0` (legacy, pre-payment-split) |
| Source table | `orders` (`delivery_type='bus'`, `shipping_fee > 0`) |
| Journal `source_type` | `order_shipping_hold` |
| `source_id` | `orders.id` |
| Sync function | `_migrate_v49_backfill_order_shipping` (`schema.py:2285`) — **backfill migration only**. There is no live `_sync_*` function writing this source_type; the live path credits 2200 inside the `payment_transaction` entry instead. |
| Source-side amount | `orders.shipping_fee` |
| Journal-side amount | `credit_2200` on the `order_shipping_hold` JE (equals `debit_2100`) |
| Amount identity | `shipping_fee = credit_2200`, **per order**. Aggregated: `Σ orders.shipping_fee (bus, with a hold entry) = Σ credit_2200 of order_shipping_hold entries`. |
| Caveat | A bus order may hold shipping in 2200 **either** via an `order_shipping_hold` entry (legacy) **or** via its `payment_transaction` entries (live). The validator for this class must only compare the `order_shipping_hold` slice against orders that actually have such an entry; comparing against `orders.shipping_fee` for all bus orders would double-count orders whose shipping is held via `payment_transaction`. |
| Existing validation | `deposit_balance_integrity` includes `order_shipping_hold` debits in its 2100 net calculation. **No standalone amount identity check exists.** |

### 3.6 `order_shipping_release` — bus shipping released at delivery

| Field | Value |
|-------|-------|
| Event class | delivered/completed bus order with `shipping_fee > 0` |
| Source table | `orders` (`delivery_type='bus'`, `shipping_fee > 0`, `status IN ('delivered','completed')`) |
| Journal `source_type` | `order_shipping_release` |
| `source_id` | `orders.id` |
| Sync function | `_sync_bus_shipping_release_entry` (`:1104`) |
| Source-side amount | `min(orders.shipping_fee, held_in_2200_for_order)` where `held_in_2200` sums credits−debits on 2200 across `payment_transaction` AND `order_shipping_hold` entries for the order (`_held_shipping_for_order`, `:451`) |
| Journal-side amount | `debit_2200` on the `order_shipping_release` JE (equals `credit_asset`, default 1100) |
| Amount identity | `release_amount = debit_2200`, **per order**, where `release_amount = min(shipping_fee, held_in_2200)`. Aggregated: `Σ min(shipping_fee, held_in_2200) = Σ debit_2200 of order_shipping_release entries`. |
| Caveat | The source-side amount is **not** simply `orders.shipping_fee` — it is capped by the amount actually held in 2200. A validator that uses `shipping_fee` directly will report a false delta for orders where `held_in_2200 < shipping_fee` (partial hold). The identity must use the capped `release_amount`. |
| Existing validation | **None.** No check inspects `order_shipping_release` amounts. **Coverage gap.** |

### 3.7 `payment_transaction` — customer payments / refunds / tien-rut

| Field | Value |
|-------|-------|
| Event class | payment transaction |
| Source table | `payment_transactions` (rows with `invalidated_at IS NULL`) |
| Journal `source_type` | `payment_transaction` |
| `source_id` | `payment_transactions.id` |
| Sync function | `_sync_payment_journal` (`:637`), builder `_build_payment_journal_lines` (`:544`) |
| Source-side amount | `payment_transactions.amount` |
| Journal-side amount | `debit_asset` on the `payment_transaction` JE (equals credit on 2100 and/or 2200 and/or 2400 depending on type) |
| Amount identity | `amount = debit_asset`, **per transaction**. Aggregated: `Σ payment_transactions.amount (non-invalidated) = Σ debit_asset of payment_transaction entries`. |
| Special cases | • `type='refund'` (outflow): debits 2100, credits asset — `amount = credit_asset` instead. The identity holds on **both** sides: `amount = debit_2100 = credit_asset`. <br>• `type='tien_rut'` (DG-198 reversal): debits asset, credits 2400 — `amount = debit_asset = credit_2400`. <br>• Bus inflow with `shipping_fee > 0`: debit_asset = `amount`, credit split across 2100 (deposit) + 2200 (shipping). `amount = credit_2100 + credit_2200`. |
| Aggregated identity (robust form) | `Σ amount = Σ debit_asset` over all non-invalidated transactions — this works for inflows, refunds, and tien-rut uniformly because every `payment_transaction` JE debits an asset account for exactly `amount`. **Recommended for `source_ledger_totals`.** |
| Existing validation | `source_completeness` (existence); `cash_flow_integrity` (net cash balance, different shape). **No lump-sum source-vs-ledger total check exists.** |

### 3.8 `waste_cogs` — wasted stock

| Field | Value |
|-------|-------|
| Event class | waste stock movement |
| Source table | `stock_movements` (rows with `movement_type='waste'`) |
| Journal `source_type` | `waste_cogs` |
| `source_id` | `stock_movements.id` |
| Sync function | `_sync_waste_cogs_journal` (`:1358`) |
| Source-side amount | `resolve_product_cost(product_id) * quantity` — the resolved unit cost × wasted qty |
| Journal-side amount | `debit_5900` (equals `credit_1300`) |
| Amount identity | `unit_cost * quantity = debit_5900`, **per movement**. Aggregated: `Σ (resolve_product_cost × qty) = Σ debit_5900 of waste_cogs entries`. |
| Zero-cost skip | `_sync_waste_cogs_journal` skips when `resolve_product_cost` yields 0; movements with zero resolved cost have **no JE by design** and must be excluded from the source SUM. |
| Existing validation | `waste_cogs_referential_integrity` (orphan check only). **No amount identity check exists.** **Coverage gap.** |

### 3.9 `negative_sale_cogs` — oversold (negative) stock

| Field | Value |
|-------|-------|
| Event class | negative (oversold) sale stock movement |
| Source table | `stock_movements` (rows with `movement_type='negative_sale'`, per `_sync_negative_sale_cogs_journal` caller convention) |
| Journal `source_type` | `negative_sale_cogs` |
| `source_id` | `stock_movements.id` |
| Sync function | `_sync_negative_sale_cogs_journal` (`:1408`) |
| Source-side amount | `resolve_product_cost(product_id) * quantity` |
| Journal-side amount | `debit_5900` (equals `credit_1300`) |
| Amount identity | `unit_cost * quantity = debit_5900`, **per movement**. Aggregated: `Σ (resolve_product_cost × qty) = Σ debit_5900 of negative_sale_cogs entries`. |
| Zero-cost skip | same as `waste_cogs`. |
| Existing validation | **None.** **Coverage gap.** |

### 3.10 `restock_inflow` — reconciliation surplus inflow

| Field | Value |
|-------|-------|
| Event class | reconciliation surplus (restock) stock movement |
| Source table | `stock_movements` (rows with `movement_type='restock'`, per caller convention) |
| Journal `source_type` | `restock_inflow` |
| `source_id` | `stock_movements.id` |
| Sync function | `_sync_restock_inflow_journal` (`:1460`) |
| Source-side amount | `resolve_product_cost(product_id) * quantity` |
| Journal-side amount | `debit_1300` (equals `credit_5900`) — **note the lines are reversed** vs COGS: inventory debited, COGS credited. |
| Amount identity | `unit_cost * quantity = debit_1300`, **per movement**. Aggregated: `Σ (resolve_product_cost × qty) = Σ debit_1300 of restock_inflow entries`. |
| Zero-cost skip | same as `waste_cogs`. |
| Existing validation | **None.** **Coverage gap.** |

## 4. Coverage matrix: what `source_ledger_totals` must cover

Per the Phase 1 scope (§4 of the requirements doc), the new
`source_ledger_totals` check must cover the following classes. Each row
maps to one sub-identity the validator should compute:

| # | Class (source_type) | Source SUM | Journal SUM | Tolerance | Notes |
|---|--------------------|-----------|------------|-----------|-------|
| 1 | `expense` | `Σ events.data.amount_vnd` (non-deleted, buildable) | `Σ jl.debit` of `expense` JEs (excl. reversals) | 0.005 | Exclude zero-amount/unbuildable events; see §3.1 |
| 2 | `expense_settlement` | `Σ settlements.amount` across all debt expense events | `Σ jl.debit_2500` of `expense_settlement` JEs | 0.005 | Nested in `events.data.settlements[]`; currently 0 rows live — class still required for completeness |
| 3 | `order` (revenue) | `Σ max(0, deposits_in − tien_rut − refunds − shipping_held)` over delivered/completed orders | `Σ jl.debit_2100` of `order` revenue entries (description `Order revenue:`) | 0.005 | Must split by description prefix; AR and tien-rut-return are separate sub-identities |
| 4 | `order` (AR) | `Σ orders.total_price` over truly-unpaid delivered orders | `Σ jl.debit_1500` of `order` AR entries (description `Order revenue (AR):`) | 0.005 | Only orders where `deposits_in − tien_rut ≤ 0` |
| 5 | `order` (tien-rut return) | `Σ tien_rut_total` over delivered orders with held 2400 | `Σ jl.debit_2400` of `order` return entries (description `Tien rut return:`) | 0.005 | Source = held 2400 balance, not nominal `tien_rut_total` when partial returns exist |
| 6 | `order_cogs` | `Σ order_items.cost_at_sale * quantity` (non-extra/gift) | `Σ jl.debit_5900` of `order_cogs` JEs | 0.005 | Exclude all-zero-cost orders (no JE by design) |
| 7 | `order_shipping_hold` | `Σ orders.shipping_fee` over bus orders with a hold entry | `Σ jl.credit_2200` of `order_shipping_hold` JEs | 0.005 | Backfill-only source_type; cap to orders that actually have such an entry |
| 8 | `order_shipping_release` | `Σ min(shipping_fee, held_in_2200)` over delivered bus orders | `Σ jl.debit_2200` of `order_shipping_release` JEs | 0.005 | Source amount is capped, not raw `shipping_fee` |
| 9 | `payment_transaction` | `Σ payment_transactions.amount` (non-invalidated) | `Σ jl.debit_asset` of `payment_transaction` JEs | 0.005 | Use the asset-debit side for uniformity across inflow/refund/tien-rut |
| 10 | `waste_cogs` | `Σ resolve_product_cost × qty` over waste movements (resolvable cost) | `Σ jl.debit_5900` of `waste_cogs` JEs | 0.005 | Exclude zero-cost movements |
| 11 | `negative_sale_cogs` | `Σ resolve_product_cost × qty` over negative-sale movements (resolvable) | `Σ jl.debit_5900` of `negative_sale_cogs` JEs | 0.005 | Exclude zero-cost movements; 0 rows live |
| 12 | `restock_inflow` | `Σ resolve_product_cost × qty` over restock movements (resolvable) | `Σ jl.debit_1300` of `restock_inflow` JEs | 0.005 | Note: debit is on 1300, not 5900; 0 rows live |

## 5. Coverage gaps (classes with no existing validation)

Classes that currently have **no** dedicated validation check (only
`source_completeness` existence, or nothing at all):

| Class | Existing checks | Gap for `source_ledger_totals` to fill |
|-------|-----------------|----------------------------------------|
| `expense` | `source_completeness` (existence), `expense_category_mismatch` (debit account) | No amount identity. **Phase 5 fills this.** |
| `expense_settlement` | **None** | No existence, no amount identity. **Phase 5 fills this.** |
| `order` (revenue/AR/return) | `source_completeness`, `deposit_revenue_integrity`, `deposit_balance_integrity` | No lump-sum source-vs-ledger total. **Phase 5 fills this.** |
| `order_cogs` | `cogs_completeness`, `cogs_amount_accuracy` (per-entry) | No aggregated lump-sum check. **Phase 5 fills this.** |
| `order_shipping_hold` | `deposit_balance_integrity` (includes its 2100 debit) | No standalone amount identity. **Phase 5 fills this.** |
| `order_shipping_release` | **None** | No amount identity. **Phase 5 fills this.** |
| `payment_transaction` | `source_completeness`, `cash_flow_integrity` (net cash) | No lump-sum source-vs-ledger total. **Phase 5 fills this.** |
| `waste_cogs` | `waste_cogs_referential_integrity` (orphan only) | No amount identity. **Phase 5 fills this.** |
| `negative_sale_cogs` | **None** | No amount identity. **Phase 5 fills this.** |
| `restock_inflow` | **None** | No amount identity. **Phase 5 fills this.** |

Every class in the map is currently missing a lump-sum source-ledger
total check — confirming that the Phase 5 `source_ledger_totals` check is
additive (NFR: no rewrite of existing checks) and fills a real gap for
each class.

## 6. Key implementation notes for Phase 5

1. **Reversal exclusion.** Every aggregated SUM must exclude
   `journal_entries.description LIKE 'Reversal:%'` — reversal entries
   legitimately share a `source_type`/`source_id` with the original and
   would double-count. (`duplicate_entries` already uses this pattern.)

2. **`order` must split by description prefix.** Summing all `order`
   debits together mixes revenue (2100), AR (1500), and tien-rut return
   (2400) into one meaningless number. The validator must partition
   `order` entries by `description LIKE 'Order revenue:%'` /
   `'Order revenue (AR):%'` / `'Tien rut return:%'` and apply each
   sub-identity separately.

3. **Zero-amount / unbuildable source rows are by-design excluded.**
   `_build_expense_journal_lines` and the COGS/waste/restock syncs skip
   rows that have no resolvable cost. The source SUM must apply the
   same skip predicate (e.g. "resolvable cost exists" for COGS classes)
   or the identity will report false positives. Documenting the exact
   skip predicate per class is part of the Phase 5 spec.

4. **Capped source amounts.** `order_shipping_release` uses
   `min(shipping_fee, held_in_2200)`, not raw `shipping_fee`. The
   validator must replicate `_held_shipping_for_order` for the source
   side, or it will produce false deltas for partial-hold orders.

5. **Invalidation filter.** `payment_transaction` and any class
   derived from `payment_transactions` must exclude rows with
   `invalidated_at IS NOT NULL` (use `_invalidation_filter` from
   `baker.models.payment_transaction`).

6. **Nested settlements.** `expense_settlement` source rows live inside
   `events.data.settlements[]`, not in a dedicated table. The source
   SUM is a JSON aggregation over expense events whose
   `payment_method='Nợ'`. Phase 5 must decide whether to compute this
   in SQL (json_each) or in Python; the per-class result must still be
   a single lump-sum number.

7. **Tolerance.** Use `DEBIT_CREDIT_TOLERANCE` (0.005) for all classes
   to stay consistent with the existing checks. `REVENUE_UPDATE_TOLERANCE`
   is the same value (0.005) so no class needs a different threshold.

## 7. Traceability

- **Requirements doc**: `agent-teams/requirements/artifacts/2026-07-14-dg245-source-ledger-reconciliation.md`
  - §4 In Scope item: "New validator check `source_ledger_totals` (lump-sum per event class) covering: `expense`/`expense_settlement`, `order`/`order_cogs`/`order_shipping_hold`/`order_shipping_release`, `payment_transaction`, and inventory-derived `waste_cogs`/`negative_sale_cogs`/`restock_inflow`." → all 12 classes in §4 covered by this map.
  - FR8: "per-class amount identity defined" → §3.1–§3.10 define each identity; §4 gives the SUM expressions.
  - AC6: "per-class amount identity defined (partial — full verification after Phase 5)" → this doc is the partial definition; Phase 5 implements and fully verifies.
- **Verification**: reviewer confirms the 12-class map matches (a) the live
  `journal_entries.source_type` distribution (§2) and (b) every `_sync_*`
  function in `journal_sync.py` + the `order_shipping_hold` backfill in
  `schema.py`. No code change in this phase.