# Unknown payment destinations (DG-444)

## Staff workflow

1. Open an order and record an incoming deposit, payment, or full payment.
2. Select **Chưa rõ nơi nhận** only when receipt of the money is confirmed but cash versus bank cannot yet be verified. Enter the amount and receipt date as usual. The receipt immediately reduces the order's outstanding balance.
3. Find unresolved receipts in **Kế toán → Đối soát nơi nhận**. Search by order reference or customer name (submit the search field), refresh, and use previous/next pages as needed. The header shows the matching unresolved count and amount.
4. Verify the destination, then select **Xác nhận nơi nhận** and choose cash, TK Phượng VCB, or TK Ân VCB. Confirm the dialog. The same action is available from the order's transaction detail sheet.

Cash assignment requires a currently open cash drawer. If none is open, open one and retry. The cash movement belongs to that drawer, not a drawer closed since the original receipt. Bank assignment requires one of the two specific accounts; an unallocated bank transfer is not a verified destination.

## Accounting and audit

- Account **1400 — Tiền nhận chưa rõ nơi nhận** is an asset under 1000, separate from cash and bank-unallocated account 1290.
- The original receipt debits 1400 and credits the existing deposit/shipping liabilities. Existing order balance, shipping allocation, and revenue recognition rules continue to apply.
- Assignment leaves the original receipt, timestamp, photo links, and liability posting intact. A separate `payment_destination` journal debits 1101, 1210, or 1220 and credits 1400 at verification time. It does not create a second payment or recognize revenue again.
- Cash destination movements appear as cash in/out, with the order reference and customer name, in the drawer. Closed drawer balances and snapshots are not rewritten.
- The receipt exposes `destinationStatus`, `destinationResolvedAt`, and `destinationResolvedBy`. Order history records the receipt ID and verified destination using the authenticated actor.
- Assignment is atomic with its journal and audit. Exact retries return the original result; conflicting assignments return 409. Missing original neutral postings must be repaired before assignment.

## Corrections and boundaries

Unknown-origin receipt financial fields are immutable, including after resolution. If the amount, type, date, or verified destination is wrong, invalidate the receipt and enter a replacement. Notes and photo attachments remain available through their APIs. Hard deletion is prohibited to retain audit history.

Invalidation and restoration of a resolved receipt post compensating destination movements. Cash corrections require the current open drawer; they do not rewrite a closed drawer. A failed posting rolls back the receipt state change. Invalidated receipts are excluded from the unresolved list and paid total.

POS checkout, refunds, held `tien_rut`, automatic bank matching, historical backfill, and existing DG-244 bank-routing defaults are unchanged. An unknown bank account for a known transfer still uses 1290; it is not an unknown cash-or-bank destination.

The assignment menu is an immediate confirmed action, not a draft form. Its asynchronous busy/error state is keyed by order and receipt. Order receipt fields retain their existing context-keyed, authenticated-session draft lifecycle.

## API

- `POST /api/orders/{ref}/transactions`: `method: "unknown"`, positive finite amount, type `deposit`, `payment`, or `full_payment`, and no `payment_source`.
- `GET /api/payment-destinations?search=&limit=50&offset=0`: paginated items with order/customer identity, `total`, `has_more`, and `unresolvedAmount` for the matching set.
- `POST /api/orders/{ref}/transactions/{id}/destination`: `{"method":"cash"}` or `{"method":"transfer","payment_source":"TK Ân VCB"}` (also supports TK Phượng VCB).

Existing authentication policy applies. API callers cannot supply the resolution actor or timestamp.

## Upgrade and verification

Back up the existing SQLite database using the SQLite backup API (including committed WAL contents) **before starting the upgraded backend**. Verify SQLite ≥ 3.35.0. Migration 106 adds resolution metadata, a partial unresolved index, and account 1400, without changing historical receipts.

Backend tests must use `PYTHONPATH=src` in ticket worktrees when the shared Python environment's editable package points to the canonical checkout. Relevant tests are `tests/test_unknown_payment_destination.py`, existing payment-source/invalidation/journal tests, and schema tests. Client tests cover API serialization, operation isolation and retry, draft retention, receipt choices, reconciliation UI, and drawer classification. Automated tests do not substitute for human UAT.
