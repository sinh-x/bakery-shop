# Accounting Journal Reference

> Date: 2026-06-26
> Ticket: DG-198 (Phase 7)
> Source of truth: `src/baker/services/journal_sync.py`, `src/baker/db/schema.py`

This document lists every business action that generates a double-entry
journal entry, with the debit/credit account mapping for each. Account codes
refer to the chart of accounts seeded in `SEED_CHART_OF_ACCOUNTS`
(`src/baker/db/schema.py:1504`).

## Chart of Accounts (Reference)

| Code | Name (VN) | Type | Parent |
|------|-----------|------|--------|
| 1000 | Tài sản | asset | — |
| 1100 | Tiền mặt (Cash on Hand) | asset | 1000 |
| 1200 | Tài khoản ngân hàng (Bank Account) | asset | 1000 |
| 1300 | Hàng tồn kho (Inventory) | asset | 1000 |
| 1500 | Phải thu khách hàng (Accounts Receivable) | asset | 1000 |
| 2000 | Nợ phải trả | liability | — |
| 2100 | Tiền khách đặt cọc (Customer Deposits) | liability | 2000 |
| 2200 | Tiền ship bus giữ hộ (Bus Shipping Held) | liability | 2000 |
| 2300 | Phải trả nhân viên (Staff Payables) | liability | 2000 |
| 2400 | Tiền rút tạm giữ (Tien Rut Held) | liability | 2000 |
| 3000 | Vốn chủ sở hữu | equity | — |
| 3100 | Vốn chủ sở hữu (Owner's Equity) | equity | 3000 |
| 4000 | Doanh thu | income | — |
| 4100 | Doanh thu bán hàng (Order Revenue) | income | 4000 |
| 5000 | Chi phí | expense | — |
| 5100 | Nguyên liệu (Ingredients) | expense | 5000 |
| 5200 | Bao bì (Packaging) | expense | 5000 |
| 5300 | Vận chuyển (Delivery/Shipping) | expense | 5000 |
| 5400 | Điện/nước (Utilities) | expense | 5000 |
| 5500 | Dụng cụ (Tools) | expense | 5000 |
| 5600 | Sửa chữa (Equipment Maintenance) | expense | 5000 |
| 5700 | Lương/phụ cấp (Staff Salary) | expense | 5000 |
| 5800 | Khác (Other Expenses) | expense | 5000 |
| 5900 | Giá vốn hàng bán (COGS) | expense | 5000 |

## Asset Account Selection

The "Asset" account on the credit side of inflows (and debit side of
outflows) is resolved from the payment transaction's `method` field via
`PAYMENT_METHOD_TO_ASSET_CODE`:

| `method` | Asset account |
|----------|---------------|
| `cash` | 1100 (Cash on Hand) |
| `card` | 1100 (Cash on Hand) |
| `transfer` | 1200 (Bank Account) |

When the method is unknown, the default is `1100`.

---

## 1. Payment Transactions

Payment transactions are recorded in `payment_transactions` and synced to a
`source_type = 'payment_transaction'` journal entry by
`_sync_payment_journal()` / `_build_payment_journal_lines()`.

The transaction `type` determines whether it is an inflow (customer pays in)
or an outflow (cash returns to the customer).

### 1.1 Deposit / Payment / Full Payment (inflow)

> Triggered by `type ∈ {deposit, payment, full_payment}`.

Customer money flows into the shop. The asset account is debited and
Customer Deposits (2100) is credited.

**Non-bus order (or bus order with no shipping fee):**

| Action | Debit | Credit |
|--------|-------|--------|
| Customer deposit/payment | Asset (1100 or 1200) | 2100 (Customer Deposits) |

**Bus order with `shipping_fee > 0`** — the inflow is split so the shipping
portion is held in 2200 (Bus Shipping Held) up to the order's `shipping_fee`
across all payments; the remainder goes to 2100:

| Action | Debit | Credit |
|--------|-------|--------|
| Customer deposit (bus, shipping split) | Asset (1100/1200) | 2100 (deposit portion) + 2200 (shipping portion) |

The shipping portion = `min(amount, max(0, shipping_fee − already_held))`.
Only the first payments that cover shipping allocate to 2200; later payments
go entirely to 2100.

### 1.2 Refund (outflow)

> Triggered by `type = refund`. Member of `PAYMENT_OUTFLOW_TYPES`.

Cash returns to the customer. Customer Deposits (2100) is debited and the
asset account is credited — the reverse of a normal deposit.

| Action | Debit | Credit |
|--------|-------|--------|
| Refund to customer | 2100 (Customer Deposits) | Asset (1100/1200) |

Outflows are **not split** for bus shipping at payment time; the held shipping
balance in 2200 is preserved until the delivery release entry (§3.3).

### 1.3 Tien Rut — cash withdrawal (outflow)

> Triggered by `type = tien_rut`. Member of `PAYMENT_OUTFLOW_TYPES`.
> Implemented in DG-198 Phase 2 (FR1).

`tien_rut` debits **2400 (Tien Rut Held)** instead of 2100, so Customer
Deposits is not overdrawn while revenue recognition is pending. The amount is
held in 2400 until the order is delivered, at which point the revenue entry
clears 2400 (§3.2).

| Action | Debit | Credit |
|--------|-------|--------|
| Tien rut (cash withdrawal) | 2400 (Tien Rut Held) | Asset (1100/1200) |

**Guardrail (DG-198 Phase 3 / FR2):** the API rejects `tien_rut` creation when
`amount > available`, where
`available = total_paid_excl_outflows − total_outflows`. The check runs inside
the same DB transaction as payment creation (NFR2 — no race-condition window).
On rejection the API returns HTTP 422 with message
`"Số tiền rút vượt quá số dư cọc hiện có"`.

### 1.4 Invalidation / Restoration of a payment transaction

Payment transactions can be **invalidated** (`POST /{ref}/transactions/{txn_id}/invalidate`)
and **restored** (`POST /{ref}/transactions/{txn_id}/restore`). Both re-sync
the journal entry via `_sync_payment_journal` with the `deleted` flag
semantics below (see §6 for the full invalidation/reversal model).

- **Invalidate:** sets `invalidated_at`/`invalidated_by`, then reverses (locked)
  or deletes (unlocked) the `payment_transaction` journal entry.
- **Restore:** clears `invalidated_at`/`invalidated_by` and re-creates the
  journal entry. A prior locked reversal is left intact so the locked period's
  books are preserved.

---

## 2. Expense Events

Expense events (`events` rows) are synced to a `source_type = 'expense'`
journal entry by `_sync_expense_journal()` / `_build_expense_journal_lines()`.

### 2.1 Operating expense (non-inventory category)

> `category ∉ INVENTORY_PURCHASE_CATEGORIES` (i.e. not "Nguyên liệu" /
> "Bao bì"). The debit account is resolved from
> `EXPENSE_CATEGORY_TO_ACCOUNT_CODE`.

| Action | Debit | Credit |
|--------|-------|--------|
| Operating expense | Expense account (5100–5800 per category) | Payment account (see below) |

Expense account by category:

| Category | Account |
|----------|---------|
| Nguyên liệu | 5100 |
| Bao bì | 5200 |
| Vận chuyển | 5300 |
| Điện/nước | 5400 |
| Dụng cụ | 5500 |
| Sửa chữa | 5600 |
| Lương/phụ cấp | 5700 |
| Khác | 5800 |

### 2.2 Inventory purchase (Nguyên liệu / Bao bì)

> `category ∈ INVENTORY_PURCHASE_CATEGORIES = {"Nguyên liệu", "Bao bì"}`.
> The cost is capitalized into Inventory (1300) until goods are sold/wasted.

| Action | Debit | Credit |
|--------|-------|--------|
| Inventory purchase | 1300 (Inventory) | Payment account (see below) |

### 2.3 Expense payment account (credit side)

The credit account is resolved from `payment_source` via
`EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE`:

| `payment_source` | Credit account |
|------------------|----------------|
| Shop tiền mặt | 1100 (Cash on Hand) |
| TK Phượng VCB | 1200 (Bank Account) |
| TK Ân VCB | 1200 (Bank Account) |
| Nhân viên ứng trước (staff advance) | 2300 (Staff Payables) sub-account per staff name |

When `payment_source = "Nhân viên ứng trước"`, a per-staff sub-account is
created under 2300 via `_ensure_staff_payable_sub_account()`. This records a
staff advance: the shop owes the staff member the advanced amount.

### 2.4 Staff advance (special case)

> Triggered by `payment_source = "Nhân viên ứng trước"`.
> Implemented in DG-194 (reclassified from asset 1400 to liability 2300).

| Action | Debit | Credit |
|--------|-------|--------|
| Staff advance (expense paid via staff advance) | Expense account (5100–5800) or 1300 (inventory) | 2300 (Staff Payables) sub-account |

The staff payables sub-account is a liability: the shop owes the staff member
the advanced amount. When the staff is later reimbursed, a separate
transaction clears the sub-account (out of scope for this doc).

---

## 3. Order Delivery (Revenue Recognition)

When an order is delivered/completed, `_sync_delivered_order_journal()` creates
up to three journal entries: the revenue entry, the bus shipping release
entry, and the COGS entry.

### 3.1 Revenue entry — paid order

> `source_type = 'order'`. Implemented in DG-198 Phase 4 (FR3).

For a paid order (any deposits held), a revenue entry is **always** created
(replacing the previous "skip when net <= 0" behaviour). It debits Customer
Deposits for the full deposit balance still held, credits Tien Rut Held (2400)
for the tien_rut held (clearing the holding), and credits Order Revenue (4100)
for the net revenue.

Definitions:
- `deposit_balance = max(0, deposits_in − refund_total − shipping_held)`
  where `deposits_in = total_paid_excl_outflows`,
  `refund_total = total_outflows − tien_rut_held`,
  `shipping_held = shipping_fee` for bus orders (else 0).
- `credit_2400 = min(tien_rut_held, deposit_balance)`
- `revenue_amount = max(0, deposit_balance − tien_rut_held)`

| Action | Debit | Credit |
|--------|-------|--------|
| Revenue recognition (paid order) | 2100 (Customer Deposits) = deposit_balance | 2400 (Tien Rut Held) = credit_2400 *(if > 0)* + 4100 (Order Revenue) = revenue_amount *(if > 0)* |

Zero-amount lines are omitted so the entry always balances. This entry clears
the 2100 deposit balance and the 2400 tien_rut holding in one balanced entry.

### 3.2 Revenue entry — unpaid order (Accounts Receivable)

> `source_type = 'order'`. Applies when `total_paid_excl_outflows <= 0` and
> `total_price > 0`.

For a truly unpaid order (no deposits, no outflows), the full order total is
recorded as a customer debt (Accounts Receivable).

| Action | Debit | Credit |
|--------|-------|--------|
| Revenue recognition (unpaid order) | 1500 (Accounts Receivable) = total_price | 4100 (Order Revenue) = total_price |

Bus shipping exclusion does not apply here because there were no deposits to
hold shipping in 2200; the full order total remains a receivable. When
`deposit_balance <= 0` but deposits existed (nothing held, e.g. fully
refunded), no entry is created (nothing to recognise).

### 3.3 Bus shipping release (delivery)

> `source_type = 'order_shipping_release'`. Implemented in DG-191.

For a delivered bus order with `shipping_fee > 0`, the shipping fee held in
2200 is released to the cash asset account (1100).

| Action | Debit | Credit |
|--------|-------|--------|
| Bus shipping release | 2200 (Bus Shipping Held) = release_amount | 1100 (Cash on Hand) = release_amount |

`release_amount = min(shipping_fee, held_in_2200)`. Non-bus orders or
`shipping_fee <= 0` produce no entry. The entry is idempotent: an existing
entry matching the expected release amount (within tolerance) is left
untouched.

### 3.4 COGS at sale

> `source_type = 'order_cogs'`.

At delivery, the cost of goods sold is recognised by debiting COGS and
crediting Inventory for `Σ(cost_at_sale × qty)` across non-extra, non-gift
order items.

| Action | Debit | Credit |
|--------|-------|--------|
| COGS at sale | 5900 (COGS) = total_cogs | 1300 (Inventory) = total_cogs |

`cost_at_sale` is populated at delivery time from `cost_history` (via
`resolve_product_cost`), applying the documented baseline fallback when no
historical cost is in effect. The entry is created once per order
(idempotent: skipped when an `order_cogs` entry already exists).

---

## 4. Waste COGS

> `source_type = 'waste_cogs'`. Triggered by `_sync_waste_cogs_journal()` when
> stock is wasted.

| Action | Debit | Credit |
|--------|-------|--------|
| Waste COGS | 5900 (COGS) = unit_cost × quantity | 1300 (Inventory) = unit_cost × quantity |

`unit_cost` is resolved via `resolve_product_cost` (cost_history → baseline
fallback). When the resolved cost is zero, no entry is created (consistent
with sale COGS behaviour for zero-cost items). Idempotent: skipped when a
`waste_cogs` entry already exists for the stock movement.

---

## 5. Repair / Backfill Commands

### 5.1 `baker repair-order-revenue`

Re-syncs the `source_type = 'order'` revenue entry for orders whose revenue
entry is missing or stale (calls `_reconcile_order_revenue_entry`). Produces
the same debit/credit lines as §3.1 / §3.2.

### 5.2 `baker repair-tien-rut-gap` (DG-198 Phase 5)

Backfills existing orders whose `tien_rut` payment journal entries were
recorded against 2100 (pre-fix) instead of 2400. For each affected order it:

1. Re-syncs the `tien_rut` `payment_transaction` journal entry → routes to 2400
   via `_sync_payment_journal` (§1.3).
2. Reconciles the revenue entry → clears 2400 via
   `_reconcile_order_revenue_entry` (§3.1).

Idempotent (NFR3): detection excludes orders already on 2400, and the
sync/reconcile helpers are themselves idempotent. Supports `--order-id`,
`--all`, `--dry-run`.

---

## 6. Invalidation / Reversal Model

Every journal sync helper supports a `deleted` flag that reverses or removes
the entry when the source transaction is removed or invalidated. The model is
shared across all source types.

| Condition | Behaviour |
|-----------|-----------|
| Existing entry is **unlocked** | `_delete_journal_entry_cascade()` — delete the entry and its lines outright |
| Existing entry is **locked** | `_reverse_journal_entry()` — create a reversal entry that swaps debit↔credit, preserving the original `transaction_date` (same-period correction) |
| No existing entry | No-op |

A **reversal entry** has `description = "Reversal: <original>"`, the same
`source_type`/`source_id` as the original, and swaps every line's debit and
credit. Locked entries are never deleted — only reversed — so the locked
period's books are preserved.

### 6.1 Per-source-type invalidation behaviour

| Source type | Invalidation trigger | Effect |
|-------------|----------------------|--------|
| `payment_transaction` | `POST .../invalidate` or transaction delete | Reverse (locked) / delete (unlocked) the entry; re-sync on restore |
| `expense` | Event delete (`deleted_at` set) | Reverse (locked) / delete (unlocked) the entry |
| `order` (revenue) | Not directly invalidatable; re-synced on order re-delivery / repair | Reverse (locked) / delete (unlocked) stale entry, then create corrected entry |
| `order_shipping_release` | Re-synced on order re-delivery / shipping_fee edit | Same as `order` |
| `order_cogs` | Re-synced on order re-delivery; skipped if already exists | Reverse (locked) / delete (unlocked) stale entry, then recreate |
| `waste_cogs` | Not directly invalidatable; idempotent (skipped if exists) | — |

### 6.2 Invalidation vs. deletion

- **Invalidation** (`invalidated_at` set on `payment_transactions`): the row is
  retained for audit; downstream totals (`total_paid_excl_outflows`,
  `total_outflows`) exclude invalidated rows; the journal entry is
  reversed/deleted.
- **Deletion**: the transaction row is removed and the journal entry is
  reversed/deleted. Restoring an invalidated transaction re-creates the
  journal entry using the transaction's `created_at` for `transaction_date`; a
  prior locked reversal is left intact.

---

## 7. transaction_date Semantics

Each journal entry carries a `transaction_date` representing the business
event date (FR4/FR11), used by reports and lock filters:

| Source type | transaction_date source |
|-------------|-------------------------|
| `payment_transaction` | `payment_transactions.created_at` |
| `expense` | `events.timestamp` |
| `order` (revenue) | `orders.due_date` (fallback `created_at`) |
| `order_shipping_release` | `orders.due_date` (fallback `created_at`) |
| `order_cogs` | `orders.due_date` (fallback `created_at`) |
| `waste_cogs` | `stock_movements.created_at` |

Reversal entries preserve the original entry's `transaction_date` so the
correction relates to the same period as the entry being reversed.

---

## 8. Validation Checks

`baker validate-accounts` runs registered checks in
`src/baker/services/accounting_validation.py`. The deposit-revenue integrity
check (DG-198 Phase 6, check #15) verifies the balance equation for every
`source_type = 'order'` revenue entry with a 2100 debit:

```
debit_2100 = credit_2400 + credit_4100   (within tolerance)
```

AR-only entries (debit 1500, no 2100) are excluded. A gap (2400 credit missing
or understated) is flagged with the correct gap amount.

---

## 9. Non-Blocking Sync (NFR1)

All journal sync calls are wrapped in `run_journal_sync()`, a fire-and-forget
wrapper that logs and increments the `journal_sync_failures` counter on
failure but never raises. Accounting failures never block the primary business
operation; the gap is observable through the `/api/health` endpoint.